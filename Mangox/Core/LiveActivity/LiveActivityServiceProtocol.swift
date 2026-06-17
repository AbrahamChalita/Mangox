import Foundation

/// Contract for Live Activity synchronization during indoor and outdoor rides.
/// Concrete implementation: `RideLiveActivityManager` in Outdoor/Data/DataSources/RideLiveActivity/.
@MainActor
protocol LiveActivityServiceProtocol: AnyObject {
    func syncOutdoorRecording(snapshot: OutdoorLiveActivitySnapshot) async
    func syncIndoorRecording(snapshot: IndoorLiveActivitySnapshot) async
    func endLiveActivity() async
}
