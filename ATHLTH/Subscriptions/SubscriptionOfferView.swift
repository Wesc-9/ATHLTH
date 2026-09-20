import StoreKit
import SwiftUI

struct SubscriptionOfferView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var subscriptionStore: SubscriptionStore

    let onPurchaseCompleted: () -> Void

    @State private var selectedProductID: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    VStack(spacing: 10) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 42))
                            .foregroundStyle(OnboardingTheme.green)

                        Text("Keep ATHLTH Paid")
                            .font(.largeTitle.weight(.bold))
                            .multilineTextAlignment(.center)

                        Text("Choose a plan to keep your Paid benefits after the trial.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 12)

                    OnboardingCard {
                        VStack(alignment: .leading, spacing: 14) {
                            benefit("Automatic Health background sync", icon: "heart.fill")
                            benefit("Advanced training and planning tools", icon: "calendar.badge.clock")
                            benefit("Full Apple Watch integration", icon: "applewatch")
                            benefit("Expanded progress and recovery features", icon: "chart.line.uptrend.xyaxis")
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
                                if await subscriptionStore.purchase(product) {
                                    onPurchaseCompleted()
                                }
                            }
                        } label: {
                            HStack {
                                Spacer()
                                if subscriptionStore.purchaseInProgress {
                                    ProgressView()
                                } else {
                                    Text("Continue with selected plan")
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

                    Text("You can close this window and continue using the rest of your free trial.")
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
            .navigationTitle("Paid plans")
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
                    .foregroundStyle(selected ? Color.green : Color.secondary)

                VStack(alignment: .leading, spacing: 4) {
                    Text(planTitle(for: product))
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text(product.displayPrice + planSuffix(for: product))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()
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
        Label(title, systemImage: icon)
            .font(.subheadline)
            .foregroundStyle(.primary)
            .tint(OnboardingTheme.green)
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
