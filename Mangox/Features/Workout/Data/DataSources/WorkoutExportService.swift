// Features/Workout/Data/DataSources/WorkoutExportService.swift
import Foundation
import CoreLocation

// MARK: - Export Format

enum ExportFormat: String, CaseIterable, Identifiable {
    case tcx = "TCX"
    case gpx = "GPX"

    var id: String { rawValue }

    var fileExtension: String { rawValue.lowercased() }

    var displayName: String {
        switch self {
        case .tcx: return "TCX (Recommended)"
        case .gpx: return "GPX"
        }
    }

    var subtitle: String {
        switch self {
        case .tcx: return "Best for indoor rides · Includes laps, power, HR"
        case .gpx: return "Requires route · Universal GPS format"
        }
    }
}

// MARK: - Errors

enum WorkoutExportError: LocalizedError {
    case noRouteLoaded
    case noSamples
    case noTrackpoints
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .noRouteLoaded:
            return "Load a GPX route first so Mangox can map distance to GPS points."
        case .noSamples:
            return "This workout has no samples to export."
        case .noTrackpoints:
            return "Unable to generate route trackpoints for export."
        case .writeFailed(let reason):
            return "Failed to write export file: \(reason)"
        }
    }
}

// MARK: - Export Service

enum WorkoutExportService {

    // MARK: - Public API

    /// Export a workout in the specified format.
    /// TCX is preferred for indoor rides — it works without a route and natively supports
    /// power, cadence, HR, laps, and calories.
    /// GPX requires a route for coordinate mapping but uses standard Garmin extension namespaces
    /// that Strava, TrainingPeaks, and Garmin Connect all recognize.
    static func export(
        workout: Workout,
        format: ExportFormat,
        routeService: (any RouteServiceProtocol)? = nil
    ) throws -> URL {
        switch format {
        case .tcx:
            return try exportTCX(workout: workout, routeService: routeService)
        case .gpx:
            return try exportGPX(workout: workout, routeService: routeService)
        }
    }

    /// Legacy convenience method — exports GPX (backward compatible with old call sites).
    static func exportGPX(workout: Workout, routeManager: RouteManager) throws -> URL {
        try export(workout: workout, format: .gpx, routeService: routeManager)
    }

    /// Whether a given format can export without a loaded route.
    static func canExport(format: ExportFormat, hasRoute: Bool) -> Bool {
        switch format {
        case .tcx: return true       // TCX works without GPS coordinates
        case .gpx: return hasRoute   // GPX needs coordinates
        }
    }

    // MARK: - Distance alignment (TCX / GPX)

    /// Raw per-second speed integration often under-reports vs the wheel/sensor total stored on `Workout` / `LapSplit`.
    /// Strava recomputes distance from trackpoints, so we scale sample increments so they sum to `targetMeters`.
    /// Also used by `FITWorkoutCodec` so FIT record distances match session totals.
    static func scaledDistanceIncrements(samples: [WorkoutSample], targetMeters: Double) -> [Double] {
        let n = samples.count
        guard n > 0 else { return [] }
        if targetMeters <= 0 {
            return Array(repeating: 0, count: n)
        }
        let raw = samples.map { max(0, $0.speed / 3.6) }
        let rawSum = raw.reduce(0, +)
        if rawSum > 0.001 {
            let scale = targetMeters / rawSum
            return raw.map { $0 * scale }
        }
        let each = targetMeters / Double(n)
        return Array(repeating: each, count: n)
    }

    /// Seconds between this sample and the previous (minimum 1) for speed = Δdistance / Δtime on exports.
    static func elapsedDeltaSeconds(samples: [WorkoutSample], index: Int) -> Double {
        guard index < samples.count else { return 1 }
        if index == 0 {
            let e = samples[0].elapsedSeconds
            return Double(max(1, e))
        }
        let d = samples[index].elapsedSeconds - samples[index - 1].elapsedSeconds
        return Double(max(1, d))
    }

    // MARK: - TCX Export

    /// Exports to Training Center XML (TCX) — the ideal format for indoor trainer data.
    ///
    /// Structure: Activity → Lap[] → Track → Trackpoint[]
    /// Each trackpoint contains time, HR, cadence, power, speed, and optionally position.
    /// Laps contain summary stats (avg/max HR, avg/max power, calories, distance, etc.)
    private static func exportTCX(
        workout: Workout,
        routeService: (any RouteServiceProtocol)?
    ) throws -> URL {
        let samples = workout.samples.sorted { $0.elapsedSeconds < $1.elapsedSeconds }
        guard !samples.isEmpty else { throw WorkoutExportError.noSamples }

        let laps = workout.laps.sorted { $0.lapNumber < $1.lapNumber }
        let hasRoute = routeService?.hasRoute == true

        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <TrainingCenterDatabase
          xmlns="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2"
          xmlns:tpx="http://www.garmin.com/xmlschemas/ActivityExtension/v2"
          xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
          xsi:schemaLocation="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2
            http://www.garmin.com/xmlschemas/TrainingCenterDatabasev2.xsd">
          <Activities>
            <Activity Sport="Biking">
              <Id>\(iso8601(workout.startDate))</Id>
              <Creator xsi:type="Device_t">
                <Name>Mangox Indoor Cycling</Name>
                <UnitId>0</UnitId>
                <ProductID>0</ProductID>
              </Creator>\n
        """

        if laps.count > 1 {
            // Multi-lap: emit each lap with its own track.
            // Single-pass partitioning: iterate samples once, appending each to the correct lap.
            var lapSamplesBuckets: [[WorkoutSample]] = Array(repeating: [], count: laps.count)
            var lapBounds: [(start: Int, end: Int)] = []
            var runningStart = 0
            for lap in laps {
                let end = runningStart + Int(lap.duration)
                lapBounds.append((start: runningStart, end: end))
                runningStart = end
            }
            for sample in samples {
                for (idx, bound) in lapBounds.enumerated() {
                    if sample.elapsedSeconds > bound.start && sample.elapsedSeconds <= bound.end {
                        lapSamplesBuckets[idx].append(sample)
                        break
                    }
                }
            }

            var distanceOffset: Double = 0
            for (idx, lap) in laps.enumerated() {
                let lapSamples = lapSamplesBuckets[idx]

                let lapCalories = estimateCalories(
                    avgPower: lap.avgPower,
                    durationSeconds: lap.duration
                )

                xml += tcxLap(
                    startTime: lap.startTime,
                    durationSeconds: lap.duration,
                    distanceMeters: lap.distance,
                    calories: lapCalories,
                    avgHR: lap.avgHR > 0 ? Int(lap.avgHR.rounded()) : nil,
                    maxHR: nil, // LapSplit doesn't track maxHR per lap
                    avgPower: Int(lap.avgPower.rounded()),
                    maxPower: lap.maxPower,
                    avgCadence: Int(lap.avgCadence.rounded()),
                    avgSpeed: lap.avgSpeed,
                    samples: lapSamples,
                    workout: workout,
                    routeService: hasRoute ? routeService : nil,
                    distanceOffset: distanceOffset
                )

                distanceOffset += lap.distance
            }
        } else {
            // Single lap: emit all samples in one lap
            let totalCalories = estimateCalories(
                avgPower: workout.avgPower,
                durationSeconds: workout.duration
            )

            xml += tcxLap(
                startTime: workout.startDate,
                durationSeconds: workout.duration,
                distanceMeters: workout.distance,
                calories: totalCalories,
                avgHR: workout.avgHR > 0 ? Int(workout.avgHR.rounded()) : nil,
                maxHR: workout.maxHR > 0 ? workout.maxHR : nil,
                avgPower: Int(workout.avgPower.rounded()),
                maxPower: workout.maxPower,
                avgCadence: Int(workout.avgCadence.rounded()),
                avgSpeed: workout.avgSpeed,
                samples: samples,
                workout: workout,
                routeService: hasRoute ? routeService : nil,
                distanceOffset: 0
            )
        }

        xml += """
            </Activity>
          </Activities>
        </TrainingCenterDatabase>
        """

        let url = exportDirectory()
            .appendingPathComponent("mangox-\(workout.id.uuidString).tcx")

        do {
            try xml.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw WorkoutExportError.writeFailed(error.localizedDescription)
        }

        return url
    }

    private static func tcxLap(
        startTime: Date,
        durationSeconds: TimeInterval,
        distanceMeters: Double,
        calories: Int,
        avgHR: Int?,
        maxHR: Int?,
        avgPower: Int,
        maxPower: Int,
        avgCadence: Int,
        avgSpeed: Double,
        samples: [WorkoutSample],
        workout: Workout,
        routeService: (any RouteServiceProtocol)?,
        distanceOffset: Double = 0
    ) -> String {
        // Start accumulation from the offset so multi-lap exports look up the
        // correct coordinate/elevation on the GPX route for every trackpoint.
        let increments = scaledDistanceIncrements(samples: samples, targetMeters: distanceMeters)
        var cumulativeDistance: Double = distanceOffset
        var trackpointParts: [String] = []
        trackpointParts.reserveCapacity(samples.count)

        for (idx, sample) in samples.enumerated() {
            cumulativeDistance += increments[idx]

            let coordinate: CLLocationCoordinate2D?
            let elevationMeters: Double?
            if let rs = routeService {
                coordinate = rs.coordinate(forDistance: cumulativeDistance)
                elevationMeters = rs.elevation(forDistance: cumulativeDistance)
            } else {
                coordinate = nil
                elevationMeters = nil
            }

            let time = iso8601(workout.startDate.addingTimeInterval(TimeInterval(sample.elapsedSeconds)))

            var tp = "          <Trackpoint>\n"
            tp += "            <Time>\(time)</Time>\n"

            if let coord = coordinate {
                tp += "            <Position>\n"
                tp += "              <LatitudeDegrees>\(coord.latitude)</LatitudeDegrees>\n"
                tp += "              <LongitudeDegrees>\(coord.longitude)</LongitudeDegrees>\n"
                tp += "            </Position>\n"
            }

            if let elevationMeters {
                tp += "            <AltitudeMeters>\(String(format: "%.1f", elevationMeters))</AltitudeMeters>\n"
            }

            tp += "            <DistanceMeters>\(String(format: "%.1f", cumulativeDistance))</DistanceMeters>\n"

            if sample.heartRate > 0 {
                tp += "            <HeartRateBpm><Value>\(sample.heartRate)</Value></HeartRateBpm>\n"
            }

            if sample.cadence > 0 {
                tp += "            <Cadence>\(Int(sample.cadence.rounded()))</Cadence>\n"
            }

            // Speed (m/s) matches scaled distance increment over elapsed delta — consistent with DistanceMeters.
            let dt = elapsedDeltaSeconds(samples: samples, index: idx)
            let speedMps = max(0, increments[idx] / dt)

            // Garmin ActivityExtension/v2: power + speed
            tp += "            <Extensions>\n"
            tp += "              <tpx:TPX>\n"
            tp += "                <tpx:Speed>\(String(format: "%.2f", speedMps))</tpx:Speed>\n"
            tp += "                <tpx:Watts>\(sample.power)</tpx:Watts>\n"
            tp += "              </tpx:TPX>\n"
            tp += "            </Extensions>\n"

            tp += "          </Trackpoint>\n"

            trackpointParts.append(tp)
        }

        let trackpoints = trackpointParts.joined()

        // Build lap XML
        var lap = ""
        lap += "      <Lap StartTime=\"\(iso8601(startTime))\">\n"
        lap += "        <TotalTimeSeconds>\(String(format: "%.1f", durationSeconds))</TotalTimeSeconds>\n"
        lap += "        <DistanceMeters>\(String(format: "%.1f", distanceMeters))</DistanceMeters>\n"
        lap += "        <Calories>\(calories)</Calories>\n"

        if let avgHR {
            lap += "        <AverageHeartRateBpm><Value>\(avgHR)</Value></AverageHeartRateBpm>\n"
        }
        if let maxHR {
            lap += "        <MaximumHeartRateBpm><Value>\(maxHR)</Value></MaximumHeartRateBpm>\n"
        }

        lap += "        <Intensity>Active</Intensity>\n"
        lap += "        <TriggerMethod>Manual</TriggerMethod>\n"

        // Lap-level extensions: avg power, max power, avg speed, avg cadence
        let lapAvgSpeedMps = durationSeconds > 0
            ? distanceMeters / durationSeconds
            : max(0, avgSpeed / 3.6)
        lap += "        <Extensions>\n"
        lap += "          <tpx:LX>\n"
        lap += "            <tpx:AvgSpeed>\(String(format: "%.2f", max(0, lapAvgSpeedMps)))</tpx:AvgSpeed>\n"
        lap += "            <tpx:AvgWatts>\(avgPower)</tpx:AvgWatts>\n"
        lap += "            <tpx:MaxWatts>\(maxPower)</tpx:MaxWatts>\n"
        lap += "          </tpx:LX>\n"
        lap += "        </Extensions>\n"

        lap += "        <Track>\n"
        lap += trackpoints
        lap += "        </Track>\n"
        lap += "      </Lap>\n"

        return lap
    }

    // MARK: - GPX Export

    /// Exports to GPX 1.1 with standard Garmin extension namespaces.
    ///
    /// Uses:
    /// - `gpxtpx:TrackPointExtension` for HR, cadence, speed, temperature
    /// - `pwr:PowerExtension` for power
    ///
    /// These are the namespaces that Strava, Garmin Connect, TrainingPeaks,
    /// and Golden Cheetah all parse automatically.
    private static func exportGPX(
        workout: Workout,
        routeService: (any RouteServiceProtocol)?
    ) throws -> URL {
        let hasRoute = routeService?.hasRoute == true
        guard hasRoute else { throw WorkoutExportError.noRouteLoaded }

        let samples = workout.samples.sorted { $0.elapsedSeconds < $1.elapsedSeconds }
        guard !samples.isEmpty else { throw WorkoutExportError.noSamples }

        let routeName = xmlEscaped(
            "Mangox Ride \(workout.startDate.formatted(date: .abbreviated, time: .shortened))"
        )

        let increments = scaledDistanceIncrements(samples: samples, targetMeters: workout.distance)
        var cumulativeDistance: Double = 0
        var trackpoints: [String] = []

        let trimStart = RidePreferences.shared.gpxPrivacyTrimStartMeters
        let trimEnd = RidePreferences.shared.gpxPrivacyTrimEndMeters
        let routeLen = max(workout.distance, 1)

        for (idx, sample) in samples.enumerated() {
            cumulativeDistance += increments[idx]

            if GPXPrivacyTrimLogic.isExcluded(
                cumulativeDistanceAlongRoute: cumulativeDistance,
                trimStartMeters: trimStart,
                trimEndMeters: trimEnd,
                routeLengthMeters: routeLen
            ) {
                continue
            }

            guard let coordinate = routeService?.coordinate(forDistance: cumulativeDistance) else {
                continue
            }
            let elevationMeters = routeService?.elevation(forDistance: cumulativeDistance)

            let time = iso8601(workout.startDate.addingTimeInterval(TimeInterval(sample.elapsedSeconds)))
            let dt = elapsedDeltaSeconds(samples: samples, index: idx)
            let speedMps = max(0, increments[idx] / dt)

            var trkpt = ""
            trkpt += "      <trkpt lat=\"\(coordinate.latitude)\" lon=\"\(coordinate.longitude)\">\n"
            if let elevationMeters {
                trkpt += "        <ele>\(String(format: "%.1f", elevationMeters))</ele>\n"
            }
            trkpt += "        <time>\(time)</time>\n"
            trkpt += "        <extensions>\n"

            // Garmin TrackPointExtension (HR, cadence, speed)
            trkpt += "          <gpxtpx:TrackPointExtension>\n"
            if sample.heartRate > 0 {
                trkpt += "            <gpxtpx:hr>\(sample.heartRate)</gpxtpx:hr>\n"
            }
            if sample.cadence > 0 {
                trkpt += "            <gpxtpx:cad>\(Int(sample.cadence.rounded()))</gpxtpx:cad>\n"
            }
            trkpt += "            <gpxtpx:speed>\(String(format: "%.2f", speedMps))</gpxtpx:speed>\n"
            trkpt += "          </gpxtpx:TrackPointExtension>\n"

            // Power extension
            trkpt += "          <pwr:PowerExtension>\n"
            trkpt += "            <pwr:Watts>\(sample.power)</pwr:Watts>\n"
            trkpt += "          </pwr:PowerExtension>\n"

            trkpt += "        </extensions>\n"
            trkpt += "      </trkpt>"

            trackpoints.append(trkpt)
        }

        if trackpoints.isEmpty, trimStart > 0 || trimEnd > 0 {
            // Privacy trim removed every point — fall back to full export.
            cumulativeDistance = 0
            trackpoints = []
            for (idx, sample) in samples.enumerated() {
                cumulativeDistance += increments[idx]
                guard let coordinate = routeService?.coordinate(forDistance: cumulativeDistance) else {
                    continue
                }
                let elevationMeters = routeService?.elevation(forDistance: cumulativeDistance)
                let time = iso8601(workout.startDate.addingTimeInterval(TimeInterval(sample.elapsedSeconds)))
                let dt = elapsedDeltaSeconds(samples: samples, index: idx)
                let speedMps = max(0, increments[idx] / dt)
                var trkpt = ""
                trkpt += "      <trkpt lat=\"\(coordinate.latitude)\" lon=\"\(coordinate.longitude)\">\n"
                if let elevationMeters {
                    trkpt += "        <ele>\(String(format: "%.1f", elevationMeters))</ele>\n"
                }
                trkpt += "        <time>\(time)</time>\n"
                trkpt += "        <extensions>\n"
                trkpt += "          <gpxtpx:TrackPointExtension>\n"
                if sample.heartRate > 0 {
                    trkpt += "            <gpxtpx:hr>\(sample.heartRate)</gpxtpx:hr>\n"
                }
                if sample.cadence > 0 {
                    trkpt += "            <gpxtpx:cad>\(Int(sample.cadence.rounded()))</gpxtpx:cad>\n"
                }
                trkpt += "            <gpxtpx:speed>\(String(format: "%.2f", speedMps))</gpxtpx:speed>\n"
                trkpt += "          </gpxtpx:TrackPointExtension>\n"
                trkpt += "          <pwr:PowerExtension>\n"
                trkpt += "            <pwr:Watts>\(sample.power)</pwr:Watts>\n"
                trkpt += "          </pwr:PowerExtension>\n"
                trkpt += "        </extensions>\n"
                trkpt += "      </trkpt>"
                trackpoints.append(trkpt)
            }
        }

        guard !trackpoints.isEmpty else { throw WorkoutExportError.noTrackpoints }

        let metadata = gpxMetadata(workout: workout)

        var gpx = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        gpx += "<gpx version=\"1.1\"\n"
        gpx += "  creator=\"Mangox Indoor Cycling\"\n"
        gpx += "  xmlns=\"http://www.topografix.com/GPX/1/1\"\n"
        gpx += "  xmlns:gpxtpx=\"http://www.garmin.com/xmlschemas/TrackPointExtension/v2\"\n"
        gpx += "  xmlns:pwr=\"http://www.garmin.com/xmlschemas/PowerExtension/v1\"\n"
        gpx += "  xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\"\n"
        gpx += "  xsi:schemaLocation=\"http://www.topografix.com/GPX/1/1 http://www.topografix.com/GPX/1/1/gpx.xsd http://www.garmin.com/xmlschemas/TrackPointExtension/v2 http://www.garmin.com/xmlschemas/TrackPointExtensionv2.xsd http://www.garmin.com/xmlschemas/PowerExtension/v1 http://www.garmin.com/xmlschemas/PowerExtensionv1.xsd\">\n"
        gpx += metadata
        gpx += "  <trk>\n"
        gpx += "    <name>\(routeName)</name>\n"
        gpx += "    <type>cycling</type>\n"
        gpx += "    <trkseg>\n"
        gpx += trackpoints.joined(separator: "\n")
        gpx += "\n    </trkseg>\n"
        gpx += "  </trk>\n"
        gpx += "</gpx>\n"

        let url = exportDirectory()
            .appendingPathComponent("mangox-\(workout.id.uuidString).gpx")

        do {
            try gpx.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw WorkoutExportError.writeFailed(error.localizedDescription)
        }

        return url
    }

    // MARK: - GPX Metadata

    /// Builds a `<metadata>` block with workout summary info embedded as description.
    /// Strava and other platforms display this in the activity notes.
    private static func gpxMetadata(workout: Workout) -> String {
        let startTime = iso8601(workout.startDate)
        let durationMin = Int(workout.duration) / 60
        let distKm = String(format: "%.2f", workout.distance / 1000)
        let avgPwr = Int(workout.avgPower.rounded())
        let np = Int(workout.normalizedPower.rounded())
        let tss = String(format: "%.0f", workout.tss)
        let ifVal = String(format: "%.2f", workout.intensityFactor)
        let calories = estimateCalories(avgPower: workout.avgPower, durationSeconds: workout.duration)

        var desc = "Duration: \(durationMin) min"
        desc += " | Distance: \(distKm) km"
        desc += " | Avg Power: \(avgPwr) W"
        if workout.normalizedPower > 0 {
            desc += " | NP: \(np) W"
        }
        desc += " | Max Power: \(workout.maxPower) W"
        if workout.tss > 0 {
            desc += " | TSS: \(tss) | IF: \(ifVal)"
        }
        desc += " | Calories: \(calories) kcal"
        if workout.avgHR > 0 {
            desc += " | Avg HR: \(Int(workout.avgHR)) bpm"
        }
        if workout.maxHR > 0 {
            desc += " | Max HR: \(workout.maxHR) bpm"
        }

        var meta = "  <metadata>\n"
        meta += "    <name>\(xmlEscaped("Mangox Ride"))</name>\n"
        meta += "    <desc>\(xmlEscaped(desc))</desc>\n"
        meta += "    <author><name>Mangox</name></author>\n"
        meta += "    <time>\(startTime)</time>\n"
        meta += "  </metadata>\n"
        return meta
    }

    // MARK: - Calorie Estimation

    /// Estimates calories burned from cycling power output.
    ///
    /// Uses the standard gross metabolic efficiency model:
    /// - Mechanical efficiency of cycling ≈ 22–25% (we use 24%)
    /// - Gross metabolic rate = power / efficiency
    /// - 1 kcal ≈ 4184 J
    ///
    /// This matches Strava's and TrainingPeaks' calorie models closely.
    static func estimateCalories(avgPower: Double, durationSeconds: TimeInterval) -> Int {
        guard avgPower > 0, durationSeconds > 0 else { return 0 }
        let efficiency = 0.24
        let metabolicWatts = avgPower / efficiency
        let joules = metabolicWatts * durationSeconds
        let kcal = joules / 4184.0
        return Int(kcal.rounded())
    }

    // MARK: - Formatting Helpers

    /// ISO 8601 date string with Zulu time — the format all GPS/fitness XML schemas expect.
    private static let iso8601Formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static func iso8601(_ date: Date) -> String {
        iso8601Formatter.string(from: date)
    }

    // MARK: - Export Directory

    /// Returns a stable, accessible directory for exported workout files.
    /// Uses the app's Documents directory instead of NSTemporaryDirectory so that:
    /// 1. Files persist long enough for Strava/Garmin/etc. to read them after the share sheet opens
    /// 2. The system grants proper file access to receiving apps via the share extension
    /// 3. Files survive app backgrounding during the share flow
    ///
    /// Old exports are cleaned up each time a new export is created.
    private static func exportDirectory() -> URL {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return URL(fileURLWithPath: NSTemporaryDirectory())
        }
        let exportDir = docs.appendingPathComponent("Exports", isDirectory: true)

        // Ensure directory exists
        try? FileManager.default.createDirectory(at: exportDir, withIntermediateDirectories: true)

        // Clean up old exports (keep directory tidy — remove files older than 1 hour)
        if let contents = try? FileManager.default.contentsOfDirectory(
            at: exportDir,
            includingPropertiesForKeys: [.creationDateKey],
            options: .skipsHiddenFiles
        ) {
            let cutoff = Date().addingTimeInterval(-3600)
            for fileURL in contents {
                if let attrs = try? fileURL.resourceValues(forKeys: [.creationDateKey]),
                   let created = attrs.creationDate,
                   created < cutoff {
                    try? FileManager.default.removeItem(at: fileURL)
                }
            }
        }

        return exportDir
    }

    /// Escapes special XML characters.
    private static func xmlEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
