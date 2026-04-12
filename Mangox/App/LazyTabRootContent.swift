import SwiftUI

// MARK: - Placeholder (first tab activation)

enum LazyTabPlaceholderStyle: Equatable {
    case plain
    case calendar
    case coach
    case stats
    case settings
}

struct LazyTabPlaceholderView: View {
    let style: LazyTabPlaceholderStyle

    var body: some View {
        ZStack {
            AppColor.bg.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                switch style {
                case .plain:
                    Color.clear.frame(height: 1)
                case .calendar:
                    calendarSkeleton
                case .coach:
                    coachSkeleton
                case .stats:
                    statsSkeleton
                case .settings:
                    settingsSkeleton
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var calendarSkeleton: some View {
        VStack(alignment: .leading, spacing: 16) {
            skeletonBar(width: 140, height: 22)
                .padding(.horizontal, 20)
                .padding(.top, 16)
            skeletonBar(width: 220, height: 32)
                .padding(.horizontal, 20)
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 8
            ) {
                ForEach(0..<28, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                        .frame(height: 36)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private var coachSkeleton: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                skeletonBar(width: 90, height: 24)
                Spacer(minLength: 0)
                skeletonBar(width: 72, height: 32)
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            skeletonBar(width: 100, height: 11)
                .padding(.horizontal, 24)
            ForEach(0..<4, id: \.self) { _ in
                skeletonBar(width: nil, height: 68)
                    .padding(.horizontal, 16)
            }
        }
    }

    private var statsSkeleton: some View {
        VStack(alignment: .leading, spacing: 20) {
            skeletonBar(width: 160, height: 22)
                .padding(.horizontal, 20)
                .padding(.top, 12)
            skeletonBar(width: nil, height: 120)
                .padding(.horizontal, 20)
            HStack(spacing: 8) {
                ForEach(0..<4, id: \.self) { _ in
                    skeletonBar(width: nil, height: 32)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private var settingsSkeleton: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Circle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 8) {
                    skeletonBar(width: 140, height: 18)
                    skeletonBar(width: 180, height: 12)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            ForEach(0..<5, id: \.self) { _ in
                skeletonBar(width: nil, height: 48)
                    .padding(.horizontal, 20)
            }
        }
    }

    @ViewBuilder
    private func skeletonBar(width: CGFloat?, height: CGFloat) -> some View {
        if let width {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.08))
                .frame(width: width, height: height)
        } else {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.08))
                .frame(height: height)
                .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Lazy tab root

/// Defers building a tab's root until the user selects it at least once, while keeping
/// `NavigationStack` state in `ContentView` once loaded. Use for secondary tabs only (not Home).
///
/// Performance: defers inserting the heavy view tree until after one main-thread yield so the
/// tab transition can start before SwiftData @Query subscription and layout run.
struct LazyTabRootContent<Content: View>: View {
    let tabIndex: Int
    let selectedTab: Int
    @Binding var loadedTabs: Set<Int>
    var placeholderStyle: LazyTabPlaceholderStyle = .plain
    @ViewBuilder var content: () -> Content

    @State private var renderReady = false

    var body: some View {
        Group {
            if loadedTabs.contains(tabIndex) || renderReady {
                content()
            } else {
                LazyTabPlaceholderView(style: placeholderStyle)
            }
        }
        .onAppear {
            if selectedTab == tabIndex && !loadedTabs.contains(tabIndex) {
                activate()
            }
        }
        .onChange(of: selectedTab) { _, new in
            if new == tabIndex {
                activate()
            }
        }
    }

    private func activate() {
        if loadedTabs.contains(tabIndex) {
            return
        }
        Task { @MainActor in
            await Task.yield()
            loadedTabs.insert(tabIndex)
            renderReady = true
        }
    }
}
