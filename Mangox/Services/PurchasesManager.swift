import Foundation
import Observation
import RevenueCat
import os.log

private let rcLogger = Logger(subsystem: "com.abchalita.Mangox", category: "PurchasesManager")

enum PurchasesManagerError: Error {
    case notConfigured
}

@MainActor
@Observable
final class PurchasesManager {

    static let shared = PurchasesManager()

    /// RevenueCat entitlement only (no dev override). Use for UI that must show real subscription state.
    private(set) var revenueCatPro: Bool = false

    /// Effective Pro access: store entitlement or DEBUG-only superuser override (`MANGOX_DEV_PRO`, UserDefaults).
    var isPro: Bool { revenueCatPro || Self.isProDevOverride }
    var offerings: Offerings?
    var customerInfo: CustomerInfo?
    var isLoading = false
    var purchaseError: String?

    static let proEntitlementID = "pro"
    static let monthlyProductID = "com.mangox.pro.monthly"
    static let yearlyProductID = "com.mangox.pro.yearly"

    private let revenueCatDelegate = Delegate()

    private init() {
        revenueCatDelegate.owner = self
    }

    func configure(apiKey: String) {
        Purchases.configure(withAPIKey: apiKey)
        Purchases.shared.delegate = revenueCatDelegate
        Task { await sync() }
    }

    func sync() async {
        guard Purchases.isConfigured else { return }
        do {
            let info = try await Purchases.shared.customerInfo()
            updateEntitlements(info)
        } catch {
            rcLogger.error("Sync failed: \(error)")
        }
    }

    func loadOfferings() async {
        guard Purchases.isConfigured else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            offerings = try await Purchases.shared.offerings()
        } catch {
            rcLogger.error("Failed to load offerings: \(error)")
        }
    }

    func purchase(_ package: Package) async throws {
        guard Purchases.isConfigured else {
            throw PurchasesManagerError.notConfigured
        }
        let result = try await Purchases.shared.purchase(package: package)
        updateEntitlements(result.customerInfo)
        if !result.userCancelled {
            _ = try await Purchases.shared.syncPurchases()
        }
    }

    func restorePurchases() async {
        guard Purchases.isConfigured else { return }
        do {
            let info = try await Purchases.shared.restorePurchases()
            updateEntitlements(info)
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    /// Subscription management URL from RevenueCat, with App Store fallback.
    var subscriptionManagementURL: URL? {
        if let url = customerInfo?.managementURL {
            return url
        }
        return URL(string: "https://apps.apple.com/account/subscriptions")
    }

    private func updateEntitlements(_ info: CustomerInfo) {
        customerInfo = info
        revenueCatPro = info.entitlements[Self.proEntitlementID]?.isActive == true
    }

    private var activeProEntitlement: EntitlementInfo? {
        customerInfo?.entitlements[Self.proEntitlementID]
    }

    /// Billing cadence from the active store entitlement (e.g. Monthly / Yearly).
    var storeProPlanKind: String? {
        guard revenueCatPro, let pid = activeProEntitlement?.productIdentifier else { return nil }
        switch pid {
        case Self.monthlyProductID: return "Monthly"
        case Self.yearlyProductID: return "Yearly"
        default:
            return activeProEntitlement?.productIdentifier
        }
    }

    /// Human-readable renewal or end date for the active subscription, when RevenueCat provides one.
    var storeProRenewalDescription: String? {
        guard revenueCatPro, let ent = activeProEntitlement, ent.isActive else { return nil }
        guard let exp = ent.expirationDate else { return nil }
        let df = DateFormatter()
        df.dateStyle = .medium
        if ent.willRenew {
            return "Renews \(df.string(from: exp))"
        }
        return "Active until \(df.string(from: exp))"
    }

    /// True when Pro comes only from the DEBUG override (no App Store entitlement).
    var isProDevUnlockOnly: Bool { isPro && !revenueCatPro }

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

    private final class Delegate: NSObject, PurchasesDelegate {
        weak var owner: PurchasesManager?

        nonisolated func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
            Task { @MainActor in
                owner?.updateEntitlements(customerInfo)
            }
        }
    }
}
