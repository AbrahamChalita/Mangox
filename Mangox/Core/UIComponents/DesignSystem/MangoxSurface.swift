import SwiftUI

enum MangoxSurface {
    case frosted
    case frostedInteractive
    case flat
    case flatSubtle
    case mapOverlay
    /// Flat panel with explicit fill and border (hairlines, zone tint, CTAs). Prefer ``flat`` / ``flatSubtle`` when defaults match.
    case flatCustom(fill: Color, border: Color)
    /// Flat fill with a hairline using any ``ShapeStyle`` (e.g. ``LinearGradient`` for coach message shells).
    case flatStyled(fill: Color, border: AnyShapeStyle)
}

enum MangoxSurfaceShape {
    case rounded(CGFloat)
    case capsule
    case circle
    case rectangle
}

private struct MangoxSurfaceInsetShape: InsettableShape {
    let shape: MangoxSurfaceShape

    nonisolated func path(in rect: CGRect) -> Path {
        switch shape {
        case .rounded(let corner):
            RoundedRectangle(cornerRadius: corner, style: .continuous).path(in: rect)
        case .capsule:
            Capsule().path(in: rect)
        case .circle:
            Circle().path(in: rect)
        case .rectangle:
            Rectangle().path(in: rect)
        }
    }

    nonisolated func inset(by amount: CGFloat) -> MangoxSurfaceInsetShape {
        MangoxSurfaceInsetShape(shape: shape)
    }
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
        case .flatCustom(let fill, let border):
            applyFlat(content: content, fill: fill, border: border)
        case .flatStyled(let fill, let border):
            applyFlatStyled(content: content, fill: fill, border: border)
        }
    }

    private func shapeView(_ shape: MangoxSurfaceShape) -> MangoxSurfaceInsetShape {
        MangoxSurfaceInsetShape(shape: shape)
    }

    @ViewBuilder
    private func applyFrosted(content: Content, interactive: Bool) -> some View {
        let borderColor = interactive ? AppColor.mango.opacity(0.35) : AppColor.hair2
        if reduceTransparency {
            applyFlat(content: content, fill: AppColor.bg3, border: borderColor)
        } else {
            let insetShape = shapeView(shape)
            content
                .background(.ultraThinMaterial, in: insetShape)
                .background(AppColor.bg4.opacity(0.72), in: insetShape)
                .overlay(insetShape.strokeBorder(borderColor, lineWidth: 1))
        }
    }

    @ViewBuilder
    private func applyMapOverlay(content: Content) -> some View {
        if reduceTransparency {
            applyFlat(content: content, fill: AppColor.bg2.opacity(0.92), border: AppColor.hair2)
        } else {
            let insetShape = shapeView(shape)
            content
                .background(.ultraThinMaterial, in: insetShape)
                .background(AppColor.bg3.opacity(0.62), in: insetShape)
                .overlay(insetShape.strokeBorder(AppColor.hair2, lineWidth: 1))
        }
    }

    @ViewBuilder
    private func applyFlat(content: Content, fill: Color, border: Color? = nil) -> some View {
        let insetShape = shapeView(shape)
        content
            .background(fill, in: insetShape)
            .overlay {
                if let border {
                    insetShape.strokeBorder(border, lineWidth: 1)
                }
            }
    }

    @ViewBuilder
    private func applyFlatStyled(content: Content, fill: Color, border: AnyShapeStyle) -> some View {
        let insetShape = shapeView(shape)
        content
            .background(fill, in: insetShape)
            .overlay {
                insetShape.strokeBorder(border, lineWidth: 1)
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
