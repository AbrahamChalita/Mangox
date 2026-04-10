import SwiftUI

enum MangoxSurface {
    case frosted
    case frostedInteractive
    case flat
    case flatSubtle
    case mapOverlay
}

enum MangoxSurfaceShape {
    case rounded(CGFloat)
    case capsule
    case circle
    case rectangle
}

private struct MangoxSurfaceModifier: ViewModifier {
    let surface: MangoxSurface
    let shape: MangoxSurfaceShape

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        switch surface {
        case .frosted:
            applyFrosted(content: content, interactive: false)
        case .frostedInteractive:
            applyFrosted(content: content, interactive: true)
        case .flat:
            applyFlat(content: content, opacity: AppOpacity.cardBg, borderOpacity: AppOpacity.cardBorder)
        case .flatSubtle:
            applyFlat(content: content, opacity: AppOpacity.pillBg, borderOpacity: 0)
        case .mapOverlay:
            applyMapOverlay(content: content)
        }
    }

    @ViewBuilder
    private func applyFrosted(content: Content, interactive: Bool) -> some View {
        if reduceTransparency {
            applyOpaque(content: content, bgOpacity: 0.12, borderOpacity: 0.12)
        } else {
            switch shape {
            case .rounded(let corner):
                if interactive {
                    content.glassEffect(.regular.interactive(), in: .rect(cornerRadius: corner, style: .continuous))
                } else {
                    content.glassEffect(.regular, in: .rect(cornerRadius: corner, style: .continuous))
                }
            case .capsule:
                if interactive {
                    content.glassEffect(.regular.interactive(), in: .capsule)
                } else {
                    content.glassEffect(.regular, in: .capsule)
                }
            case .circle:
                if interactive {
                    content.glassEffect(.regular.interactive(), in: .circle)
                } else {
                    content.glassEffect(.regular, in: .circle)
                }
            case .rectangle:
                if interactive {
                    content.glassEffect(.regular.interactive(), in: .rect(cornerRadius: 0, style: .continuous))
                } else {
                    content.glassEffect(.regular, in: .rect(cornerRadius: 0, style: .continuous))
                }
            }
        }
    }

    @ViewBuilder
    private func applyMapOverlay(content: Content) -> some View {
        if reduceTransparency {
            applyOpaque(content: content, bgOpacity: 0.1, borderOpacity: 0.08)
        } else {
            switch shape {
            case .rounded(let corner):
                content
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: corner, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: corner, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                    )
            case .capsule:
                content
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                    )
            case .circle:
                content
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(
                        Circle()
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                    )
            case .rectangle:
                content
                    .background(.ultraThinMaterial)
            }
        }
    }

    @ViewBuilder
    private func applyFlat(content: Content, opacity: Double, borderOpacity: Double) -> some View {
        switch shape {
        case .rounded(let corner):
            content
                .background(Color.white.opacity(opacity))
                .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
                .overlay {
                    if borderOpacity > 0 {
                        RoundedRectangle(cornerRadius: corner, style: .continuous)
                            .strokeBorder(Color.white.opacity(borderOpacity), lineWidth: 1)
                    }
                }
        case .capsule:
            content
                .background(Color.white.opacity(opacity), in: Capsule())
                .overlay {
                    if borderOpacity > 0 {
                        Capsule().strokeBorder(Color.white.opacity(borderOpacity), lineWidth: 1)
                    }
                }
        case .circle:
            content
                .background(Color.white.opacity(opacity), in: Circle())
                .overlay {
                    if borderOpacity > 0 {
                        Circle().strokeBorder(Color.white.opacity(borderOpacity), lineWidth: 1)
                    }
                }
        case .rectangle:
            content.background(Color.white.opacity(opacity))
        }
    }

    @ViewBuilder
    private func applyOpaque(content: Content, bgOpacity: Double, borderOpacity: Double) -> some View {
        switch shape {
        case .rounded(let corner):
            content
                .background(Color.white.opacity(bgOpacity))
                .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .strokeBorder(Color.white.opacity(borderOpacity), lineWidth: 1)
                }
        case .capsule:
            content
                .background(Color.white.opacity(bgOpacity), in: Capsule())
                .overlay {
                    Capsule().strokeBorder(Color.white.opacity(borderOpacity), lineWidth: 1)
                }
        case .circle:
            content
                .background(Color.white.opacity(bgOpacity), in: Circle())
                .overlay {
                    Circle().strokeBorder(Color.white.opacity(borderOpacity), lineWidth: 1)
                }
        case .rectangle:
            content
                .background(Color.white.opacity(bgOpacity))
                .overlay(Rectangle().strokeBorder(Color.white.opacity(borderOpacity), lineWidth: 1))
        }
    }
}

extension View {
    func mangoxSurface(_ surface: MangoxSurface, shape: MangoxSurfaceShape = .rounded(MangoxRadius.card.rawValue)) -> some View {
        modifier(MangoxSurfaceModifier(surface: surface, shape: shape))
    }
}
