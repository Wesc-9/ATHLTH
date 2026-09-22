import StoreKit
import SwiftUI

struct SubscriptionOfferView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var subscriptionStore: SubscriptionStore
    @EnvironmentObject private var accountService: SupabaseAccountService

    let onPurchaseCompleted: () -> Void

    @State private var selectedProductID: String?
    @State private var legalDocument: LegalDocumentKind?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    hero
                    benefits

                    if subscriptionStore.isLoading {
                        ProgressView("Loading plans…")
                            .tint(OnboardingTheme.accent)
                            .foregroundStyle(OnboardingTheme.mutedText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 28)
                    } else if subscriptionStore.products.isEmpty {
                        unavailableState
                    } else {
                        plans
                        purchaseButton
                    }

                    if let errorMessage = subscriptionStore.errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }

                    trialEscape
                    purchaseUtilities
                    legalLinks
                }
                .padding(.horizontal, 24)
                .padding(.top, 18)
                .padding(.bottom, 32)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
            .background(OnboardingBackground().ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(.ultraThinMaterial, in: Circle())
                            .overlay {
                                Circle()
                                    .stroke(OnboardingTheme.border, lineWidth: 1)
                            }
                    }
                    .accessibilityLabel("Close and continue free trial")
                }
            }
        }
        .preferredColorScheme(.dark)
        .sheet(item: $legalDocument) { document in
            NavigationStack {
                LegalDocumentView(kind: document)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") {
                                legalDocument = nil
                            }
                        }
                    }
            }
        }
        .task {
            await subscriptionStore.loadProducts()

            if selectedProductID == nil {
                selectedProductID =
                    subscriptionStore.product(for: SubscriptionStore.yearlyProductID)?.id ??
                    subscriptionStore.products.first?.id
            }
        }
    }

    private var hero: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(OnboardingTheme.accent)
                .frame(width: 72, height: 72)
                .background(
                    OnboardingTheme.accent.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 24, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(OnboardingTheme.accent.opacity(0.24), lineWidth: 1)
                }

            Text("Unlock ATHLTH+")
                .font(.system(size: 34, weight: .bold))
                .multilineTextAlignment(.center)

            Text("Choose Monthly or Yearly for the full ATHLTH experience.")
                .font(.subheadline)
                .foregroundStyle(OnboardingTheme.mutedText)
                .multilineTextAlignment(.center)

            if session.subscriptionAccess.trialIsActive {
                Text("Your 7-day free access is already active.")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(OnboardingTheme.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        OnboardingTheme.accent.opacity(0.10),
                        in: Capsule()
                    )
            }
        }
        .padding(.top, 4)
    }

    private var benefits: some View {
        OnboardingCard {
            VStack(alignment: .leading, spacing: 15) {
                benefit("Automatic Health background sync", icon: "heart.fill")
                benefit("Advanced training and planning tools", icon: "calendar.badge.clock")
                benefit("Full Apple Watch integration", icon: "applewatch")
                benefit("Expanded progress and recovery features", icon: "chart.line.uptrend.xyaxis")
            }
        }
    }

    @ViewBuilder
    private var plans: some View {
        VStack(spacing: 12) {
            if let yearly = subscriptionStore.product(for: SubscriptionStore.yearlyProductID) {
                planCard(yearly)
            }

            if let monthly = subscriptionStore.product(for: SubscriptionStore.monthlyProductID) {
                planCard(monthly)
            }

            ForEach(
                subscriptionStore.products.filter {
                    $0.id != SubscriptionStore.yearlyProductID &&
                    $0.id != SubscriptionStore.monthlyProductID
                },
                id: \.id
            ) { product in
                planCard(product)
            }
        }
    }

    private var purchaseButton: some View {
        Button {
            guard
                let selectedProductID,
                let product = subscriptionStore.product(for: selectedProductID)
            else {
                return
            }

            Task {
                guard let userID = accountService.currentUserID else {
                    return
                }

                if await subscriptionStore.purchase(
                    product,
                    appAccountToken: userID
                ) {
                    onPurchaseCompleted()
                }
            }
        } label: {
            HStack {
                Spacer()

                if subscriptionStore.purchaseInProgress {
                    ProgressView()
                } else if
                    let selectedProductID,
                    let product = subscriptionStore.product(for: selectedProductID) {
                    Text("Subscribe · \(product.displayPrice)")
                        .font(.headline)
                } else {
                    Text("Choose a plan")
                        .font(.headline)
                }

                Spacer()
            }
        }
        .buttonStyle(OnboardingPrimaryButtonStyle())
        .disabled(
            selectedProductID == nil ||
            subscriptionStore.purchaseInProgress
        )
    }

    private var trialEscape: some View {
        VStack(spacing: 7) {
            if session.subscriptionAccess.trialIsActive {
                if let trialEndsAt = session.subscriptionAccess.trialEndsAt {
                    Text("Not ready to subscribe? Close this screen and keep ATHLTH+ free through \(trialEndsAt.formatted(date: .abbreviated, time: .omitted)).")
                        .font(.caption)
                        .foregroundStyle(OnboardingTheme.mutedText)
                        .multilineTextAlignment(.center)
                } else {
                    Text("Not ready to subscribe? Close this screen and continue your 7-day ATHLTH+ trial.")
                        .font(.caption)
                        .foregroundStyle(OnboardingTheme.mutedText)
                        .multilineTextAlignment(.center)
                }

                Text("No subscription starts automatically. Purchasing a plan now starts the App Store subscription now.")
                    .font(.caption2)
                    .foregroundStyle(OnboardingTheme.faintText)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var purchaseUtilities: some View {
        Button {
            Task {
                if await subscriptionStore.restorePurchases() {
                    onPurchaseCompleted()
                }
            }
        } label: {
            if subscriptionStore.restoreInProgress {
                HStack(spacing: 7) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Restoring…")
                }
            } else {
                Text("Restore Purchases")
            }
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(OnboardingTheme.mutedText)
        .disabled(subscriptionStore.restoreInProgress)
    }

    private var legalLinks: some View {
        HStack(spacing: 16) {
            Button("Terms of Service") {
                legalDocument = .terms
            }

            Button("Privacy Policy") {
                legalDocument = .privacy
            }
        }
        .font(.caption2)
        .foregroundStyle(OnboardingTheme.faintText)
    }

    private var unavailableState: some View {
        VStack(spacing: 9) {
            Image(systemName: "creditcard")
                .font(.title2)
                .foregroundStyle(OnboardingTheme.accent)

            Text("Plans aren’t available yet")
                .font(.headline)

            Text("Monthly and Yearly App Store plans will appear here when they are available.")
                .font(.caption)
                .foregroundStyle(OnboardingTheme.mutedText)
                .multilineTextAlignment(.center)

            Button("Continue free trial") {
                dismiss()
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(OnboardingTheme.accent)
            .padding(.top, 4)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(
            Color.white.opacity(0.07),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(OnboardingTheme.border, lineWidth: 1)
        }
    }

    @ViewBuilder
    private func planCard(_ product: Product) -> some View {
        let selected = selectedProductID == product.id
        let yearly = product.id == SubscriptionStore.yearlyProductID

        Button {
            selectedProductID = product.id
        } label: {
            HStack(spacing: 14) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(
                        selected ? OnboardingTheme.accent : OnboardingTheme.mutedText
                    )

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(planTitle(for: product))
                            .font(.headline)
                            .foregroundStyle(.white)

                        if yearly {
                            Text("BEST VALUE")
                                .font(.system(size: 9, weight: .bold))
                                .tracking(0.8)
                                .foregroundStyle(.black)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(OnboardingTheme.accent, in: Capsule())
                        }
                    }

                    Text(product.displayPrice + planSuffix(for: product))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)

                    if yearly, let saving = yearlySavingsPercent {
                        Text("Save about \(saving)% compared with Monthly")
                            .font(.caption)
                            .foregroundStyle(OnboardingTheme.accent)
                    } else if product.id == SubscriptionStore.monthlyProductID {
                        Text("Flexible monthly billing")
                            .font(.caption)
                            .foregroundStyle(OnboardingTheme.mutedText)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(
                selected
                    ? OnboardingTheme.accent.opacity(0.11)
                    : Color.white.opacity(0.07),
                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(
                        selected
                            ? OnboardingTheme.accent.opacity(0.60)
                            : OnboardingTheme.border,
                        lineWidth: selected ? 1.4 : 1
                    )
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func benefit(_ title: String, icon: String) -> some View {
        HStack(spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(OnboardingTheme.accent)
                .frame(width: 30, height: 30)
                .background(
                    OnboardingTheme.accent.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )

            Text(title)
                .font(.subheadline)
                .foregroundStyle(.white)

            Spacer(minLength: 0)
        }
    }

    private var yearlySavingsPercent: Int? {
        guard
            let monthly = subscriptionStore.product(for: SubscriptionStore.monthlyProductID),
            let yearly = subscriptionStore.product(for: SubscriptionStore.yearlyProductID)
        else {
            return nil
        }

        let monthlyAnnual = monthly.price * Decimal(12)
        guard monthlyAnnual > 0, yearly.price < monthlyAnnual else {
            return nil
        }

        let ratio = NSDecimalNumber(decimal: yearly.price / monthlyAnnual).doubleValue
        return Int(((1 - ratio) * 100).rounded())
    }

    private func planTitle(for product: Product) -> String {
        switch product.id {
        case SubscriptionStore.monthlyProductID:
            return "Monthly"
        case SubscriptionStore.yearlyProductID:
            return "Yearly"
        default:
            return product.displayName
        }
    }

    private func planSuffix(for product: Product) -> String {
        switch product.id {
        case SubscriptionStore.monthlyProductID:
            return " / month"
        case SubscriptionStore.yearlyProductID:
            return " / year"
        default:
            return ""
        }
    }
}
