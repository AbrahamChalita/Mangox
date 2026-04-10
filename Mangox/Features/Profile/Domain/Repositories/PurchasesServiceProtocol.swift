import Foundation

/// Display-only snapshot of a purchasable plan option, decoupled from RevenueCat `Package`.
struct PaywallOption: Identifiable, Sendable {
    let id: String
    let productIdentifier: String
    let title: String
    let localizedPrice: String
    let isYearly: Bool
}

/// Contract for in-app purchase management.
/// Concrete implementation: `PurchasesManager` in Profile/Data/.
@MainActor
protocol PurchasesServiceProtocol: AnyObject {
    var isPro: Bool { get }
    var isLoading: Bool { get }
    var purchaseError: String? { get set }

    func configure(apiKey: String)
    func sync() async
    func loadOfferings() async
    func restorePurchases() async

    var subscriptionManagementURL: URL? { get }
    var isProDevUnlockOnly: Bool { get }
    var hasStoreSubscription: Bool { get }
    var storeProPlanKind: String? { get }
    var storeProRenewalDescription: String? { get }
    var availablePaywallOptions: [PaywallOption] { get }

    func purchase(optionWithID id: String) async throws -> Bool
}
