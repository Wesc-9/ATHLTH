import SwiftUI

struct ATHLTHPlusFeatureGate<Content: View>: View {
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var subscriptionStore: SubscriptionStore

    let feature: ATHLTHFeature
    let title: String
    let message: String
    private let content: () -> Content

    @State private var showingSubscriptionOffer = false

    init(
        feature: ATHLTHFeature,
        title: String,
        message: String,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.feature = feature
        self.title = title
        self.message = message
        self.content = content
    }

    var body: some View {
        Group {
            if session.canAccess(feature) {
                content()
            } else {
                lockedCard
            }
        }
        .sheet(isPresented: $showingSubscriptionOffer) {
            SubscriptionOfferView {
                session.applyStoreKitEntitlement(
                    subscriptionStore.activeEntitlement
                )
                showingSubscriptionOffer = false
            }
            .environmentObject(subscriptionStore)
        }
    }

    private var lockedCard: some View {
        ATHLTHCard {
            VStack(spacing: 14) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(ATHLTHTheme.accent)

                Text(title)
                    .font(.title3.weight(.bold))
                    .multilineTextAlignment(.center)

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button("View ATHLTH+") {
                    showingSubscriptionOffer = true
                }
                .buttonStyle(.borderedProminent)
                .tint(ATHLTHTheme.accent)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }
}
