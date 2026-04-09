// Features/Workout/Data/DataSources/ZWOImportService.swift
import Foundation

enum ZWOImportError: LocalizedError {
    case invalidXML
    case noSegments

    var errorDescription: String? {
        switch self {
        case .invalidXML: return "Could not read this ZWO file."
        case .noSegments: return "No workout steps found in file."
        }
    }
}

/// Parses Zwift-style ZWO (subset) into `IntervalSegment`s.
enum ZWOImportService {

    static func parse(data: Data) throws -> (name: String, intervals: [IntervalSegment]) {
        let parser = XMLParser(data: data)
        let delegate = ZWOParserDelegate()
        parser.delegate = delegate
        guard parser.parse() else {
            throw ZWOImportError.invalidXML
        }
        guard !delegate.intervals.isEmpty else { throw ZWOImportError.noSegments }
        let name = delegate.workoutName.isEmpty ? "Imported workout" : delegate.workoutName
        return (name, delegate.intervals.sorted { $0.order < $1.order })
    }

    private final class ZWOParserDelegate: NSObject, XMLParserDelegate {
        var workoutName = ""
        var intervals: [IntervalSegment] = []
        private var order = 1
        private var stack: [String] = []

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
            stack.append(elementName)
            let lower = elementName.lowercased()

            if lower == "name", stack.contains(where: { $0.lowercased() == "workout" }) {
                // handled in foundCharacters
            }

            if lower == "steadystate" {
                let dur = Int(attributeDict["Duration"] ?? "") ?? 300
                let power = Double(attributeDict["Power"] ?? "0.65") ?? 0.65
                let zone = zoneFromFTPFraction(power)
                intervals.append(IntervalSegment(
                    order: order,
                    name: "Steady",
                    durationSeconds: dur,
                    zone: zone,
                    repeats: 1,
                    notes: "",
                    suggestedTrainerMode: .erg
                ))
                order += 1
            }

            if lower == "intervalst" {
                let repeats = max(1, Int(attributeDict["Repeat"] ?? "1") ?? 1)
                let onDur = Int(attributeDict["OnDuration"] ?? "") ?? 60
                let offDur = Int(attributeDict["OffDuration"] ?? "") ?? 60
                let onPow = Double(attributeDict["OnPower"] ?? "0.95") ?? 0.95
                let offPow = Double(attributeDict["OffPower"] ?? "0.55") ?? 0.55
                let onZone = zoneFromFTPFraction(onPow)
                let offZone = zoneFromFTPFraction(offPow)
                intervals.append(IntervalSegment(
                    order: order,
                    name: "Intervals",
                    durationSeconds: onDur,
                    zone: onZone,
                    repeats: repeats,
                    recoverySeconds: offDur,
                    recoveryZone: offZone,
                    notes: "\(repeats)× efforts",
                    suggestedTrainerMode: .erg
                ))
                order += 1
            }

            if lower == "ramp" {
                let dur = Int(attributeDict["Duration"] ?? "") ?? 600
                let start = Double(attributeDict["PowerLow"] ?? "0.55") ?? 0.55
                let end = Double(attributeDict["PowerHigh"] ?? "0.85") ?? 0.85
                let z = zoneFromFTPFraction((start + end) / 2)
                intervals.append(IntervalSegment(
                    order: order,
                    name: "Ramp",
                    durationSeconds: dur,
                    zone: z,
                    repeats: 1,
                    notes: String(format: "Ramp ~%.0f–%.0f%% FTP", start * 100, end * 100),
                    suggestedTrainerMode: .freeRide
                ))
                order += 1
            }

            if lower == "warmup" || lower == "cooldown" {
                let dur = Int(attributeDict["Duration"] ?? "") ?? 600
                let start = Double(attributeDict["PowerLow"] ?? "0.50") ?? 0.50
                let end = Double(attributeDict["PowerHigh"] ?? "0.75") ?? 0.75
                let z = zoneFromFTPFraction((start + end) / 2)
                let title = lower == "warmup" ? "Warm up" : "Cool down"
                intervals.append(IntervalSegment(
                    order: order,
                    name: title,
                    durationSeconds: dur,
                    zone: z,
                    repeats: 1,
                    notes: String(format: "~%.0f–%.0f%% FTP", start * 100, end * 100),
                    suggestedTrainerMode: .erg
                ))
                order += 1
            }

            if lower == "maxeffort" {
                let dur = Int(attributeDict["Duration"] ?? "") ?? 15
                intervals.append(IntervalSegment(
                    order: order,
                    name: "Max effort",
                    durationSeconds: dur,
                    zone: .z5,
                    repeats: 1,
                    notes: "All-out",
                    suggestedTrainerMode: .erg
                ))
                order += 1
            }

            if lower == "freeride" {
                let dur = Int(attributeDict["Duration"] ?? "") ?? 600
                intervals.append(IntervalSegment(
                    order: order,
                    name: "Free ride",
                    durationSeconds: dur,
                    zone: .z2,
                    repeats: 1,
                    notes: "Self-paced",
                    suggestedTrainerMode: .freeRide
                ))
                order += 1
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            guard stack.last?.lowercased() == "name",
                  stack.contains(where: { $0.lowercased() == "workout" }) else { return }
            workoutName += string.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
            _ = stack.popLast()
        }

        private func zoneFromFTPFraction(_ f: Double) -> TrainingZoneTarget {
            switch f {
            case ..<0.60: return .z1z2
            case ..<0.75: return .z2
            case ..<0.90: return .z3
            case ..<1.05: return .z4
            default: return .z5
            }
        }
    }
}
