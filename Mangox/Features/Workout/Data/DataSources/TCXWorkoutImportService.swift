import Foundation

enum TCXWorkoutImportError: LocalizedError {
    case invalidXML
    case noWorkoutData

    var errorDescription: String? {
        switch self {
        case .invalidXML:
            return "Could not read this TCX file."
        case .noWorkoutData:
            return "No workout data was found in this TCX file."
        }
    }
}

enum TCXWorkoutImportService {
    static func parse(data: Data) throws -> FITWorkoutCodec.ImportResult {
        let parser = XMLParser(data: data)
        let delegate = ParserDelegate()
        parser.delegate = delegate

        guard parser.parse() else {
            throw TCXWorkoutImportError.invalidXML
        }

        return try delegate.makeImportResult()
    }

    private struct TrackpointDraft {
        var time: Date?
        var distanceMeters: Double?
        var cadence: Double = 0
        var speedKmh: Double = 0
        var heartRate: Int = 0
        var power: Int = 0
    }

    private struct LapDraft {
        var startTime: Date?
        var totalTimeSeconds: Double = 0
        var distanceMeters: Double = 0
        var averageHeartRate: Double = 0
        var maximumHeartRate: Int = 0
        var cadence: Double = 0
        var averagePower: Double = 0
        var maximumPower: Int = 0
    }

    private final class ParserDelegate: NSObject, XMLParserDelegate {
        private(set) var trackpoints: [TrackpointDraft] = []
        private(set) var laps: [LapDraft] = []

        private var stack: [String] = []
        private var currentText = ""
        private var currentTrackpoint: TrackpointDraft?
        private var currentLap: LapDraft?
        private let iso8601Formatters: [ISO8601DateFormatter] = {
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let regular = ISO8601DateFormatter()
            regular.formatOptions = [.withInternetDateTime]
            return [fractional, regular]
        }()

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?,
            attributes attributeDict: [String: String] = [:]
        ) {
            stack.append(elementName)
            currentText = ""

            switch elementName {
            case "Trackpoint":
                currentTrackpoint = TrackpointDraft()
            case "Lap":
                var lap = LapDraft()
                if let startTimeRaw = attributeDict["StartTime"] {
                    lap.startTime = parseDate(startTimeRaw)
                }
                currentLap = lap
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            currentText += string
        }

        func parser(
            _ parser: XMLParser,
            didEndElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?
        ) {
            let value = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

            if !value.isEmpty {
                applyValue(value, for: elementName)
            }

            switch elementName {
            case "Trackpoint":
                if let currentTrackpoint, currentTrackpoint.time != nil {
                    trackpoints.append(currentTrackpoint)
                }
                currentTrackpoint = nil
            case "Lap":
                if let currentLap {
                    laps.append(currentLap)
                }
                currentLap = nil
            default:
                break
            }

            currentText = ""
            _ = stack.popLast()
        }

        func makeImportResult() throws -> FITWorkoutCodec.ImportResult {
            if !trackpoints.isEmpty {
                return try buildTrackpointResult()
            }
            if !laps.isEmpty {
                return try buildLapOnlyResult()
            }
            throw TCXWorkoutImportError.noWorkoutData
        }

        private func applyValue(_ value: String, for elementName: String) {
            if currentTrackpoint != nil {
                applyTrackpointValue(value, for: elementName)
            } else if currentLap != nil {
                applyLapValue(value, for: elementName)
            }
        }

        private func applyTrackpointValue(_ value: String, for elementName: String) {
            guard var trackpoint = currentTrackpoint else { return }

            switch elementName {
            case "Time":
                trackpoint.time = parseDate(value)
            case "DistanceMeters":
                trackpoint.distanceMeters = Double(value)
            case "Cadence":
                trackpoint.cadence = Double(value) ?? 0
            case "Speed":
                if let metersPerSecond = Double(value) {
                    trackpoint.speedKmh = metersPerSecond * 3.6
                }
            case "Watts":
                trackpoint.power = Int((Double(value) ?? 0).rounded())
            case "Value":
                if stack.contains("HeartRateBpm") {
                    trackpoint.heartRate = Int((Double(value) ?? 0).rounded())
                }
            default:
                break
            }

            currentTrackpoint = trackpoint
        }

        private func applyLapValue(_ value: String, for elementName: String) {
            guard var lap = currentLap else { return }

            switch elementName {
            case "TotalTimeSeconds":
                lap.totalTimeSeconds = Double(value) ?? 0
            case "DistanceMeters":
                lap.distanceMeters = Double(value) ?? 0
            case "Cadence":
                lap.cadence = Double(value) ?? 0
            case "Watts":
                if stack.contains("AverageWatts") {
                    lap.averagePower = Double(value) ?? 0
                } else if stack.contains("MaximumWatts") {
                    lap.maximumPower = Int((Double(value) ?? 0).rounded())
                }
            case "Value":
                if stack.contains("AverageHeartRateBpm") {
                    lap.averageHeartRate = Double(value) ?? 0
                } else if stack.contains("MaximumHeartRateBpm") {
                    lap.maximumHeartRate = Int((Double(value) ?? 0).rounded())
                }
            default:
                break
            }

            currentLap = lap
        }

        private func buildTrackpointResult() throws -> FITWorkoutCodec.ImportResult {
            let sorted = trackpoints.compactMap { draft -> TrackpointDraft? in
                guard draft.time != nil else { return nil }
                return draft
            }.sorted { ($0.time ?? .distantPast) < ($1.time ?? .distantPast) }

            guard let firstDate = sorted.first?.time,
                  let lastDate = sorted.last?.time else {
                throw TCXWorkoutImportError.noWorkoutData
            }

            let durationSeconds = max(1, Int(lastDate.timeIntervalSince(firstDate)))
            var samples: [(elapsed: Int, power: Int, cadence: Double, speed: Double, hr: Int)] = []
            samples.reserveCapacity(sorted.count)

            var powers: [Int] = []
            var maxPower = 0
            var powerSum = 0.0
            var heartRateSum = 0.0
            var heartRateCount = 0
            var maxHeartRate = 0
            var maxDistanceMeters = 0.0

            for trackpoint in sorted {
                guard let time = trackpoint.time else { continue }
                let elapsed = max(0, Int(time.timeIntervalSince(firstDate)))
                let power = trackpoint.power
                powers.append(power)
                powerSum += Double(power)
                maxPower = max(maxPower, power)

                let heartRate = trackpoint.heartRate
                if heartRate > 0 {
                    heartRateSum += Double(heartRate)
                    heartRateCount += 1
                    maxHeartRate = max(maxHeartRate, heartRate)
                }

                maxDistanceMeters = max(maxDistanceMeters, trackpoint.distanceMeters ?? 0)

                samples.append((
                    elapsed: elapsed,
                    power: power,
                    cadence: trackpoint.cadence,
                    speed: trackpoint.speedKmh,
                    hr: heartRate
                ))
            }

            let averagePower = powerSum / Double(max(1, sorted.count))
            let averageHeartRate = heartRateCount > 0
                ? heartRateSum / Double(heartRateCount)
                : 0

            return FITWorkoutCodec.ImportResult(
                startDate: firstDate,
                durationSeconds: durationSeconds,
                distanceMeters: maxDistanceMeters,
                avgPower: averagePower,
                maxPower: maxPower,
                avgHR: averageHeartRate,
                maxHR: maxHeartRate,
                powers: powers,
                samples: samples
            )
        }

        private func buildLapOnlyResult() throws -> FITWorkoutCodec.ImportResult {
            guard let firstLap = laps.first else {
                throw TCXWorkoutImportError.noWorkoutData
            }

            let startDate = firstLap.startTime ?? .now
            let durationSeconds = max(1, Int(laps.reduce(0.0) { $0 + $1.totalTimeSeconds }))
            let distanceMeters = laps.reduce(0.0) { $0 + $1.distanceMeters }
            let averagePower = laps.reduce(0.0) { $0 + $1.averagePower } / Double(max(1, laps.count))
            let maxPower = laps.map(\.maximumPower).max() ?? 0
            let averageHeartRate = laps.reduce(0.0) { $0 + $1.averageHeartRate } / Double(max(1, laps.count))
            let maxHeartRate = laps.map(\.maximumHeartRate).max() ?? 0

            return FITWorkoutCodec.ImportResult(
                startDate: startDate,
                durationSeconds: durationSeconds,
                distanceMeters: distanceMeters,
                avgPower: averagePower,
                maxPower: maxPower,
                avgHR: averageHeartRate,
                maxHR: maxHeartRate,
                powers: [],
                samples: []
            )
        }

        private func parseDate(_ value: String) -> Date? {
            for formatter in iso8601Formatters {
                if let date = formatter.date(from: value) {
                    return date
                }
            }
            return nil
        }
    }
}
