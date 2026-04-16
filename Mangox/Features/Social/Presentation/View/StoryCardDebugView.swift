// Features/Social/Presentation/View/StoryCardDebugView.swift
// TEMPORARY — delete after visual QA.
import SwiftUI
import UIKit

struct StoryCardDebugView: View {
    @State private var renderedImage: UIImage?
    @State private var savedPath: String?
    @State private var options = InstagramStoryCardOptions.default

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let image = renderedImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .padding(.horizontal, 12)
                } else {
                    ProgressView().tint(AppColor.mango)
                        .frame(height: 500)
                }

                if let path = savedPath {
                    Text(path)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.4))
                        .textSelection(.enabled)
                }

                Button("Re-render & Save") { render() }
                    .buttonStyle(.borderedProminent)
                    .tint(AppColor.mango)
            }
            .padding(.vertical, 16)
        }
        .background(AppColor.bg)
        .navigationTitle("Story Debug")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .onAppear { render() }
    }

    private func render() {
        let workout = Self.makeMockWorkout()
        let zone = PowerZone.zone(for: Int(workout.avgPower.rounded()))
        let image = InstagramStoryCardRenderer.render(
            workout: workout,
            dominantZone: zone,
            routeName: "Col du Galibier",
            totalElevationGain: 824,
            personalRecordNames: [],
            options: options,
            sessionKind: .outdoor,
            whoopStrain: 12.4,
            whoopRecovery: 68,
            aiTitle: "Climb Day"
        )
        renderedImage = image
        savedPath = Self.saveToDisk(image)
    }

    static func saveToDisk(_ image: UIImage) -> String? {
        guard let data = image.pngData() else { return nil }
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let url = dir.appendingPathComponent("story_debug.png")
        try? data.write(to: url)
        return url.path
    }

    static func makeMockWorkout() -> Workout {
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
        let zones: [(range: ClosedRange<Int>, weight: Int)] = [
            (100...145, 8),
            (146...199, 22),
            (199...230, 31),
            (231...278, 26),
            (279...380, 13),
        ]
        var elapsed = 0
        for zone in zones {
            let count = zone.weight * 79
            for _ in 0..<count {
                let power = Int.random(in: zone.range)
                let hr = min(190, 120 + power / 4 + Int.random(in: -5...5))
                let cadence = Double(Int.random(in: 75...95))
                let speed = Double.random(in: 18...38)
                samples.append(WorkoutSample(
                    timestamp: workout.startDate.addingTimeInterval(TimeInterval(elapsed)),
                    elapsedSeconds: elapsed,
                    power: power,
                    cadence: cadence,
                    speed: speed,
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

#Preview {
    NavigationStack {
        StoryCardDebugView()
    }
}
