import Foundation

#if canImport(os) && DEBUG
    import os

    /// Points of interest for Instruments (SwiftUI / Time Profiler). Subsystem: Mangox — Performance.
    enum MangoxDebugPerformance {
        private static let signposter = OSSignposter(
            subsystem: "com.abchalita.Mangox", category: "Performance")

        static func runInterval(_ name: StaticString, _ work: () -> Void) {
            let id = signposter.makeSignpostID()
            let state = signposter.beginInterval(name, id: id)
            defer { signposter.endInterval(name, state) }
            work()
        }

        static func runInterval(_ name: StaticString, _ work: () async -> Void) async {
            let id = signposter.makeSignpostID()
            let state = signposter.beginInterval(name, id: id)
            defer { signposter.endInterval(name, state) }
            await work()
        }
    }
#else
    enum MangoxDebugPerformance {
        static func runInterval(_: StaticString, _ work: () -> Void) { work() }

        static func runInterval(_: StaticString, _ work: () async -> Void) async { await work() }
    }
#endif
