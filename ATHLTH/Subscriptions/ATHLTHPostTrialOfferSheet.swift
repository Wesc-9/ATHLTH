import Foundation
import StoreKit
import Supabase
import SwiftUI
import UIKit

/// Offered on exactly one eligible foreground visit for an account, and
/// only when an actual App Store Connect code is available in the backend.
/// No local UserDefaults reset can reissue a once-presented offer.
struct ATHLTHPostTrialOfferWindow: Identifiable {
    let id = UUID()
    let expiresAt: Date
}

@MainActor
enum ATHLTHPostTrialOfferClient {
    private struct Request: Encodable {
        let action: String
    }
    private struct Response: Decodable {
        let status: String
        let expiresAt: String?
        let code: String?
    }

    private static func request(_ action: String) async throws -> Response {
        try await SupabaseEnvironment.client.functions.invoke(
            "post-trial-offer",
            options: FunctionInvokeOptions(body: Request(action: action))
        )
    }

    static func presentOnce() async -> ATHLTHPostTrialOfferWindow? {
        do {
            let reply = try await request("present")
            guard reply.status == "new", let raw = reply.expiresAt else {
                return nil
            }
            let format = ISO8601DateFormatter()
            format.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            guard let end = format.date(from: raw), end > Date() else {
                return nil
            }
            return ATHLTHPostTrialOfferWindow(expiresAt: end)
        } catch {
            // A missing code inventory, disabled campaign or unavailable
            // network must not show a fake discount or block regular access.
            return nil
        }
    }

    static func claim() async -> String? {
        do {
            let reply = try await request("claim")
            guard reply.status == "claimed",
                  let code = reply.code, !code.isEmpty else {
                return nil
            }
            return code
        } catch {
            return nil
        }
    }
}

struct ATHLTHPostTrialOfferSheet: View {
    let window: ATHLTHPostTrialOfferWindow
    @Environment(\.dismiss) private var dismiss

    @State private var isClaiming = false
    @State private var claimedCode: String?
    @State private var showAppleRedemption = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Image(systemName: "gift")
                        .font(.system(size: 31, weight: .medium))
                        .foregroundStyle(OnboardingTheme.accent)
                        .frame(width: 66, height: 66)
                        .background(
                            OnboardingTheme.accent.opacity(0.13),
                            in: RoundedRectangle(cornerRadius: 22)
                        )

                    Text(ATHLTHLocalization.choose(
                        english: "A little more time with ATHLTH+",
                        norwegian: "Et ekstra tilbud på ATHLTH+"
                    ))
                    .font(.system(size: 29, weight: .semibold, design: .rounded))
                    .multilineTextAlignment(.center)

                    Text(ATHLTHLocalization.choose(
                        english: "Your trial has ended. You have one opportunity to claim an App Store offer code.",
                        norwegian: "Prøveperioden er avsluttet. Du har én mulighet til å hente en tilbudskode fra App Store."
                    ))
                    .font(.subheadline)
                    .foregroundStyle(OnboardingTheme.mutedText)
                    .multilineTextAlignment(.center)

                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let seconds = max(
                            0,
                            Int(ceil(window.expiresAt.timeIntervalSince(context.date)))
                        )
                        VStack(spacing: 5) {
                            Text(ATHLTHLocalization.choose(
                                english: "Time left to claim",
                                norwegian: "Tid igjen til å hente tilbudet"
                            ))
                            .font(.caption)
                            .foregroundStyle(OnboardingTheme.mutedText)

                            Text(String(format: "%02d:%02d", seconds / 60, seconds % 60))
                                .font(.system(size: 37, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(OnboardingTheme.primaryText)

                            if seconds == 0 && claimedCode == nil {
                                Text(ATHLTHLocalization.choose(
                                    english: "Your claim window has closed.",
                                    norwegian: "Tiden for å hente tilbudet er ute."
                                ))
                                .font(.caption)
                                .foregroundStyle(OnboardingTheme.mutedText)
                            }

                            Button {
                                claimOffer()
                            } label: {
                                if isClaiming {
                                    ProgressView()
                                        .frame(maxWidth: .infinity)
                                } else {
                                    Text(ATHLTHLocalization.choose(
                                        english: "Claim App Store offer",
                                        norwegian: "Hent App Store-tilbudet"
                                    ))
                                    .frame(maxWidth: .infinity)
                                }
                            }
                            .buttonStyle(OnboardingPrimaryButtonStyle())
                            .disabled(seconds == 0 || isClaiming || claimedCode != nil)
                            .padding(.top, 6)
                        }
                    }

                    if let claimedCode {
                        VStack(spacing: 9) {
                            Text(ATHLTHLocalization.choose(
                                english: "Offer code copied",
                                norwegian: "Tilbudskoden er kopiert"
                            ))
                            .font(.headline)
                            Text(claimedCode)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                            Button(ATHLTHLocalization.choose(
                                english: "Copy code again",
                                norwegian: "Kopier kode på nytt"
                            )) {
                                UIPasteboard.general.string = claimedCode
                            }
                            .buttonStyle(.bordered)

                            Button(ATHLTHLocalization.choose(
                                english: "Redeem with Apple",
                                norwegian: "Løs inn hos Apple"
                            )) {
                                showAppleRedemption = true
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }

                    if let message {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(OnboardingTheme.mutedText)
                            .multilineTextAlignment(.center)
                    }

                    Text(ATHLTHLocalization.choose(
                        english: "Apple determines your final discounted price, eligibility and subscription renewal terms. Check the App Store confirmation before accepting. The 15 minutes applies to claiming the code in ATHLTH, not its Apple redemption expiry.",
                        norwegian: "Apple avgjør rabattpris, hvem som kan bruke tilbudet og abonnementsvilkårene. Kontroller App Store-bekreftelsen før du godtar. De 15 minuttene gjelder å hente koden i ATHLTH, ikke utløpsdatoen hos Apple."
                    ))
                    .font(.caption2)
                    .foregroundStyle(OnboardingTheme.mutedText)
                    .multilineTextAlignment(.center)
                }
                .padding(24)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
            .background(OnboardingBackground().ignoresSafeArea())
            .navigationTitle("ATHLTH+")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(ATHLTHLocalization.choose(
                        english: "Close",
                        norwegian: "Lukk"
                    )) { dismiss() }
                }
            }
            .offerCodeRedemption(isPresented: $showAppleRedemption)
        }
        .preferredColorScheme(.light)
    }

    private func claimOffer() {
        guard claimedCode == nil, !isClaiming, Date() < window.expiresAt else {
            return
        }
        isClaiming = true
        Task {
            let result = await ATHLTHPostTrialOfferClient.claim()
            isClaiming = false
            if let result {
                claimedCode = result
                UIPasteboard.general.string = result
                showAppleRedemption = true
            } else {
                message = ATHLTHLocalization.choose(
                    english: "The offer could not be claimed. The code may be unavailable or the claim period has ended.",
                    norwegian: "Kunne ikke hente tilbudet. Koden kan være utilgjengelig, eller tidsfristen kan ha gått ut."
                )
            }
        }
    }
}
