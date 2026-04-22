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
            applyFlat(content: content, fill: AppColor.bg2, border: AppColor.hair2)
        case .flatSubtle:
            applyFlat(content: content, fill: AppColor.bg1, border: AppColor.hair)
        case .mapOverlay:
            applyMapOverlay(content: content)
        }
    }

    @ViewBuilder
    private func applyFrosted(content: Content, interactive: Bool) -> some View {
        if reduceTransparency {
            applyFlat(content: content, fill: AppColor.bg3, border: interactive ? AppColor.mango.opacity(0.35) : AppColor.hair2)
        } else {
            switch shape {
            case .rounded(let corner):
                content
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: corner, style: .continuous))
                    .background(AppColor.bg4.opacity(0.72), in: RoundedRectangle(cornerRadius: corner, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: corner, style: .continuous)
                            .strokeBorder(interactive ? AppColor.mango.opacity(0.35) : AppColor.hair2, lineWidth: 1)
                    )
            case .capsule:
                content
                    .background(.ultraThinMaterial, in: Capsule())
                    .background(AppColor.bg4.opacity(0.72), in: Capsule())
                    .overlay(
                        Capsule().strokeBorder(interactive ? AppColor.mango.opacity(0.35) : AppColor.hair2, lineWidth: 1)
                    )
            case .circle:
                content
                    .background(.ultraThinMaterial, in: Circle())
                    .background(AppColor.bg4.opacity(0.72), in: Circle())
                    .overlay(
                        Circle().strokeBorder(interactive ? AppColor.mango.opacity(0.35) : AppColor.hair2, lineWidth: 1)
                    )
            case .rectangle:
                content
                    .background(.ultraThinMaterial)
                    .background(AppColor.bg4.opacity(0.72))
                    .overlay(Rectangle().strokeBorder(interactive ? AppColor.mango.opacity(0.35) : AppColor.hair2, lineWidth: 1))
            }
        }
    }

    @ViewBuilder
    private func applyMapOverlay(content: Content) -> some View {
        if reduceTransparency {
            applyFlat(content: content, fill: AppColor.bg2.opacity(0.92), border: AppColor.hair2)
        } else {
            switch shape {
            case .rounded(let corner):
                content
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: corner, style: .continuous))
                    .background(AppColor.bg3.opacity(0.62), in: RoundedRectangle(cornerRadius: corner, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: corner, style: .continuous)
                            .strokeBorder(AppColor.hair2, lineWidth: 1)
                    )
            case .capsule:
                content
                    .background(.ultraThinMaterial, in: Capsule())
                    .background(AppColor.bg3.opacity(0.62), in: Capsule())
                    .overlay(Capsule().strokeBorder(AppColor.hair2, lineWidth: 1))
            case .circle:
                content
                    .background(.ultraThinMaterial, in: Circle())
                    .background(AppColor.bg3.opacity(0.62), in: Circle())
                    .overlay(Circle().strokeBorder(AppColor.hair2, lineWidth: 1))
            case .rectangle:
                content
                    .background(.ultraThinMaterial)
                    .background(AppColor.bg3.opacity(0.62))
                    .overlay(Rectangle().strokeBorder(AppColor.hair2, lineWidth: 1))
            }
        }
    }

    @ViewBuilder
    private func applyFlat(content: Content, fill: Color, border: Color? = nil) -> some View {
        switch shape {
        case .rounded(let corner):
            content
                .background(fill, in: RoundedRectangle(cornerRadius: corner, style: .continuous))
                .overlay {
                    if let border {
                        RoundedRectangle(cornerRadius: corner, style: .continuous)
                            .strokeBorder(border, lineWidth: 1)
                    }
                }
        case .capsule:
            content
                .background(fill, in: Capsule())
                .overlay {
                    if let border {
                        Capsule().strokeBorder(border, lineWidth: 1)
                    }
                }
        case .circle:
            content
                .background(fill, in: Circle())
                .overlay {
                    if let border {
                        Circle().strokeBorder(border, lineWidth: 1)
                    }
                }
        case .rectangle:
            content
                .background(fill)
                .overlay {
                    if let border {
                        Rectangle().strokeBorder(border, lineWidth: 1)
                    }
                }
        }
    }
}

extension View {
    func mangoxSurface(
        _ surface: MangoxSurface,
        shape: MangoxSurfaceShape = .rounded(MangoxRadius.card.rawValue)
    ) -> some View {
        modifier(MangoxSurfaceModifier(surface: surface, shape: shape))
    }
}
