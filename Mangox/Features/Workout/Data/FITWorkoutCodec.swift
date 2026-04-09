import Foundation
import AntMessageProtocol
import FitDataProtocol
import FitnessUnits

// MARK: - Export

enum FITWorkoutCodec {

    static func encodeActivity(workout: Workout) throws -> Data {
        let samples = workout.samples.sorted { $0.elapsedSeconds < $1.elapsedSeconds }
        guard !samples.isEmpty else { throw WorkoutExportError.noSamples }

        let start = workout.startDate
        let fileTime = FitTime(date: start)
        let serial: UInt32 = {
            let h = UInt32(bitPattern: Int32(truncatingIfNeeded: workout.id.hashValue))
            return h == 0 ? 1 : h
        }()

        let fileId = FileIdMessage(
            deviceSerialNumber: serial,
            fileCreationDate: fileTime,
            manufacturer: Manufacturer.garmin,
            product: 0,
            fileNumber: nil,
            fileType: .activity,
            productName: "Mangox"
        )

        var messages: [FitMessage] = []

        let increments = WorkoutExportService.scaledDistanceIncrements(
            samples: samples,
            targetMeters: workout.distance
        )
        var cumulativeDistance: Double = 0
        for (idx, s) in samples.enumerated() {
            let t = FitTime(date: start.addingTimeInterval(TimeInterval(s.elapsedSeconds)))
            cumulativeDistance += increments[idx]
            let dt = WorkoutExportService.elapsedDeltaSeconds(samples: samples, index: idx)
            let speedMps = max(0, increments[idx] / dt)
            let dist = Measurement(value: cumulativeDistance, unit: UnitLength.meters)
            let spd = Measurement(value: speedMps, unit: UnitSpeed.metersPerSecond)
            let pwr = Measurement(value: Double(s.power), unit: UnitPower.watts)

            let rec = RecordMessage(
                timeStamp: t,
                distance: dist,
                speed: spd,
                power: pwr,
                heartRate: s.heartRate > 0 ? UInt8(clamping: s.heartRate) : nil,
                cadence: s.cadence > 0 ? UInt8(clamping: Int(s.cadence.rounded())) : nil,
                activity: ActivityType.cycling
            )
            messages.append(rec)
        }

        let laps = workout.laps.sorted { $0.lapNumber < $1.lapNumber }
        if laps.count > 1 {
            for lap in laps {
                let lapStart = FitTime(date: lap.startTime)
                let dur = Measurement(value: lap.duration, unit: UnitDuration.seconds)
                let lapDist = Measurement(value: max(0, lap.distance), unit: UnitLength.meters)
                let avgP = Measurement(value: lap.avgPower, unit: UnitPower.watts)
                let maxP = Measurement(value: Double(lap.maxPower), unit: UnitPower.watts)
                let lm = LapMessage(
                    timeStamp: lapStart,
                    event: .lap,
                    eventType: .stop,
                    startTime: lapStart,
                    totalTimerTime: dur,
                    totalDistance: lapDist,
                    averagePower: avgP,
                    maximumPower: maxP,
                    sport: Sport.cycling
                )
                messages.append(lm)
            }
        } else {
            let lapStart = FitTime(date: start)
            let dur = Measurement(value: workout.duration, unit: UnitDuration.seconds)
            let lapDist = Measurement(value: max(0, workout.distance), unit: UnitLength.meters)
            let avgP = Measurement(value: workout.avgPower, unit: UnitPower.watts)
            let maxP = Measurement(value: Double(workout.maxPower), unit: UnitPower.watts)
            let lm = LapMessage(
                timeStamp: lapStart,
                event: .lap,
                eventType: .stop,
                startTime: lapStart,
                totalTimerTime: dur,
                totalDistance: lapDist,
                averagePower: avgP,
                maximumPower: maxP,
                sport: Sport.cycling
            )
            messages.append(lm)
        }

        let elapsed = Measurement(value: Double(workout.duration), unit: UnitDuration.seconds)
        let timer = Measurement(value: Double(workout.duration), unit: UnitDuration.seconds)
        let distM = Measurement(value: max(0, workout.distance), unit: UnitLength.meters)
        let avgPow = Measurement(value: workout.avgPower, unit: UnitPower.watts)
        let maxPow = Measurement(value: Double(workout.maxPower), unit: UnitPower.watts)
        let npMeas = Measurement(value: workout.normalizedPower, unit: UnitPower.watts)
        let avgHR = workout.avgHR > 0 ? UInt8(clamping: Int(workout.avgHR.rounded())) : nil
        let maxHR = workout.maxHR > 0 ? UInt8(clamping: workout.maxHR) : nil

        let sessionStart = FitTime(date: start)
        let session = SessionMessage(
            timeStamp: FitTime(date: workout.endDate ?? start.addingTimeInterval(workout.duration)),
            event: .session,
            eventType: .stop,
            startTime: sessionStart,
            sport: Sport.cycling,
            totalElapsedTime: elapsed,
            totalTimerTime: timer,
            totalDistance: distM,
            averageHeartRate: avgHR,
            maximumHeartRate: maxHR,
            averagePower: avgPow,
            maximumPower: maxPow,
            numberOfLaps: UInt16(clamping: max(1, laps.count)),
            normalizedPower: workout.normalizedPower > 0 ? npMeas : nil
        )
        messages.append(session)

        let activity = ActivityMessage(
            timeStamp: FitTime(date: workout.endDate ?? start.addingTimeInterval(workout.duration)),
            totalTimerTime: timer,
            localTimeStamp: nil,
            numberOfSessions: 1,
            activity: Activity.manual,
            event: nil,
            eventType: nil,
            eventGroup: nil
        )
        messages.append(activity)

        let encoder = FitFileEncoder(dataValidityStrategy: .none)
        let result = encoder.encode(fildIdMessage: fileId, messages: messages)
        switch result {
        case .success(let data):
            return data
        case .failure(let err):
            throw WorkoutExportError.writeFailed(err.localizedDescription)
        }
    }

    // MARK: - Import

    struct ImportResult {
        let startDate: Date
        let durationSeconds: Int
        let distanceMeters: Double
        let avgPower: Double
        let maxPower: Int
        let avgHR: Double
        let maxHR: Int
        let powers: [Int]
        let samples: [(elapsed: Int, power: Int, cadence: Double, speed: Double, hr: Int)]
    }

    static func decodeActivity(data: Data) throws -> ImportResult {
        var records: [RecordMessage] = []
        var session: SessionMessage?

        var decoder = FitFileDecoder(crcCheckingStrategy: .throws)
        try decoder.decode(data: data, messages: FitFileDecoder.defaultMessages) { msg in
            if let r = msg as? RecordMessage { records.append(r) }
            if let s = msg as? SessionMessage { session = s }
        }

        if records.isEmpty, let sess = session {
            return try importFromSessionOnly(sess)
        }
        guard !records.isEmpty else {
            throw WorkoutExportError.noSamples
        }

        let sorted = records.sorted { ($0.timeStamp?.recordDate ?? .distantPast) < ($1.timeStamp?.recordDate ?? .distantPast) }
        guard let firstDate = sorted.first?.timeStamp?.recordDate,
              let lastDate = sorted.last?.timeStamp?.recordDate else {
            throw WorkoutExportError.writeFailed("FIT records missing timestamps")
        }

        let durationSeconds = max(1, Int(lastDate.timeIntervalSince(firstDate)))
        var samples: [(elapsed: Int, power: Int, cadence: Double, speed: Double, hr: Int)] = []
        samples.reserveCapacity(sorted.count)
        var powers: [Int] = []
        var maxP = 0
        var sumP = 0.0
        var sumHR = 0.0
        var hrCount = 0
        var maxHR = 0

        var cumulativeDistance: Double = 0
        for (idx, rec) in sorted.enumerated() {
            let t = rec.timeStamp?.recordDate ?? firstDate.addingTimeInterval(TimeInterval(idx))
            let elapsed = max(0, Int(t.timeIntervalSince(firstDate)))
            let p = Int(rec.power?.value.rounded() ?? 0)
            powers.append(p)
            sumP += Double(p)
            if p > maxP { maxP = p }

            let c = rec.cadence?.value ?? 0
            let spdKmh = (rec.speed?.value ?? 0) * 3.6
            let hr = Int(rec.heartRate?.value.rounded() ?? 0)
            if hr > 0 {
                sumHR += Double(hr)
                hrCount += 1
                maxHR = max(maxHR, hr)
            }

            if let d = rec.distance?.value {
                cumulativeDistance = d
            }

            samples.append((elapsed: elapsed, power: p, cadence: c, speed: spdKmh, hr: hr))
        }

        let avgP = sumP / Double(max(1, sorted.count))
        let avgHR = hrCount > 0 ? sumHR / Double(hrCount) : 0

        let dist = session?.totalDistance?.value ?? cumulativeDistance

        return ImportResult(
            startDate: firstDate,
            durationSeconds: durationSeconds,
            distanceMeters: dist,
            avgPower: avgP,
            maxPower: maxP,
            avgHR: avgHR,
            maxHR: maxHR,
            powers: powers,
            samples: samples
        )
    }

    private static func importFromSessionOnly(_ session: SessionMessage) throws -> ImportResult {
        guard let start = session.startTime?.recordDate else {
            throw WorkoutExportError.writeFailed("FIT session missing start time")
        }
        let dur = Int(session.totalTimerTime?.value ?? session.totalElapsedTime?.value ?? 0)
        let dist = session.totalDistance?.value ?? 0
        let avgP = session.averagePower?.value ?? 0
        let maxP = Int(session.maximumPower?.value.rounded() ?? 0)
        return ImportResult(
            startDate: start,
            durationSeconds: max(1, dur),
            distanceMeters: dist,
            avgPower: avgP,
            maxPower: maxP,
            avgHR: session.averageHeartRate?.value ?? 0,
            maxHR: Int(session.maximumHeartRate?.value ?? 0),
            powers: [],
            samples: []
        )
    }
}
