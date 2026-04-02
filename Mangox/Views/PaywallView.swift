import SwiftUI
import RevenueCat

struct PaywallView: View {
    @Environment(PurchasesManager.self) private var purchases
    @Environment(\.dismiss) private var dismiss

    @State private var selectedPackage: Package?
    @State private var isPurchasing = false

    private let mango = AppColor.mango
    private let success = AppColor.success
    private let bg = AppColor.bg

    var body: some View {
        NavigationStack {
            ZStack {
                bg.ignoresSafeArea()

                if purchases.isLoading {
                    ProgressView()
                        .tint(mango)
                } else {
                    ScrollView {
                        VStack(spacing: 24) {
                            heroSection
                            featuresSection
                            packageSelector
                            purchaseButton
                            restoreButton
                            footerText
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                        .padding(.bottom, 40)
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .task {
            // Check if Purchases has been configured before attempting to load offerings
            guard Purchases.isConfigured else {
                return
            }
            await purchases.loadOfferings()
            if let currentOffering = purchases.offerings?.current {
                if selectedPackage == nil {
                    selectedPackage = currentOffering.availablePackages.first(where: { $0.storeProduct.productIdentifier.contains("yearly") })
                        ?? currentOffering.availablePackages.first
                }
            }
        }
    }

    private var heroSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "bolt.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(mango)

            Text("Upgrade to Mangox Pro")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white)

            Text("Advanced analytics, structured training tools, and everything you need to hit your goals.")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
        }
    }

    private var featuresSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            featureRowMango(title: "Structured Training", subtitle: "Follow the Classicissima plan with clear weeks, key workouts, and event prep")
            featureRow(icon: "sparkles", title: "AI Coaching", subtitle: "Chat with your coach, analyze rides, and get personalized training advice")
            featureRow(icon: "calendar.badge.plus", title: "AI Plan Generation", subtitle: "Generate multi-week training plans tailored to your event and fitness level")
            featureRow(icon: "chart.line.uptrend.xyaxis", title: "Advanced Analytics", subtitle: "Deep dive into your training data with PMC charts and trends")
            featureRow(icon: "bolt.heart", title: "Priority Features", subtitle: "Early access to new features and improvements")
        }
        .padding(16)
        .background(Color.white.opacity(AppOpacity.cardBg))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.white.opacity(AppOpacity.cardBorder), lineWidth: 1)
        )
    }

    private func featureRowMango(title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            MangoxMark(size: 22)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.4))
            }

            Spacer()
        }
    }

    private func featureRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(success)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.4))
            }

            Spacer()
        }
    }

    private var packageSelector: some View {
        VStack(spacing: 12) {
            Text("Choose your plan")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))

            if let packages = purchases.offerings?.current?.availablePackages {
                HStack(spacing: 12) {
                    ForEach(packages, id: \.identifier) { pkg in
                        packageCard(pkg)
                    }
                }
            }
        }
    }

    private func packageCard(_ pkg: Package) -> some View {
        let isSelected = selectedPackage?.identifier == pkg.identifier
        let isYearly = pkg.storeProduct.productIdentifier.contains("yearly")

        return Button {
            selectedPackage = pkg
        } label: {
            VStack(spacing: 8) {
                if isYearly {
                    Text("BEST VALUE")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(mango)
                        .clipShape(Capsule())
                }

                Text(pkg.packageTitle)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)

                Text(pkg.localizedPriceString)
                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                    .foregroundStyle(mango)

                if isYearly {
                    Text("Save 50%")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(success)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(isSelected ? mango.opacity(0.12) : Color.white.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(isSelected ? mango.opacity(0.5) : Color.white.opacity(0.08), lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(MangoxPressStyle())
    }

    private var purchaseButton: some View {
        Button {
            Task { await purchaseSelectedPackage() }
        } label: {
            HStack(spacing: 8) {
                if isPurchasing {
                    ProgressView()
                        .tint(.black)
                } else {
                    Image(systemName: "lock.fill")
                }
                Text(selectedPackage?.localizedPriceString ?? "Select a plan")
            }
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(mango)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(MangoxPressStyle())
        .disabled(isPurchasing || selectedPackage == nil || purchases.isLoading)
    }

    private var restoreButton: some View {
        Button {
            Task { await purchases.restorePurchases() }
        } label: {
            Text("Restore Purchases")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.4))
        }
    }

    private var footerText: some View {
        Text("Subscriptions auto-renew. Manage in Settings › Apple ID. AI plan generation limited to 8 per month for Pro subscribers.")
            .font(.system(size: 10))
            .foregroundStyle(.white.opacity(0.25))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 12)
    }

    private func purchaseSelectedPackage() async {
        guard let pkg = selectedPackage else { return }
        isPurchasing = true
        defer { isPurchasing = false }

        do {
            try await purchases.purchase(pkg)
            if purchases.isPro {
                dismiss()
            }
        } catch {
            purchases.purchaseError = error.localizedDescription
        }
    }
}

extension Package {
    var packageTitle: String {
        switch packageType {
        case .monthly: return "Monthly"
        case .annual: return "Yearly"
        default: return storeProduct.localizedTitle
        }
    }
}
