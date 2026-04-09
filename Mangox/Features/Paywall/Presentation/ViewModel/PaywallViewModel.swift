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
    var purchaseError: String? { purchasesService.purchaseError }

    init(purchasesService: PurchasesServiceProtocol) {
        self.purchasesService = purchasesService
    }

    func restorePurchases() async {
        await purchasesService.restorePurchases()
    }

    func syncSubscription() async {
        await purchasesService.sync()
    }
}
