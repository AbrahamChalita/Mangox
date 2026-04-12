// Keep MangoxRideAttributes identical to Mangox/Features/Outdoor/RideLiveActivity/MangoxRideAttributes.swift

import ActivityKit
import SwiftUI
import WidgetKit

// MARK: - Must match main app (byte-for-byte same fields)

struct MangoxRideAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var speedKmh: Double
        var distanceM: Double
        var durationSeconds: Double
        var nextTurnShort: String?
        var heartRateBpm: Int
        var powerWatts: Int
        var cadenceRpm: Double
        var hrZoneId: Int
        var powerZoneId: Int
        var useImperial: Bool
    }

    var rideModeLabel: String

}

// MARK: - Palette (mirrors PowerZone / HeartRateZone ids 1…5)

private enum ZonePalette {
    static func accent(for zoneId: Int) -> Color {
        switch zoneId {
        case 1: return Color(red: 107 / 255, green: 127 / 255, blue: 212 / 255)
        case 2: return Color(red: 79 / 255, green: 195 / 255, blue: 161 / 255)
        case 3: return Color(red: 240 / 255, green: 195 / 255, blue: 78 / 255)
        case 4: return Color(red: 240 / 255, green: 122 / 255, blue: 58 / 255)
        case 5: return Color(red: 232 / 255, green: 68 / 255, blue: 90 / 255)
        default: return Color.white.opacity(0.35)
        }
    }

    /// Dominant accent for header / keyline: prefer HR zone, then power, then mango.
    static func dominantAccent(hr: Int, hrZ: Int, power: Int, powerZ: Int) -> Color {
        if hr > 0, hrZ > 0 { return accent(for: hrZ) }
        if power > 0, powerZ > 0 { return accent(for: powerZ) }
        return Color(red: 255 / 255, green: 186 / 255, blue: 50 / 255)
    }
}

// MARK: - Formatting

private func formatDuration(_ seconds: TimeInterval) -> String {
    let s = max(0, Int(seconds))
    let h = s / 3600
    let m = (s % 3600) / 60
    let sec = s % 60
    if h > 0 {
        return String(format: "%d:%02d:%02d", h, m, sec)
    }
    return String(format: "%d:%02d", m, sec)
}

private func formatDistance(_ m: Double, imperial: Bool) -> String {
    if imperial {
        return String(format: "%.1f mi", m / 1609.344)
    }
    return String(format: "%.2f km", m / 1000)
}

private func displaySpeedInt(_ kmh: Double, imperial: Bool) -> Int {
    if imperial {
        return Int(kmh * 0.621371 + 0.5)
    }
    return Int(kmh + 0.5)
}

private func speedUnitLabel(_ imperial: Bool) -> String {
    imperial ? "mph" : "km/h"
}

// MARK: - Zone strip (5 segments)

private struct ZoneSegmentStrip: View {
    let activeZoneId: Int
    let maxZone: Int

    var body: some View {
        HStack(spacing: 3) {
            ForEach(1...maxZone, id: \.self) { z in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(
                        ZonePalette.accent(for: z).opacity(
                            z <= activeZoneId && activeZoneId > 0 ? 1 : 0.2)
                    )
                    .frame(height: 4)
            }
        }
    }
}

// MARK: - Widget

@main
struct MangoxLiveActivityExtensionBundle: WidgetBundle {
    var body: some Widget {
        MangoxRideLiveActivityWidget()
    }
}

struct MangoxRideLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MangoxRideAttributes.self) { context in
            lockScreenView(context: context)
                .widgetURL(deepLinkURL(for: context.attributes.rideModeLabel))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    expandedLeading(context: context)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    expandedTrailing(context: context)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    expandedBottom(context: context)
                }
            } compactLeading: {
                Image(systemName: "figure.outdoor.cycle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(
                        ZonePalette.dominantAccent(
                            hr: context.state.heartRateBpm,
                            hrZ: context.state.hrZoneId,
                            power: context.state.powerWatts,
                            powerZ: context.state.powerZoneId
                        ))
            } compactTrailing: {
                compactTrailingContent(context: context)
            } minimal: {
                if context.state.heartRateBpm > 0 {
                    Image(systemName: "heart.fill")
                        .font(.caption2)
                        .foregroundStyle(ZonePalette.accent(for: max(1, context.state.hrZoneId)))
                } else if context.state.powerWatts > 0 {
                    Image(systemName: "bolt.fill")
                        .font(.caption2)
                        .foregroundStyle(ZonePalette.accent(for: max(1, context.state.powerZoneId)))
                } else {
                    Image(systemName: "bicycle")
                        .font(.caption2)
                }
            }
            .widgetURL(deepLinkURL(for: context.attributes.rideModeLabel))
        }
    }
}

private func deepLinkURL(for rideModeLabel: String) -> URL {
    rideModeLabel == "Indoor"
        ? URL(string: "mangox://ride/indoor/live")!
        : URL(string: "mangox://ride/outdoor/live")!
}

// MARK: - Lock screen

private func lockScreenView(context: ActivityViewContext<MangoxRideAttributes>) -> some View {
    let s = context.state
    let accent = ZonePalette.dominantAccent(
        hr: s.heartRateBpm, hrZ: s.hrZoneId, power: s.powerWatts, powerZ: s.powerZoneId)
    let activeZ = max(s.hrZoneId, s.powerZoneId)

    return VStack(alignment: .leading, spacing: 10) {
        HStack(alignment: .center) {
            Text(context.attributes.rideModeLabel.uppercased())
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(.secondary)
                .tracking(0.8)
            Spacer()
            if activeZ > 0 {
                ZoneSegmentStrip(activeZoneId: activeZ, maxZone: 5)
                    .frame(width: 72)
            }
        }

        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("\(displaySpeedInt(s.speedKmh, imperial: s.useImperial))")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .contentTransition(.numericText())
            Text(speedUnitLabel(s.useImperial))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            sensorChips(state: s)
        }

        HStack(spacing: 12) {
            Label {
                Text(formatDistance(s.distanceM, imperial: s.useImperial))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .contentTransition(.numericText())
            } icon: {
                Image(systemName: "location.north.line.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accent.opacity(0.9))
            }
            Text("·")
                .foregroundStyle(.tertiary)
            Text(formatDuration(s.durationSeconds))
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
        }

        if let t = s.nextTurnShort, !t.isEmpty {
            Text(t)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .padding(.top, 2)
        }
    }
    .padding(14)
    .activityBackgroundTint(Color.black.opacity(0.42))
    .overlay(alignment: .leading) {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [accent, accent.opacity(0.4)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: 4)
    }
}

@ViewBuilder
private func sensorChips(state: MangoxRideAttributes.ContentState) -> some View {
    HStack(spacing: 8) {
        if state.heartRateBpm > 0 {
            HStack(spacing: 4) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ZonePalette.accent(for: max(1, state.hrZoneId)))
                Text("\(state.heartRateBpm)")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                if state.hrZoneId > 0 {
                    Text("Z\(state.hrZoneId)")
                        .font(.system(size: 10, weight: .heavy))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(ZonePalette.accent(for: state.hrZoneId).opacity(0.22))
                        .clipShape(Capsule())
                }
            }
        }
        if state.powerWatts > 0 {
            HStack(spacing: 4) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ZonePalette.accent(for: max(1, state.powerZoneId)))
                Text("\(state.powerWatts)")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                Text("W")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                if state.powerZoneId > 0 {
                    Text("Z\(state.powerZoneId)")
                        .font(.system(size: 10, weight: .heavy))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(ZonePalette.accent(for: state.powerZoneId).opacity(0.22))
                        .clipShape(Capsule())
                }
            }
        }
        if state.cadenceRpm > 0 {
            HStack(spacing: 4) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("\(Int(state.cadenceRpm))")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                Text("rpm")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Dynamic Island expanded

private func expandedLeading(context: ActivityViewContext<MangoxRideAttributes>) -> some View {
    let s = context.state
    return VStack(alignment: .leading, spacing: 2) {
        Text("\(displaySpeedInt(s.speedKmh, imperial: s.useImperial))")
            .font(.system(size: 28, weight: .bold, design: .rounded))
            .contentTransition(.numericText())
        Text(speedUnitLabel(s.useImperial))
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}

private func expandedTrailing(context: ActivityViewContext<MangoxRideAttributes>) -> some View {
    let s = context.state
    return VStack(alignment: .trailing, spacing: 6) {
        if s.heartRateBpm > 0 {
            HStack(spacing: 4) {
                Image(systemName: "heart.fill")
                    .foregroundStyle(ZonePalette.accent(for: max(1, s.hrZoneId)))
                Text("\(s.heartRateBpm) bpm")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
            }
            if s.hrZoneId > 0 {
                ZoneSegmentStrip(activeZoneId: s.hrZoneId, maxZone: 5)
                    .frame(width: 88)
            }
        }
        if s.powerWatts > 0 {
            HStack(spacing: 4) {
                Image(systemName: "bolt.fill")
                    .foregroundStyle(ZonePalette.accent(for: max(1, s.powerZoneId)))
                Text("\(s.powerWatts) W")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
            }
            if s.powerZoneId > 0, s.heartRateBpm <= 0 {
                ZoneSegmentStrip(activeZoneId: s.powerZoneId, maxZone: 5)
                    .frame(width: 88)
            }
        }
    }
}

private func expandedBottom(context: ActivityViewContext<MangoxRideAttributes>) -> some View {
    let s = context.state
    return VStack(alignment: .leading, spacing: 4) {
        HStack {
            Text(formatDistance(s.distanceM, imperial: s.useImperial))
                .contentTransition(.numericText())
            Text("·")
                .foregroundStyle(.tertiary)
            Text(formatDuration(s.durationSeconds))
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .contentTransition(.numericText())
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
        if let t = s.nextTurnShort, !t.isEmpty {
            Text(t)
                .font(.caption.weight(.medium))
                .lineLimit(2)
        }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
}

@ViewBuilder
private func compactTrailingContent(context: ActivityViewContext<MangoxRideAttributes>) -> some View
{
    let s = context.state
    if s.heartRateBpm > 0 {
        Text("\(s.heartRateBpm)")
            .font(.caption2.weight(.bold))
            .foregroundStyle(ZonePalette.accent(for: max(1, s.hrZoneId)))
            .contentTransition(.numericText())
    } else if s.powerWatts > 0 {
        Text("\(s.powerWatts)")
            .font(.caption2.weight(.bold))
            .foregroundStyle(ZonePalette.accent(for: max(1, s.powerZoneId)))
            .contentTransition(.numericText())
    } else {
        Text("\(displaySpeedInt(s.speedKmh, imperial: s.useImperial))")
            .font(.caption2.weight(.semibold))
            .contentTransition(.numericText())
    }
}
