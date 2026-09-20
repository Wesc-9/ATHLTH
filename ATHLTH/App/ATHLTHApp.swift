import StoreKit
import SwiftUI

@main
struct ATHLTHApp: App {
    @StateObject private var health = HealthKitManager()
    @StateObject private var trainingPlan = TrainingPlanStore()
    @StateObject private var membership = ATHLTHPlusStore()

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environmentObject(health)
                .environmentObject(trainingPlan)
                .environmentObject(membership)
        }
    }
}

struct AppRootView: View {
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var membership: ATHLTHPlusStore

    @AppStorage("athlth.onboarding.complete") private var onboardingComplete = false
    @State private var route: LaunchRoute = .ready
    @State private var showingPlans = false
    @State private var showingPurchaseSuccess = false

    var body: some View {
        Group {
            if !health.hasRequestedAuthorization {
                HealthAccessView()
            } else if !onboardingComplete {
                switch route {
                case .ready:
                    ATHLTHReadyView {
                        if membership.hasATHLTHPlus {
                            completeOnboarding()
                        } else {
                            showingPlans = true
                        }
                    }
                case .home:
                    RootTabView()
                }
            } else {
                RootTabView()
            }
        }
        .sheet(isPresented: $showingPlans) {
            ATHLTHPlusPlansView(
                onClose: {
                    showingPlans = false
                    completeOnboarding()
                },
                onPurchased: {
                    showingPlans = false
                    showingPurchaseSuccess = true
                }
            )
            .environmentObject(membership)
        }
        .fullScreenCover(isPresented: $showingPurchaseSuccess) {
            ATHLTHPlusActivatedView {
                showingPurchaseSuccess = false
                completeOnboarding()
            }
            .environmentObject(membership)
        }
        .task {
            await membership.refreshEntitlements()
            guard health.hasRequestedAuthorization else { return }
            await health.refreshAll()
        }
    }

    private func completeOnboarding() {
        onboardingComplete = true
        route = .home
    }

    private enum LaunchRoute {
        case ready
        case home
    }
}

@MainActor
final class ATHLTHPlusStore: ObservableObject {
    static let monthlyProductID = "com.wesc9.athlth.plus.monthly"
    static let yearlyProductID = "com.wesc9.athlth.plus.yearly"

    @Published private(set) var hasATHLTHPlus = false
    @Published private(set) var products: [Product] = []
    @Published private(set) var paidAccessUntil: Date?
    @Published var purchaseError: String?
    @Published private(set) var isLoading = false

    var monthly: Product? { products.first { $0.id == Self.monthlyProductID } }
    var yearly: Product? { products.first { $0.id == Self.yearlyProductID } }

    func loadProducts() async {
        guard products.isEmpty else { return }
        do {
            products = try await Product.products(for: [Self.monthlyProductID, Self.yearlyProductID])
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    func refreshEntitlements() async {
        var active = false
        var latestExpiration: Date?

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            guard [Self.monthlyProductID, Self.yearlyProductID].contains(transaction.productID) else { continue }
            if transaction.revocationDate == nil {
                active = true
                if let expiration = transaction.expirationDate,
                   latestExpiration == nil || expiration > latestExpiration! {
                    latestExpiration = expiration
                }
            }
        }

        hasATHLTHPlus = active
        paidAccessUntil = latestExpiration
    }

    func purchase(_ product: Product) async -> Bool {
        isLoading = true
        purchaseError = nil
        defer { isLoading = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    purchaseError = "The App Store purchase could not be verified."
                    return false
                }
                await transaction.finish()
                await refreshEntitlements()
                return hasATHLTHPlus
            case .pending:
                purchaseError = "Your purchase is pending approval."
                return false
            case .userCancelled:
                return false
            @unknown default:
                return false
            }
        } catch {
            purchaseError = error.localizedDescription
            return false
        }
    }
}

private struct ATHLTHBrandHeader: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("A T H L T H")
                .font(.system(size: 23, weight: .semibold, design: .rounded))
            Text("MOVE  BETTER  LIVE  LONGER")
                .font(.system(size: 8, weight: .medium))
                .tracking(2.4)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ATHLTHReadyView: View {
    let onStart: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                ATHLTHBrandHeader()

                HStack(spacing: 8) {
                    ForEach(0..<5, id: \.self) { _ in
                        Capsule().fill(.green).frame(height: 5)
                    }
                    Text("5 of 5")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 8)
                }

                Image(systemName: "checkmark")
                    .font(.system(size: 42, weight: .bold))
                    .foregroundStyle(.green)
                    .frame(width: 92, height: 92)
                    .background(.green.opacity(0.11), in: Circle())
                    .padding(.top, 8)

                VStack(spacing: 7) {
                    Text("You’re ready")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                    Text("Your setup is complete. Let’s get started on a stronger, healthier you.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 0) {
                    HStack(spacing: 13) {
                        Image(systemName: "dumbbell.fill")
                            .foregroundStyle(.green)
                            .frame(width: 44, height: 44)
                            .background(.green.opacity(0.1), in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text("YOUR GOAL")
                                .font(.caption2.weight(.semibold))
                                .tracking(1.5)
                                .foregroundStyle(.secondary)
                            Text("Build muscle")
                                .font(.headline)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.secondary)
                    }
                    .padding(18)

                    LinearGradient(
                        colors: [.green.opacity(0.08), .mint.opacity(0.18), .clear],
                        startPoint: .bottomLeading,
                        endPoint: .topTrailing
                    )
                    .frame(height: 170)
                    .overlay {
                        VStack(spacing: 10) {
                            Image(systemName: "mountain.2.fill")
                                .font(.system(size: 55))
                                .foregroundStyle(.secondary.opacity(0.45))
                            Text("SMALL STEPS  •  BIG CHANGES")
                                .font(.caption2.weight(.semibold))
                                .tracking(2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28))
                .overlay(RoundedRectangle(cornerRadius: 28).stroke(.white.opacity(0.45)))

                Button(action: onStart) {
                    HStack {
                        Spacer()
                        Text("Start ATHLTH").fontWeight(.semibold)
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .padding(.horizontal, 18)
                    .frame(height: 56)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .clipShape(Capsule())

                Label("ATHLTH+ plans are optional and can be reviewed before entering ATHLTH.", systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
        }
        .background(
            LinearGradient(colors: [.white, .green.opacity(0.035)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        )
    }
}

struct ATHLTHPlusPlansView: View {
    @EnvironmentObject private var membership: ATHLTHPlusStore
    @Environment(\.dismiss) private var dismiss

    let onClose: () -> Void
    let onPurchased: () -> Void

    @State private var selected: Plan = .yearly

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    ATHLTHBrandHeader()

                    VStack(spacing: 7) {
                        Text("ATHLTH+")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                        Text("Get the most out of your health journey with premium features.")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                    }

                    VStack(spacing: 16) {
                        feature("icloud.and.arrow.down", "Automatic Health background sync", "Your data, always up to date")
                        feature("chart.bar.fill", "Advanced training plans", "Personalized and adaptive")
                        feature("applewatch", "Full Apple Watch integration", "Seamless and real-time")
                        feature("star.fill", "Premium insights", "Deeper data. Better progress.")
                    }
                    .padding(18)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))

                    HStack(spacing: 12) {
                        planCard(.monthly, title: "Monthly", fallbackPrice: "89,00 kr", detail: "per month")
                        planCard(.yearly, title: "Yearly", fallbackPrice: "699,00 kr", detail: "per year", badge: "Best value")
                    }

                    Button {
                        Task {
                            await membership.loadProducts()
                            guard let product = selected == .yearly ? membership.yearly : membership.monthly else {
                                membership.purchaseError = "ATHLTH+ is not available from the App Store yet."
                                return
                            }
                            if await membership.purchase(product) {
                                onPurchased()
                            }
                        }
                    } label: {
                        HStack {
                            Spacer()
                            if membership.isLoading {
                                ProgressView().tint(.white)
                            } else {
                                Text("Continue with \(selected == .yearly ? "Yearly" : "Monthly")")
                                    .fontWeight(.semibold)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                        .frame(height: 54)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .clipShape(Capsule())
                    .disabled(membership.isLoading)

                    if let error = membership.purchaseError {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }

                    Label("You can close this window and continue without ATHLTH+.", systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(24)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
            .background(
                LinearGradient(colors: [.white, .green.opacity(0.035)], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
            )
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                        onClose()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.headline)
                            .frame(width: 34, height: 34)
                            .background(.thinMaterial, in: Circle())
                    }
                    .accessibilityLabel("Close ATHLTH+ plans")
                }
            }
            .task { await membership.loadProducts() }
        }
    }

    @ViewBuilder
    private func feature(_ icon: String, _ title: String, _ subtitle: String) -> some View {
        HStack(spacing: 13) {
            Image(systemName: icon)
                .foregroundStyle(.green)
                .frame(width: 42, height: 42)
                .background(.green.opacity(0.1), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func planCard(_ plan: Plan, title: String, fallbackPrice: String, detail: String, badge: String? = nil) -> some View {
        let product = plan == .yearly ? membership.yearly : membership.monthly
        Button {
            selected = plan
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Image(systemName: selected == plan ? "largecircle.fill.circle" : "circle")
                        .foregroundStyle(selected == plan ? .green : .secondary)
                    Spacer()
                    if let badge {
                        Text(badge)
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .foregroundStyle(.white)
                            .background(.green, in: Capsule())
                    }
                }
                Text(title).font(.headline)
                Text(product?.displayPrice ?? fallbackPrice)
                    .font(.title2.bold())
                Text(detail).font(.caption).foregroundStyle(.secondary)
                if plan == .yearly {
                    Text("Save 34%").font(.caption.weight(.semibold)).foregroundStyle(.green)
                } else {
                    Text("Cancel anytime").font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 145, alignment: .leading)
            .padding(16)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(selected == plan ? .green : .secondary.opacity(0.18), lineWidth: selected == plan ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    private enum Plan {
        case monthly
        case yearly
    }
}

struct ATHLTHPlusActivatedView: View {
    @EnvironmentObject private var membership: ATHLTHPlusStore
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 26) {
            ATHLTHBrandHeader()

            Spacer()

            Image(systemName: "checkmark")
                .font(.system(size: 44, weight: .bold))
                .foregroundStyle(.green)
                .frame(width: 96, height: 96)
                .background(.green.opacity(0.11), in: Circle())

            VStack(spacing: 7) {
                Text("All set!")
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                Text("You’re in. Let’s build a healthier, stronger you together.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 14) {
                Label("ATHLTH+ activated", systemImage: "crown.fill")
                    .font(.title3.bold())
                    .foregroundStyle(.green)
                Text("You now have full access to ATHLTH+.")
                    .foregroundStyle(.secondary)
                if let date = membership.paidAccessUntil {
                    Label("Paid access until \(date.formatted(date: .abbreviated, time: .omitted))", systemImage: "checkmark.circle.fill")
                }
                Label("All ATHLTH+ features unlocked", systemImage: "checkmark.circle.fill")
                Label("Manage your subscription in your Apple ID settings", systemImage: "checkmark.circle.fill")
            }
            .padding(20)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))

            Button(action: onContinue) {
                HStack {
                    Spacer()
                    Text("Continue to ATHLTH").fontWeight(.semibold)
                    Spacer()
                    Image(systemName: "chevron.right")
                }
                .frame(height: 54)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .clipShape(Capsule())

            Spacer()

            Text("SMALL STEPS\nCREATE BIG CHANGES")
                .font(.caption.weight(.semibold))
                .tracking(3)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(maxWidth: 620)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(colors: [.white, .green.opacity(0.06)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        )
    }
}
