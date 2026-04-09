// Features/Profile/Presentation/ViewModel/ProfileViewModel.swift
import Foundation

@MainActor
@Observable
final class ProfileViewModel {
    // MARK: - Dependencies
    private let whoopService: WhoopServiceProtocol
    private let purchasesService: PurchasesServiceProtocol

    // MARK: - View state
    var whoopConnected: Bool { whoopService.isConnected }
    var whoopDisplayName: String? { whoopService.memberDisplayName }
    var recoveryScore: Double? { whoopService.latestRecoveryScore }
    var recoveryHRV: Int? { whoopService.latestRecoveryHRV }
    var isBusy: Bool { whoopService.isBusy }
    var lastError: String? { whoopService.lastError }
    var readinessHint: String { whoopService.readinessTrainingHint }

    var isPro: Bool { purchasesService.isPro }

    init(whoopService: WhoopServiceProtocol, purchasesService: PurchasesServiceProtocol) {
        self.whoopService = whoopService
        self.purchasesService = purchasesService
    }

    func connectWhoop() async {
        try? await whoopService.connect()
    }

    func disconnectWhoop() async {
        await whoopService.disconnect()
    }

    func refreshWhoop() async {
        try? await whoopService.refreshLinkedData()
    }
}
