import StoreKit
import SwiftUI

struct SubscriptionOfferView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var subscriptionStore: SubscriptionStore
    @EnvironmentObject private var accountService: SupabaseAccountService

    let onPurchaseCompleted: () -> Void

    @State private var selectedProductID: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(OnboardingTheme.green.opacity(0.12))
                                .frame(width: 82, height: 82)

                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            OnboardingTheme.deepGreen,
                                            OnboardingTheme.green
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 62, height: 62)

                            Image(systemName: "sparkles")
                                .font(.system(size: 27, weight: .semibold))
                                .foregroundStyle(.white)
                        }

                        Text("Choose ATHLTH+")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .multilineTextAlignment(.center)

                        Text("Choose the plan that fits you. The App Store shows the final price and billing details before you confirm.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 12)

                    OnboardingCard {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Text("Included with ATHLTH+")
                                    .font(.headline)

                                Spacer()

                                Text("PREMIUM")
                                    .font(.caption2.weight(.black))
                                    .tracking(0.6)
                                    .foregroundStyle(OnboardingTheme.deepGreen)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        OnboardingTheme.green.opacity(0.10),
                                        in: Capsule()
                                    )
                            }

                            benefit("Automatic Health background sync", icon: "arrow.triangle.2.circlepath")
                            benefit("Sleep and recovery insights", icon: "moon.stars.fill")
                            benefit("Advanced training plans and progression", icon: "calendar.badge.clock")
                            benefit("Route challenges and premium recovery features", icon: "figure.run.circle.fill")
                        }
                    }

                    if subscriptionStore.isLoading {
                        ProgressView("Loading plans…")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 28)
                    } else if subscriptionStore.products.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "creditcard")
                                .font(.title2)
                                .foregroundStyle(.secondary)

                            Text("Plans aren’t available yet")
                                .font(.headline)

                            Text("Monthly and Yearly App Store products will appear here when they are configured.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(20)
                        .frame(maxWidth: .infinity)
                        .onboardingSurface(cornerRadius: 18)
                    } else {
                        HStack(alignment: .top, spacing: 12) {
                            ForEach(subscriptionStore.products, id: \.id) { product in
                                planCard(product)
                                    .frame(maxWidth: .infinity)
                            }
                        }

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
                                } else {
                                    Text("Continue with this plan")
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

                    if let errorMessage = subscriptionStore.errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }

                    Text("You can close this window without purchasing and choose ATHLTH+ later in Settings.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 2)
                }
                .padding(24)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
            .background(OnboardingBackground().ignoresSafeArea())
            .navigationTitle("ATHLTH+ Plans")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") {
                        dismiss()
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

    @ViewBuilder
    private func planCard(_ product: Product) -> some View {
        let selected = selectedProductID == product.id

        Button {
            selectedProductID = product.id
        } label: {
            HStack(spacing: 14) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(
                        selected
                            ? OnboardingTheme.green
                            : Color.secondary
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(LocalizedStringKey(planTitle(for: product)))
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text(product.displayPrice + planSuffix(for: product))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if product.id == SubscriptionStore.yearlyProductID {
                    Text("YEARLY")
                        .font(.caption2.weight(.black))
                        .tracking(0.5)
                        .foregroundStyle(OnboardingTheme.deepGreen)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(
                            OnboardingTheme.green.opacity(0.10),
                            in: Capsule()
                        )
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(
                selected ? OnboardingTheme.green.opacity(0.08) : Color.white.opacity(0.90),
                in: RoundedRectangle(cornerRadius: 18)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .stroke(
                        selected ? OnboardingTheme.green.opacity(0.48) : OnboardingTheme.border,
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func benefit(_ title: String, icon: String) -> some View {
        Label {
            Text(LocalizedStringKey(title))
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(OnboardingTheme.green)
        }
        .font(.subheadline)
        .foregroundStyle(.primary)
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
