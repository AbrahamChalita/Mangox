import SwiftUI

struct DeviceStatusBadge: View {
    let icon: String
    let state: BLEConnectionState
    var fallbackName: String = ""
    /// When true (connected but no packets for >2s), badge turns amber to signal radio silence.
    var isDataStale: Bool = false

    var body: some View {
        HStack(alignment: .center, spacing: 5) {
            Circle()
                .fill(dotColor)
                .frame(width: 5, height: 5)
                .shadow(color: dotColor.opacity(0.6), radius: 3)

            Image(systemName: isDataStale ? "antenna.radiowaves.left.and.right.slash" : icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(dotColor)

            if !displayName.isEmpty {
                Text(isDataStale ? "No signal" : displayName)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(dotColor.opacity(0.95))
                    .lineLimit(1)
                    .frame(maxWidth: 90)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(minHeight: 28)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color.white.opacity(0.06))
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5))
        .animation(.easeInOut(duration: 0.3), value: isDataStale)
    }

    private var displayName: String {
        switch state {
        case .connected(let name), .connecting(let name):
            return name
        case .scanning:
            return "Searching…"
        default:
            return fallbackName
        }
    }

    private var dotColor: Color {
        if isDataStale { return AppColor.orange }
        switch state {
        case .connected:  return AppColor.success
        case .connecting: return AppColor.yellow
        case .scanning:   return AppColor.yellow
        default:          return .white.opacity(0.3)
        }
    }
}
