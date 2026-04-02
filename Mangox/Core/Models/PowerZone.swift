import SwiftUI

struct PowerZone: Identifiable {
    private static let ftpStorageKey = "user_ftp_watts"
    private static let ftpHasBeenSetKey = "user_ftp_has_been_set"
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
        get {
            let value = UserDefaults.standard.integer(forKey: ftpStorageKey)
            return value > 0 ? value : defaultFTP
        }
        set {
            UserDefaults.standard.set(max(100, newValue), forKey: ftpStorageKey)
            UserDefaults.standard.set(true, forKey: ftpHasBeenSetKey)
            FTPRefreshTrigger.shared.bump()
        }
    }

    /// Whether the user has ever explicitly set their FTP.
    /// Used to decide whether to show an FTP setup prompt on first launch.
    static var hasSetFTP: Bool {
        UserDefaults.standard.bool(forKey: ftpHasBeenSetKey)
    }

    static let zones: [PowerZone] = [
        PowerZone(id: 1, name: "Recovery",  pctLow: 0,    pctHigh: 0.55,
                  color: Color(red: 107/255, green: 127/255, blue: 212/255),
                  bgColor: Color(red: 107/255, green: 127/255, blue: 212/255).opacity(0.12)),
        PowerZone(id: 2, name: "Endurance", pctLow: 0.55, pctHigh: 0.75,
                  color: Color(red: 79/255, green: 195/255, blue: 161/255),
                  bgColor: Color(red: 79/255, green: 195/255, blue: 161/255).opacity(0.12)),
        PowerZone(id: 3, name: "Tempo",     pctLow: 0.75, pctHigh: 0.87,
                  color: Color(red: 240/255, green: 195/255, blue: 78/255),
                  bgColor: Color(red: 240/255, green: 195/255, blue: 78/255).opacity(0.12)),
        PowerZone(id: 4, name: "Threshold", pctLow: 0.87, pctHigh: 1.05,
                  color: Color(red: 240/255, green: 122/255, blue: 58/255),
                  bgColor: Color(red: 240/255, green: 122/255, blue: 58/255).opacity(0.12)),
        PowerZone(id: 5, name: "VO2 Max",   pctLow: 1.05, pctHigh: 1.50,
                  color: Color(red: 232/255, green: 68/255, blue: 90/255),
                  bgColor: Color(red: 232/255, green: 68/255, blue: 90/255).opacity(0.12)),
    ]

    static func zone(for watts: Int) -> PowerZone {
        let pct = Double(watts) / Double(max(ftp, 1))
        return zones.first { pct >= $0.pctLow && pct < $0.pctHigh } ?? zones.last!
    }
}
