import Foundation

/// Contract for in-app purchase management.
/// Concrete implementation: `PurchasesManager` in Profile/Data/.
@MainActor
protocol PurchasesServiceProtocol: AnyObject {
    var isPro: Bool { get }
    var isLoading: Bool { get }
    var purchaseError: String? { get }

    func configure(apiKey: String)
    func sync() async
    func loadOfferings() async
    func restorePurchases() async

    var subscriptionManagementURL: URL? { get }
    var isProDevUnlockOnly: Bool { get }
}
