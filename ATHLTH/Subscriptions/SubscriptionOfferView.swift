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
    @State private var showProductDiagnostics = false
    @State private var purchaseFeedback: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    hero
                    featuredBenefits

                    if subscriptionStore.isLoading {
                        ProgressView(ATHLTHLocalization.choose(
                            english: "Loading plans…",
                            norwegian: "Laster abonnementer…"
                        ))
                            .tint(OnboardingTheme.accent)
                            .foregroundStyle(OnboardingTheme.mutedText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 28)
                    } else if subscriptionStore.products.isEmpty {
                        unavailableState
                    } else {
                        plans
                        appStoreCurrencyNote
                        purchaseButton
                        purchaseReassurance
                    }

                    if let errorMessage = subscriptionStore.errorMessage,
                       !subscriptionStore.products.isEmpty {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .multilineTextAlignment(.center)
                    }

                    if let purchaseFeedback {
                        Text(purchaseFeedback)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }

                    benefits
                    trialDisclosure
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
                            .foregroundStyle(OnboardingTheme.primaryText)
                            .frame(width: 34, height: 34)
                            .background(OnboardingTheme.card, in: Circle())
                            .overlay {
                                Circle()
                                    .stroke(OnboardingTheme.border, lineWidth: 1)
                            }
                    }
                    .accessibilityLabel(
                        session.subscriptionAccess.trialIsActive
                            ? "Close and continue free trial"
                            : "Close"
                    )
                }
            }
        }
        .preferredColorScheme(.light)
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
            await reloadPlans()
        }
        .task {
            // A Sandbox/App Store region may change while ATHLTH is open.
            // Requery StoreKit; never calculate an approximate FX conversion.
            for await _ in Storefront.updates {
                guard !Task.isCancelled else { break }
                await reloadPlans()
            }
        }
    }

    private func reloadPlans() async {
        await subscriptionStore.loadProducts()
        if subscriptionStore.product(
            for: selectedProductID ?? ""
        ) == nil {
            selectedProductID =
                subscriptionStore.product(for: SubscriptionStore.yearlyProductID)?.id ??
                subscriptionStore.products.first?.id
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

            Text("ATHLTH+")
                .font(.system(size: 36, weight: .bold))
                .multilineTextAlignment(.center)

            Text(ATHLTHLocalization.choose(
                english: "Smarter training with ATHLTH AI and Audio Coach.",
                norwegian: "Smartere trening med ATHLTH AI og Audio Coach."
            ))
                .font(.subheadline)
                .foregroundStyle(OnboardingTheme.mutedText)
                .multilineTextAlignment(.center)

            if session.subscriptionAccess.trialIsActive {
                Text(ATHLTHLocalization.choose(
                    english: "Your 7-day free access is already active.",
                    norwegian: "Din gratis prøveperiode på 7 dager er aktiv."
                ))
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

    /// Lead with tangible benefits rather than asking users to choose a
    /// billing period before they know what ATHLTH+ includes.
    private var featuredBenefits: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(
                ATHLTHLocalization.choose(
                    english: "AI training plans made for you",
                    norwegian: "AI-treningsplaner tilpasset deg"
                ),
                systemImage: "sparkles"
            )
            Label(
                ATHLTHLocalization.choose(
                    english: "Audio Coach for every workout",
                    norwegian: "Audio Coach under treningen"
                ),
                systemImage: "waveform"
            )
            Label(
                ATHLTHLocalization.choose(
                    english: "Scan equipment to find exercises",
                    norwegian: "Skann apparater og finn øvelser"
                ),
                systemImage: "camera.viewfinder"
            )
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(OnboardingTheme.primaryText)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            OnboardingTheme.card,
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
    }

    private var purchaseReassurance: some View {
        VStack(spacing: 5) {
            Label(
                ATHLTHLocalization.choose(
                    english: "Secure checkout through the App Store",
                    norwegian: "Sikker betaling gjennom App Store"
                ),
                systemImage: "lock.shield"
            )
            Text(ATHLTHLocalization.choose(
                english: "Auto-renews unless canceled. You can cancel in your App Store subscriptions.",
                norwegian: "Fornyes automatisk til du sier opp. Du kan avslutte under abonnementer i App Store."
            ))
        }
        .font(.caption2)
        .foregroundStyle(OnboardingTheme.mutedText)
        .multilineTextAlignment(.center)
    }

    private var benefits: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(ATHLTHLocalization.choose(
                english: "Included with ATHLTH+",
                norwegian: "Inkludert med ATHLTH+"
            ))
                .font(.caption.weight(.bold))
                .tracking(1.2)
                .foregroundStyle(OnboardingTheme.accent)

            VStack(spacing: 10) {
                benefit(
                    ATHLTHLocalization.choose(
                        english: "AI-generated training programs from your goals",
                        norwegian: "AI-genererte treningsprogrammer tilpasset målene dine"
                    ),
                    icon: "sparkles"
                )
                benefit(
                    ATHLTHLocalization.choose(
                        english: "AI Complete fills gaps without replacing your workouts",
                        norwegian: "AI Complete fyller hull i planen uten å erstatte øktene dine"
                    ),
                    icon: "wand.and.stars"
                )
                benefit(
                    ATHLTHLocalization.choose(
                        english: "Goal, date and availability-aware AI planning",
                        norwegian: "AI-planlegging etter mål, dato og tilgjengelighet"
                    ),
                    icon: "target"
                )
                benefit(
                    ATHLTHLocalization.choose(
                        english: "Audio Coach with pace, route progress and workout-step guidance",
                        norwegian: "Audio Coach med tempo, rutefremdrift og øktveiledning"
                    ),
                    icon: "waveform.and.mic"
                )
                benefit(
                    ATHLTHLocalization.choose(
                        english: "AI equipment scanning with matched exercises from your library",
                        norwegian: "AI-skanning av treningsapparater med øvelser fra biblioteket"
                    ),
                    icon: "camera.viewfinder"
                )
            }
        }
        .padding(16)
        .background(
            OnboardingTheme.card,
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(OnboardingTheme.border, lineWidth: 1)
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


    /// All amounts come from StoreKit's active App Store storefront. The iOS
    /// language, GPS position and device region must never drive a separate
    /// display-only currency conversion on a purchase screen.
    private var appStoreCurrencyNote: some View {
        VStack(spacing: 3) {
            Text(ATHLTHLocalization.choose(
                english: "Prices and currency are provided by your App Store.",
                norwegian: "Priser og valuta hentes fra din App Store."
            ))
            if let currency = Storefront.current?.currency?.identifier {
                Text(ATHLTHLocalization.choose(
                    english: "App Store currency: \(currency)",
                    norwegian: "App Store-valuta: \(currency)"
                ))
            }
        }
        .font(.caption2)
        .foregroundStyle(OnboardingTheme.mutedText)
        .multilineTextAlignment(.center)
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
                    purchaseFeedback = ATHLTHLocalization.choose(
                        english: "Sign in to ATHLTH before subscribing.",
                        norwegian: "Logg inn i ATHLTH før du kjøper abonnement."
                    )
                    return
                }
                purchaseFeedback = nil

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
                    Text(ATHLTHLocalization.choose(
                        english: "Subscribe · \(product.displayPrice)",
                        norwegian: "Abonner · \(product.displayPrice)"
                    ))
                        .font(.headline)
                } else {
                    Text(ATHLTHLocalization.choose(
                        english: "Choose a plan",
                        norwegian: "Velg abonnement"
                    ))
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

    private var trialDisclosure: some View {
        VStack(spacing: 5) {
            if session.subscriptionAccess.trialIsActive {
                if let trialEndsAt = session.subscriptionAccess.trialEndsAt {
                    Text(ATHLTHLocalization.format(
                            english: "Your ATHLTH+ trial stays active through %@.",
                            norwegian: "ATHLTH+ prøveperioden din er aktiv til og med %@.",
                            trialEndsAt.formatted(date: .abbreviated, time: .omitted)
                        ))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(OnboardingTheme.mutedText)
                        .multilineTextAlignment(.center)
                }

                Text(ATHLTHLocalization.choose(
                    english: "No subscription starts automatically. If you subscribe now, the App Store subscription starts now and auto-renews until canceled.",
                    norwegian: "Ingen abonnement starter automatisk. Hvis du abonnerer nå, starter betalingen via App Store og fornyes automatisk til du sier opp."
                ))
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
                    Text(ATHLTHLocalization.choose(
                        english: "Restoring…", norwegian: "Gjenoppretter…"
                    ))
                }
            } else {
                Text(ATHLTHLocalization.choose(
                    english: "Restore Purchases",
                    norwegian: "Gjenopprett kjøp"
                ))
            }
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(OnboardingTheme.mutedText)
        .disabled(subscriptionStore.restoreInProgress)
    }

    private var legalLinks: some View {
        HStack(spacing: 16) {
            Button(ATHLTHLocalization.choose(
                english: "Terms of Service",
                norwegian: "Bruksvilkår"
            )) {
                legalDocument = .terms
            }

            Button(ATHLTHLocalization.choose(
                english: "Privacy Policy",
                norwegian: "Personvern"
            )) {
                legalDocument = .privacy
            }
        }
        .font(.caption2)
        .foregroundStyle(OnboardingTheme.faintText)
    }

    private var unavailableState: some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .font(.title2)
                .foregroundStyle(OnboardingTheme.accent)

            Text(ATHLTHLocalization.choose(
                english: "Plans aren't available right now",
                norwegian: "Abonnementene er ikke tilgjengelige nå"
            ))
            .font(.headline)

            Text(ATHLTHLocalization.choose(
                english: "The App Store did not return a monthly or yearly ATHLTH+ subscription. Your existing ATHLTH access is unaffected.",
                norwegian: "App Store returnerte verken måneds- eller årsabonnement for ATHLTH+. Tilgangen du allerede har påvirkes ikke."
            ))
            .font(.caption)
            .foregroundStyle(OnboardingTheme.mutedText)
            .multilineTextAlignment(.center)

            if let error = subscriptionStore.errorMessage {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(OnboardingTheme.mutedText)
                    .multilineTextAlignment(.center)
            }

            Button {
                Task { await reloadPlans() }
            } label: {
                Label(
                    ATHLTHLocalization.choose(
                        english: "Try again", norwegian: "Prøv igjen"
                    ),
                    systemImage: "arrow.clockwise"
                )
                .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(OnboardingPrimaryButtonStyle())
            .disabled(subscriptionStore.isLoading)

            Button {
                showProductDiagnostics.toggle()
            } label: {
                Text(ATHLTHLocalization.choose(
                    english: "Technical details",
                    norwegian: "Tekniske detaljer"
                ))
                .font(.caption)
                .foregroundStyle(OnboardingTheme.mutedText)
            }
            .buttonStyle(.plain)

            if showProductDiagnostics {
                Text(
                    subscriptionStore.missingProductIDs.sorted().joined(
                        separator: "\n"
                    )
                )
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(OnboardingTheme.mutedText)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(
            OnboardingTheme.card,
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
                            .foregroundStyle(OnboardingTheme.primaryText)

                        if yearly, yearlySavingsPercent != nil {
                            Text(ATHLTHLocalization.choose(
                                english: "BEST VALUE",
                                norwegian: "BEST VERDI"
                            ))
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
                        .foregroundStyle(OnboardingTheme.primaryText)

                    if yearly {
                        if let equivalent = yearlyMonthlyEquivalent(for: product) {
                            Text(ATHLTHLocalization.choose(
                                english: "≈ \(equivalent) / month",
                                norwegian: "≈ \(equivalent) per måned"
                            ))
                                .font(.caption)
                                .foregroundStyle(OnboardingTheme.mutedText)
                        }

                        if let saving = yearlySavingsPercent {
                            Text(ATHLTHLocalization.format(
                            english: "Save about %d%% compared with Monthly",
                            norwegian: "Spar omtrent %d %% sammenlignet med månedlig",
                            saving
                        ))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(OnboardingTheme.accent)
                        }
                    } else if product.id == SubscriptionStore.monthlyProductID {
                        Text(ATHLTHLocalization.choose(
                            english: "Flexible monthly billing",
                            norwegian: "Fleksibel månedlig betaling"
                        ))
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
                    : OnboardingTheme.card,
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
                .foregroundStyle(OnboardingTheme.primaryText)

            Spacer(minLength: 0)
        }
    }

    private func yearlyMonthlyEquivalent(for product: Product) -> String? {
        guard product.id == SubscriptionStore.yearlyProductID else {
            return nil
        }

        return (product.price / Decimal(12)).formatted(product.priceFormatStyle)
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
            return ATHLTHLocalization.choose(
                english: "Monthly",
                norwegian: "Månedlig"
            )
        case SubscriptionStore.yearlyProductID:
            return ATHLTHLocalization.choose(
                english: "Yearly",
                norwegian: "Årlig"
            )
        default:
            return product.displayName
        }
    }

    private func planSuffix(for product: Product) -> String {
        switch product.id {
        case SubscriptionStore.monthlyProductID:
            return ATHLTHLocalization.choose(
                english: " / month",
                norwegian: " / måned"
            )
        case SubscriptionStore.yearlyProductID:
            return ATHLTHLocalization.choose(
                english: " / year",
                norwegian: " / år"
            )
        default:
            return ""
        }
    }
}
