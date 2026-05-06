// MangoxTests/StoryCardSnapshotTest.swift
// TEMPORARY — delete after visual QA.
import XCTest
import UIKit
@testable import Mangox

@MainActor
final class StoryCardSnapshotTest: XCTestCase {

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

    func testStoryOptionsDecodeOldPreferencesWithNewDefaults() throws {
        let legacyJSON = """
        {
          "accent": "dominantZone",
          "backgroundSource": "none",
          "selectedPreset": "darkAtmospheric",
          "layeredShare": false,
          "showHeader": true,
          "showHeroTitle": true,
          "showRouteName": true,
          "showTrainingLoad": true,
          "showSummaryCards": true,
          "showBottomStrip": true,
          "showElevation": true,
          "showBrandBadge": true,
          "showQuickStatHeartRate": true,
          "showQuickStatCadence": true,
          "showQuickStatThird": true,
          "showQuickStatSpeed": true,
          "showWhoopReadiness": true
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(InstagramStoryCardOptions.self, from: legacyJSON)

        XCTAssertEqual(decoded.template, .cleanStats)
        XCTAssertEqual(decoded.visualStyle, .mangoEditorial)
        XCTAssertEqual(decoded.quickStatSlots, [.heartRate, .cadence, .elevation, .speed])
        XCTAssertFalse(decoded.carouselExport)
        XCTAssertFalse(decoded.privacyHidePower)
    }

    func testAllStoryTemplatesRenderStorySizedImages() throws {
        let workout = makeMockWorkout()
        let zone = PowerZone.zone(for: Int(workout.avgPower.rounded()))

        for template in InstagramStoryCardOptions.Template.allCases {
            var options = InstagramStoryCardOptions.default
            options.template = template
            options.visualStyle = template == .cleanStats ? .mangoEditorial : .analyst
            options.quickStatSlots = [.distance, .movingTime, .normalizedPower, .tss]

            let image = InstagramStoryCardRenderer.render(
                workout: workout,
                dominantZone: zone,
                routeName: "Col du Galibier",
                totalElevationGain: 824,
                personalRecordNames: ["20 min"],
                options: options,
                sessionKind: .outdoor,
                whoopStrain: 12.4,
                whoopRecovery: 68,
                aiTitle: "Climb Day"
            )

            XCTAssertEqual(image.size, InstagramStoryCardRenderer.cardSize, "Failed template \(template.rawValue)")
            XCTAssertGreaterThan(try XCTUnwrap(image.jpegData(compressionQuality: 0.7)).count, 1000)
        }
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
