import SwiftUI

struct LapCardView: View {
    let lapNumber: Int
    let currentAvgPower: Double
    let currentDuration: TimeInterval
    let previousAvgPower: Double
    let previousDuration: TimeInterval
    var compact: Bool = false

    var body: some View {
        if compact {
            compactBody
        } else {
            fullBody
        }
    }

    private var fullBody: some View {
        VStack(spacing: 8) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "flag.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Color(red: 107/255, green: 127/255, blue: 212/255))
                    Text("LAP \(lapNumber)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white.opacity(0.6))
                        .tracking(1)
                }
                Spacer()
            }

            HStack(spacing: 16) {
                // Current lap
                VStack(alignment: .leading, spacing: 3) {
                    Text("CURRENT")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.25))
                        .tracking(1)
                    HStack(spacing: 8) {
                        Text("\(Int(currentAvgPower))W")
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                            .foregroundStyle(PowerZone.zone(for: Int(currentAvgPower)).color)
                        Text(formatDuration(currentDuration))
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }

                if lapNumber > 1 {
                    Rectangle()
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 1, height: 30)

                    // Previous lap
                    VStack(alignment: .leading, spacing: 3) {
                        Text("PREVIOUS")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white.opacity(0.25))
                            .tracking(1)
                        HStack(spacing: 8) {
                            Text("\(Int(previousAvgPower))W")
                                .font(.system(size: 16, weight: .bold, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.5))
                            Text(formatDuration(previousDuration))
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.3))
                        }
                    }
                }

                Spacer()
            }
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
    }

    private var compactBody: some View {
        HStack(spacing: 10) {
            Image(systemName: "flag.fill")
                .font(.system(size: 10))
                .foregroundStyle(Color(red: 107/255, green: 127/255, blue: 212/255))
            Text("LAP \(lapNumber)")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white.opacity(0.55))
                .tracking(0.5)
            Text("\(Int(currentAvgPower))W")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(PowerZone.zone(for: Int(currentAvgPower)).color)
            Text(formatDuration(currentDuration))
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.white.opacity(0.45))
            if lapNumber > 1 {
                Text("·")
                    .foregroundStyle(.white.opacity(0.25))
                Text("\(Int(previousAvgPower))W")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.45))
                Text(formatDuration(previousDuration))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.32))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: .rect(cornerRadius: 10))
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}
