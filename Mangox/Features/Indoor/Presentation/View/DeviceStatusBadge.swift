import SwiftUI

struct DeviceStatusBadge: View {
    let icon: String
    let state: BLEConnectionState
    var fallbackName: String = ""
    /// When true (connected but no packets for >2s), badge turns amber to signal radio silence.
    var isDataStale: Bool = false
    /// Icon + link lamp only — for dense headers; full device name is exposed via accessibility.
    var iconOnly: Bool = false
    /// Dot + icon only — no capsule chrome (unified indoor header).
    var bare: Bool = false

    var body: some View {
        HStack(alignment: .center, spacing: bare ? 3 : (iconOnly ? 4 : 5)) {
            Circle()
                .fill(dotColor)
                .frame(width: bare ? 4 : (iconOnly ? 4 : 5), height: bare ? 4 : (iconOnly ? 4 : 5))
                .shadow(color: bare ? .clear : dotColor.opacity(0.6), radius: bare ? 0 : 3)

            Image(systemName: isDataStale ? "antenna.radiowaves.left.and.right.slash" : icon)
                .mangoxFont(bare ? .micro : (iconOnly ? .micro : .label))
                .fontWeight(.semibold)
                .foregroundStyle(dotColor)

            if !iconOnly, !bare, !displayName.isEmpty {
                Text(isDataStale ? "No signal" : displayName)
                    .mangoxFont(.label)
                    .foregroundStyle(dotColor.opacity(0.95))
                    .lineLimit(1)
                    .frame(maxWidth: 90)
            }
        }
        .padding(.horizontal, bare ? 0 : (iconOnly ? 6 : 8))
        .padding(.vertical, bare ? 0 : (iconOnly ? 4 : 5))
        .frame(minHeight: bare ? 22 : (iconOnly ? 26 : 28))
        .fixedSize(horizontal: false, vertical: true)
        .background(bare ? Color.clear : AppColor.hair)
        .clipShape(Capsule())
        .overlay {
            if !bare {
                Capsule().strokeBorder(AppColor.hair2, lineWidth: 0.5)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: isDataStale)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityTitle)
    }

    private var accessibilityTitle: String {
        let label: String = {
            if !displayName.isEmpty, displayName != fallbackName {
                return "\(fallbackName) \(displayName)"
            }
            if !displayName.isEmpty { return displayName }
            return fallbackName
        }()
        if isDataStale {
            return "\(label). \(String(localized: "indoor.link.no_recent_data"))"
        }
        return "\(label). \(state.label)"
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
        default:          return AppColor.fg3
        }
    }
}
