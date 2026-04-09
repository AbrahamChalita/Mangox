import Foundation

/// Lazy singleton that holds the built-in training plan struct.
/// Avoids calling `WeddingWeightLossPlan.create()` in computed properties
/// (which rebuilds the full 8-week plan struct on every SwiftUI body evaluation).
/// Access via `CachedPlan.shared` instead.
enum CachedPlan {
    static let shared: TrainingPlan = WeddingWeightLossPlan.create()
}
