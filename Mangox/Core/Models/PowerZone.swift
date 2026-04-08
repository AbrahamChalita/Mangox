import SwiftUI

struct PowerZone: Identifiable {
    private static let ftpStorageKey = "user_ftp_watts"
    private static let ftpHasBeenSetKey = "user_ftp_has_been_set"
    private static let ftpLastUpdateKey = "user_ftp_last_update"
    private static let defaultFTP = 265

    let id: Int
    let name: String
    let pctLow: Double
    let pctHigh: Double
    let color: Color
    let bgColor: Color

    var wattRange: ClosedRange<Int> {
        let low = Int((pctLow * Double(PowerZone.ftp)).rounded())
        let high = Int((pctHigh * Double(PowerZone.ftp)).rounded())
        return low...high
    }

    static var ftp: Int {
        let value = UserDefaults.standard.integer(forKey: ftpStorageKey)
        return value > 0 ? value : defaultFTP
    }

    /// Swift 6: use an explicit MainActor method instead of `@MainActor set` on `ftp` (setters cannot carry a global actor).
    @MainActor
    static func setFTP(_ watts: Int) {
        UserDefaults.standard.set(max(100, watts), forKey: ftpStorageKey)
        UserDefaults.standard.set(true, forKey: ftpHasBeenSetKey)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: ftpLastUpdateKey)
        FTPRefreshTrigger.shared.bump()
    }

    static var lastFTPUpdate: Date? {
        let ts = UserDefaults.standard.double(forKey: ftpLastUpdateKey)
        return ts > 0 ? Date(timeIntervalSince1970: ts) : nil
    }

    /// Whether the user has ever explicitly set their FTP.
    /// Used to decide whether to show an FTP setup prompt on first launch.
    static var hasSetFTP: Bool {
        UserDefaults.standard.bool(forKey: ftpHasBeenSetKey)
    }

    static let zones: [PowerZone] = [
        PowerZone(id: 1, name: "Recovery",  pctLow: 0,    pctHigh: 0.55, color: AppColor.blue,   bgColor: AppColor.blue.opacity(0.12)),
        PowerZone(id: 2, name: "Endurance", pctLow: 0.55, pctHigh: 0.75, color: AppColor.success, bgColor: AppColor.success.opacity(0.12)),
        PowerZone(id: 3, name: "Tempo",     pctLow: 0.75, pctHigh: 0.87, color: AppColor.yellow,  bgColor: AppColor.yellow.opacity(0.12)),
        PowerZone(id: 4, name: "Threshold", pctLow: 0.87, pctHigh: 1.05, color: AppColor.orange,  bgColor: AppColor.orange.opacity(0.12)),
        PowerZone(id: 5, name: "VO2 Max",   pctLow: 1.05, pctHigh: 1.50, color: AppColor.red,     bgColor: AppColor.red.opacity(0.12)),
    ]

    static func zone(for watts: Int) -> PowerZone {
        let pct = Double(watts) / Double(max(ftp, 1))
        return zones.first { pct >= $0.pctLow && pct < $0.pctHigh } ?? zones.last!
    }
}
