// Features/Profile/Data/DataSources/PurchasesManager.swift
import Foundation
import Observation

enum PurchasesManagerError: Error {
    case notConfigured
}

@MainActor
@Observable
final class PurchasesManager: PurchasesServiceProtocol {

    static let shared = PurchasesManager()

    /// Effective Pro access: DEBUG-only superuser override (`MANGOX_DEV_PRO`, UserDefaults).
    var isPro: Bool { Self.isProDevOverride }
    var isLoading = false
    var purchaseError: String?

    private init() {}

    func sync() async {}

    func loadOfferings() async {}

    func restorePurchases() async {
        purchaseError = "Subscriptions are not available in this build."
    }

    var subscriptionManagementURL: URL? {
        URL(string: "https://apps.apple.com/account/subscriptions")
    }

    var isProDevUnlockOnly: Bool { isPro }

    var hasStoreSubscription: Bool { false }

    var storeProPlanKind: String? { nil }

    var storeProRenewalDescription: String? { nil }

    var availablePaywallOptions: [PaywallOption] { [] }

    func purchase(optionWithID id: String) async throws -> Bool {
        throw PurchasesManagerError.notConfigured
    }

    /// DEBUG-only: grant Pro without a sandbox purchase. Release builds always return `false`.
    ///
    /// Enable any of:
    /// - Xcode Scheme → Run → Arguments → Environment: `MANGOX_DEV_PRO` = `1`
    /// - `defaults write <bundle-id> MangoxDevForcePro -bool true` (DEBUG builds only)
    private static var isProDevOverride: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.environment["MANGOX_DEV_PRO"] == "1" { return true }
        return UserDefaults.standard.bool(forKey: "MangoxDevForcePro")
        #else
        return false
        #endif
    }
}
