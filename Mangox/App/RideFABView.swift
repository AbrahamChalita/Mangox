// App/RideFABView.swift
import SwiftUI

/// Floating action button that morphs between a compact FAB and an expanded ride-selection card.
/// Manages its own expand/collapse state. Calls `onSelect` with the chosen AppRoute so
/// ContentView can navigate without owning any ride-menu UI logic.
struct RideFABView: View {
    let showFloatingButton: Bool
    let onSelect: (AppRoute) -> Void

    @State private var showRideMenu = false
    @Namespace private var fabNamespace

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Color.clear  // anchors the ZStack to fill the full overlay area
            if showRideMenu {
                AppColor.bg0.opacity(0.34)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(MangoxMotion.micro) { showRideMenu = false }
                    }
                    .transition(.opacity)
            }

            if showFloatingButton || showRideMenu {
                floatingMenu
                .padding(.trailing, MangoxSpacing.page)
                .padding(.bottom, 70)
            }
        }
        .onChange(of: showFloatingButton) { _, isVisible in
            guard !isVisible, showRideMenu else { return }
            showRideMenu = false
        }
        .animation(MangoxMotion.expansive, value: showRideMenu)
        .animation(MangoxMotion.smooth, value: showFloatingButton)
    }

    private var floatingMenu: some View {
        ZStack(alignment: .bottomTrailing) {
            if showRideMenu {
                expandedCard
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.94, anchor: .bottomTrailing)
                                .combined(with: .opacity),
                            removal: .scale(scale: 0.98, anchor: .bottomTrailing)
                                .combined(with: .opacity)
                        )
                    )
            }

            if !showRideMenu {
                collapsedFAB
                    .transition(
                        .scale(scale: 0.9, anchor: .bottomTrailing)
                            .combined(with: .opacity)
                    )
            }
        }
    }

    // MARK: - Collapsed FAB

    private var collapsedFAB: some View {
        fabToggleButton(isExpanded: false) {
            withAnimation(MangoxMotion.micro) {
                showRideMenu = true
            }
        }
    }

    // MARK: - Expanded card

    private var expandedCard: some View {
        menuPanelContent
            .frame(width: 260)
            .background(
                RoundedRectangle(cornerRadius: MangoxRadius.overlay.rawValue, style: .continuous)
                    .fill(AppColor.bg2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: MangoxRadius.overlay.rawValue, style: .continuous)
                    .strokeBorder(AppColor.hair2, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.35), radius: 16, x: 0, y: 8)
    }

    private var menuPanelContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: MangoxSpacing.md.rawValue) {
                Text("Start Ride")
                    .mangoxFont(.bodyBold)
                    .foregroundStyle(AppColor.fg0)

                Spacer(minLength: 0)

                fabToggleButton(isExpanded: true) {
                    withAnimation(MangoxMotion.micro) {
                        showRideMenu = false
                    }
                }
            }
            .padding(.horizontal, MangoxSpacing.lg.rawValue)
            .padding(.top, MangoxSpacing.lg.rawValue)
            .padding(.bottom, MangoxSpacing.md.rawValue)

            Rectangle()
                .fill(AppColor.hair)
                .frame(height: 1)

            menuRow(
                icon: "figure.indoor.cycle",
                iconColor: AppColor.mango,
                title: "Indoor Ride",
                subtitle: "Smart trainer & power meter",
                route: .indoorRideSetup
            )

            Rectangle()
                .fill(AppColor.hair)
                .frame(height: 1)

            menuRow(
                icon: "bicycle",
                iconColor: AppColor.blue,
                title: "Outdoor Ride",
                subtitle: "GPS, maps & optional sensors",
                route: .outdoorDashboard
            )
        }
    }

    private func fabToggleButton(isExpanded: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(
                    cornerRadius: MangoxRadius.button.rawValue,
                    style: .continuous
                )
                .fill(AppColor.mango)
                .matchedGeometryEffect(id: "ride-fab.chrome", in: fabNamespace)

                RoundedRectangle(
                    cornerRadius: MangoxRadius.button.rawValue,
                    style: .continuous
                )
                .strokeBorder(AppColor.mango.opacity(0.45), lineWidth: 1)
                .matchedGeometryEffect(id: "ride-fab.stroke", in: fabNamespace)

                Image(systemName: "plus")
                    .font(.title2.bold())
                    .foregroundStyle(AppColor.bg0)
                    .rotationEffect(.degrees(isExpanded ? 45 : 0))
                    .matchedGeometryEffect(id: "ride-fab.icon", in: fabNamespace)
            }
            .frame(width: 52, height: 52)
            .contentShape(
                RoundedRectangle(
                    cornerRadius: MangoxRadius.button.rawValue,
                    style: .continuous
                )
            )
        }
        .buttonStyle(MangoxPressStyle())
        .shadow(color: .black.opacity(0.35), radius: isExpanded ? 8 : 10, x: 0, y: isExpanded ? 4 : 6)
        .accessibilityLabel(isExpanded ? "Close ride options" : "Start a ride")
    }

    private func menuRow(
        icon: String,
        iconColor: Color,
        title: String,
        subtitle: String,
        route: AppRoute
    ) -> some View {
        Button {
            withAnimation(MangoxMotion.smooth) { showRideMenu = false }
            onSelect(route)
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    MangoxIconBadge(
                        systemName: icon,
                        color: iconColor,
                        size: 44,
                        cornerRadius: MangoxRadius.button.rawValue
                    )
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .mangoxFont(.bodyBold)
                        .foregroundStyle(AppColor.fg0)
                    Text(subtitle)
                        .mangoxFont(.caption)
                        .foregroundStyle(AppColor.fg2)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, MangoxSpacing.lg.rawValue)
            .padding(.vertical, MangoxSpacing.lg.rawValue)
            .contentShape(Rectangle())
        }
        .buttonStyle(MangoxPressStyle())
    }
}
