// Features/Paywall/Presentation/ViewModel/PaywallViewModel.swift
import Foundation

@MainActor
@Observable
final class PaywallViewModel {
    // MARK: - Dependencies
    private let purchasesService: PurchasesServiceProtocol

    // MARK: - View state
    var isPro: Bool { purchasesService.isPro }
    var isLoading: Bool { purchasesService.isLoading }
    var purchaseError: String? {
        get { purchasesService.purchaseError }
        set { purchasesService.purchaseError = newValue }
    }

    var isProDevUnlockOnly: Bool { purchasesService.isProDevUnlockOnly }
    var hasStoreSubscription: Bool { purchasesService.hasStoreSubscription }
    var storeProPlanKind: String? { purchasesService.storeProPlanKind }
    var storeProRenewalDescription: String? { purchasesService.storeProRenewalDescription }
    var subscriptionManagementURL: URL? { purchasesService.subscriptionManagementURL }

    var availableOptions: [PaywallOption] { purchasesService.availablePaywallOptions }

    var selectedOptionID: String?
    var isPurchasing = false

    var selectedOption: PaywallOption? {
        guard let id = selectedOptionID else { return nil }
        return availableOptions.first(where: { $0.id == id })
    }

    init(purchasesService: PurchasesServiceProtocol) {
        self.purchasesService = purchasesService
    }

    // MARK: - Lifecycle

    func onAppear() async {
        guard !purchasesService.isPro else { return }
        await purchasesService.sync()
        await purchasesService.loadOfferings()
        if selectedOptionID == nil {
            let yearly = availableOptions.first(where: { $0.isYearly })
            selectedOptionID = yearly?.id ?? availableOptions.first?.id
        }
    }

    // MARK: - Actions

    func selectOption(_ option: PaywallOption) {
        selectedOptionID = option.id
    }

    func purchaseSelected() async -> Bool {
        guard let id = selectedOptionID else { return false }
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            return try await purchasesService.purchase(optionWithID: id)
        } catch {
            purchasesService.purchaseError = error.localizedDescription
            return false
        }
    }

    func restorePurchases() async {
        await purchasesService.restorePurchases()
    }
}
