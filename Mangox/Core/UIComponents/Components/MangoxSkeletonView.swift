import SwiftUI

/// Animated shimmer skeleton for loading states.
struct MangoxSkeletonView: View {
    var width: CGFloat? = nil
    var height: CGFloat = 12
    var cornerRadius: CGFloat = MangoxRadius.badge.rawValue

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @State private var phase: CGFloat = -1

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    stops: [
                        .init(color: AppColor.bg3, location: 0),
                        .init(color: AppColor.bg4, location: 0.4),
                        .init(color: AppColor.bg3, location: 0.8),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .overlay(
                GeometryReader { geo in
                    LinearGradient(
                        stops: [
                            .init(color: Color.white.opacity(0), location: 0),
                            .init(color: Color.white.opacity(0.06), location: 0.5),
                            .init(color: Color.white.opacity(0), location: 1),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .offset(x: phase * geo.size.width)
                    .frame(width: geo.size.width * 0.6)
                }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            )
            .frame(width: width, height: height)
            .onAppear {
                if accessibilityReduceMotion {
                    phase = 2
                } else {
                    withAnimation(MangoxMotion.banner.repeatForever(autoreverses: false)) {
                        phase = 2
                    }
                }
            }
            .accessibilityHidden(true)
    }
}

// MARK: - Convenience Skeleton Layouts

struct MangoxMetricCardSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            MangoxSkeletonView(width: 60, height: 8)
            MangoxSkeletonView(width: 80, height: 20)
            MangoxSkeletonView(width: 50, height: 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(MangoxSpacing.lg.rawValue)
        .mangoxSurface(.flat, shape: .rounded(MangoxRadius.card.rawValue))
    }
}

struct MangoxChatBubbleSkeleton: View {
    let isUser: Bool

    var body: some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
            MangoxSkeletonView(height: 14)
                .frame(maxWidth: 220)
            MangoxSkeletonView(height: 14)
                .frame(maxWidth: 160)
            MangoxSkeletonView(height: 14)
                .frame(maxWidth: 180)
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

struct MangoxListRowSkeleton: View {
    var body: some View {
        HStack(spacing: 12) {
            MangoxSkeletonView(width: 4, height: 36)
                .clipShape(Capsule())
            VStack(alignment: .leading, spacing: 6) {
                MangoxSkeletonView(height: 12)
                    .frame(maxWidth: 120)
                MangoxSkeletonView(height: 10)
                    .frame(maxWidth: 80)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                MangoxSkeletonView(height: 12)
                    .frame(maxWidth: 50)
                MangoxSkeletonView(height: 10)
                    .frame(maxWidth: 40)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

// MARK: - View Modifiers

private struct MangoxLoadingModifier: ViewModifier {
    let isLoading: Bool

    func body(content: Content) -> some View {
        if isLoading {
            content
                .redacted(reason: .placeholder)
                .allowsHitTesting(false)
        } else {
            content
        }
    }
}

private struct MangoxSkeletonLoadingModifier<Skeleton: View>: ViewModifier {
    let isLoading: Bool
    @ViewBuilder let skeleton: () -> Skeleton

    func body(content: Content) -> some View {
        if isLoading {
            skeleton()
                .allowsHitTesting(false)
                .transition(.opacity)
        } else {
            content
                .transition(.opacity)
        }
    }
}

extension View {
    /// Redacts content as a placeholder while loading.
    func mangoxLoading(_ isLoading: Bool) -> some View {
        modifier(MangoxLoadingModifier(isLoading: isLoading))
    }

    /// Swaps content for a custom skeleton layout while loading.
    func mangoxLoading<S: View>(
        _ isLoading: Bool,
        @ViewBuilder skeleton: @escaping () -> S
    ) -> some View {
        modifier(MangoxSkeletonLoadingModifier(isLoading: isLoading, skeleton: skeleton))
    }
}
