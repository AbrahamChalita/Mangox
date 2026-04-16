import SwiftUI

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var viewModel: PaywallViewModel

    private let mango = AppColor.mango
    private let success = AppColor.success
    private let bg = AppColor.bg

    init(viewModel: PaywallViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                bg.ignoresSafeArea()

                if viewModel.isLoading {
                    ProgressView()
                        .tint(mango)
                } else {
                    ScrollView {
                        VStack(spacing: 24) {
                            if viewModel.isPro {
                                subscriberHeroSection
                                if viewModel.hasStoreSubscription, let url = viewModel.subscriptionManagementURL {
                                    manageSubscriptionButton(url: url)
                                }
                                if viewModel.isProDevUnlockOnly {
                                    devUnlockNotice
                                }
                            } else {
                                heroSection
                                featuresSection
                                packageSelector
                                purchaseButton
                                restoreButton
                                footerText
                            }
                            legalDocumentLinks
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
            await viewModel.onAppear()
        }
    }

    // MARK: - Subscriber hero

    private var subscriberHeroSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 48))
                .foregroundStyle(success)

            Text("You're on Mangox Pro")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white)

            Text(subscriberHeroSubtitle)
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
        }
    }

    private var subscriberHeroSubtitle: String {
        if viewModel.isProDevUnlockOnly {
            return "Pro is enabled on this development build."
        }
        if let plan = viewModel.storeProPlanKind, let renewal = viewModel.storeProRenewalDescription {
            return "\(plan) · \(renewal)"
        }
        if let renewal = viewModel.storeProRenewalDescription {
            return renewal
        }
        if let plan = viewModel.storeProPlanKind {
            return "\(plan) plan"
        }
        return "Thanks for subscribing — every feature is unlocked."
    }

    private func manageSubscriptionButton(url: URL) -> some View {
        Button {
            openURL(url)
        } label: {
            Text("Manage Subscription")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(mango)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(MangoxPressStyle())
    }

    private var devUnlockNotice: some View {
        Text("Billing and renewals are managed separately for App Store subscribers. This unlock applies only to debug builds.")
            .font(.system(size: 11))
            .foregroundStyle(.white.opacity(0.35))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 8)
    }

    // MARK: - Upgrade hero

    private var heroSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "bolt.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(mango)

            Text("Upgrade to Mangox Pro")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white)

            Text(
                "Structured training, on-device fitness charts (PMC), and an AI coach to discuss rides and build custom plans."
            )
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
        }
    }

    private var featuresSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            featureRowMango(title: "Structured Training", subtitle: "Follow built-in and AI plans with clear weeks, key workouts, and event prep")
            featureRow(
                icon: "sparkles",
                title: "AI Coaching",
                subtitle:
                    "Coach replies in chat using your recent rides and plan as context—alongside AI plan generation in the same thread"
            )
            featureRow(
                icon: "calendar.badge.plus",
                title: "AI plan building",
                subtitle: "Multi-week plans tailored to your event and fitness level, guided by chat"
            )
            featureRow(
                icon: "chart.line.uptrend.xyaxis",
                title: "Training load & PMC",
                subtitle: "CTL, ATL, and TSB from your ride history—computed on your device, not by a model"
            )
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

    // MARK: - Package selector (protocol-backed)

    private var packageSelector: some View {
        VStack(spacing: 12) {
            Text("Choose your plan")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))

            HStack(spacing: 12) {
                ForEach(viewModel.availableOptions) { option in
                    optionCard(option)
                }
            }
        }
    }

    private func optionCard(_ option: PaywallOption) -> some View {
        let isSelected = viewModel.selectedOptionID == option.id

        return Button {
            viewModel.selectOption(option)
        } label: {
            VStack(spacing: 8) {
                if option.isYearly {
                    Text("BEST VALUE")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(mango)
                        .clipShape(Capsule())
                }

                Text(option.title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)

                Text(option.localizedPrice)
                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                    .foregroundStyle(mango)

                if option.isYearly {
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

    // MARK: - Purchase button

    private var purchaseButton: some View {
        Button {
            Task {
                let didSucceed = await viewModel.purchaseSelected()
                if didSucceed { dismiss() }
            }
        } label: {
            HStack(spacing: 8) {
                if viewModel.isPurchasing {
                    ProgressView()
                        .tint(.black)
                } else {
                    Image(systemName: "lock.fill")
                }
                Text(viewModel.selectedOption?.localizedPrice ?? "Select a plan")
            }
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(mango)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(MangoxPressStyle())
        .disabled(viewModel.isPurchasing || viewModel.selectedOption == nil || viewModel.isLoading)
    }

    private var restoreButton: some View {
        Button {
            Task { await viewModel.restorePurchases() }
        } label: {
            Text("Restore Purchases")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.4))
        }
    }

    private var footerText: some View {
        Text("Subscriptions auto-renew. Manage in Settings > Apple ID. AI plan generation limited to 8 per month for Pro subscribers.")
            .font(.system(size: 10))
            .foregroundStyle(.white.opacity(0.25))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 12)
    }

    /// App Store Guideline 3.1.2: functional Privacy Policy and Terms of Use (URLs from `Info.plist`).
    @ViewBuilder
    private var legalDocumentLinks: some View {
        let privacy = MangoxLegalURLs.privacyPolicy
        let terms = MangoxLegalURLs.termsOfUse
        if privacy != nil || terms != nil {
            VStack(spacing: 10) {
                HStack(spacing: 20) {
                    if let privacy {
                        Button("Privacy Policy") { openURL(privacy) }
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(mango.opacity(0.95))
                    }
                    if let terms {
                        Button("Terms of Use") { openURL(terms) }
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(mango.opacity(0.95))
                    }
                }
                Text("Subscriptions are billed through your Apple ID. Tap above for our policies.")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.28))
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 4)
        }
    }
}
