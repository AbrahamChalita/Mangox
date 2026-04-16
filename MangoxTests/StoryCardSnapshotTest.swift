// MangoxTests/StoryCardSnapshotTest.swift
// TEMPORARY — delete after visual QA.
import XCTest
import UIKit
@testable import Mangox

final class StoryCardSnapshotTest: XCTestCase {

    @MainActor
    func testRenderStoryCardSnapshot() throws {
        let workout = makeMockWorkout()
        let zone = PowerZone.zone(for: Int(workout.avgPower.rounded()))
        let image = InstagramStoryCardRenderer.render(
            workout: workout,
            dominantZone: zone,
            routeName: "Col du Galibier",
            totalElevationGain: 824,
            personalRecordNames: [],
            options: .default,
            sessionKind: .outdoor,
            whoopStrain: 12.4,
            whoopRecovery: 68,
            aiTitle: "Climb Day"
        )

        let data = try XCTUnwrap(image.pngData())
        XCTAssertGreaterThan(data.count, 1000)

        let url = URL(fileURLWithPath: "/Users/abrahamch/Desktop/Projects/Mangox/story_card_debug.png")
        try data.write(to: url)
        print("✅ Wrote snapshot to \(url.path)")
    }

    private func makeMockWorkout() -> Workout {
        let workout = Workout(startDate: Date())
        workout.duration = 7868
        workout.distance = 62_400
        workout.avgPower = 238
        workout.maxPower = 412
        workout.avgCadence = 89
        workout.avgSpeed = 28.6
        workout.avgHR = 154
        workout.maxHR = 178
        workout.normalizedPower = 251
        workout.tss = 92
        workout.intensityFactor = 0.84
        workout.elevationGain = 824
        workout.statusRaw = "completed"

        var samples: [WorkoutSample] = []
        let zoneWeights: [(range: ClosedRange<Int>, weight: Int)] = [
            (100...145, 8),
            (146...199, 22),
            (199...230, 31),
            (231...278, 26),
            (279...380, 13),
        ]
        var elapsed = 0
        for zw in zoneWeights {
            let count = zw.weight * 79
            for _ in 0..<count {
                let power = Int.random(in: zw.range)
                let hr = min(190, 120 + power / 4 + Int.random(in: -5...5))
                samples.append(WorkoutSample(
                    timestamp: workout.startDate.addingTimeInterval(TimeInterval(elapsed)),
                    elapsedSeconds: elapsed,
                    power: power,
                    cadence: Double(Int.random(in: 75...95)),
                    speed: Double.random(in: 18...38),
                    heartRate: hr
                ))
                elapsed += 1
            }
        }
        workout.samples = samples
        workout.sampleCount = samples.count
        return workout
    }
}
