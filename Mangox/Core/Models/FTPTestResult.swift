import Foundation

struct FTPTestResult: Codable, Identifiable {
    let id: UUID
    let date: Date
    let twentyMinuteAvgPower: Double
    let estimatedFTP: Int
    let maxPower: Int
    /// Per-phase average power keyed by phase ID.
    let phaseAverages: [Int: Double]
    /// Whether the user applied this result as their active FTP.
    var applied: Bool

    init(
        date: Date = .now,
        twentyMinuteAvgPower: Double,
        estimatedFTP: Int,
        maxPower: Int,
        phaseAverages: [Int: Double],
        applied: Bool = false
    ) {
        self.id = UUID()
        self.date = date
        self.twentyMinuteAvgPower = twentyMinuteAvgPower
        self.estimatedFTP = estimatedFTP
        self.maxPower = maxPower
        self.phaseAverages = phaseAverages
        self.applied = applied
    }
}

// MARK: - Persistence

enum FTPTestHistory {
    private static let storageKey = "ftp_test_history"

    static func load() -> [FTPTestResult] {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return [] }
        return (try? JSONDecoder().decode([FTPTestResult].self, from: data)) ?? []
    }

    static func save(_ results: [FTPTestResult]) {
        if let data = try? JSONEncoder().encode(results) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    static func append(_ result: FTPTestResult) {
        var history = load()
        history.append(result)
        save(history)
    }

    static func markApplied(id: UUID) {
        var history = load()
        if let idx = history.firstIndex(where: { $0.id == id }) {
            history[idx].applied = true
            save(history)
        }
    }
}
