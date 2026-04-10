// App/RideFABView.swift
import SwiftUI

/// Floating action button that morphs between a compact FAB and an expanded ride-selection card.
/// Manages its own expand/collapse state. Calls `onSelect` with the chosen AppRoute so
/// ContentView can navigate without owning any ride-menu UI logic.
struct RideFABView: View {
    let showFloatingButton: Bool
    let onSelect: (AppRoute) -> Void

    @State private var showRideMenu = false
    @Namespace private var glassNamespace

    private static let morphID = "rideGlassFAB"

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Color.clear  // anchors the ZStack to fill the full overlay area
            if showRideMenu {
                Color.black.opacity(0.18)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(MangoxMotion.micro) { showRideMenu = false }
                    }
                    .transition(.opacity)
            }

            if showFloatingButton {
                GlassEffectContainer {
                    if showRideMenu {
                        expandedCard
                    } else {
                        collapsedFAB
                    }
                }
                .padding(.trailing, MangoxSpacing.page)
                .padding(.bottom, 70)
                .transition(.opacity)
            }
        }
        .animation(MangoxMotion.smooth, value: showFloatingButton)
    }

    // MARK: - Collapsed FAB

    private var collapsedFAB: some View {
        Button {
            withAnimation(MangoxMotion.micro) {
                showRideMenu = true
            }
        } label: {
            Image(systemName: "plus")
                .font(.title2.bold())
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .contentShape(Circle())
        }
        .buttonStyle(MangoxPressStyle())
        .glassEffect(.regular.tint(AppColor.mango), in: .circle)
        .glassEffectID(Self.morphID, in: glassNamespace)
        .shadow(color: .black.opacity(0.25), radius: 12, x: 0, y: 6)
    }

    // MARK: - Expanded card

    private var expandedCard: some View {
        menuPanelContent
            .frame(width: 260)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .glassEffectID(Self.morphID, in: glassNamespace)
            .shadow(color: .black.opacity(0.3), radius: 16, x: 0, y: 8)
    }

    private var menuPanelContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            menuRow(
                icon: "figure.indoor.cycle",
                iconColor: AppColor.mango,
                title: "Indoor Ride",
                subtitle: "Smart trainer & power meter",
                route: .indoorRideSetup
            )

            Divider()

            menuRow(
                icon: "bicycle",
                iconColor: AppColor.blue,
                title: "Outdoor Ride",
                subtitle: "GPS, maps & optional sensors",
                route: .outdoorDashboard
            )
        }
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
                    MangoxIconBadge(systemName: icon, color: iconColor, size: 44, cornerRadius: 10)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .mangoxFont(.bodyBold)
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .mangoxFont(.caption)
                        .foregroundStyle(.white.opacity(AppOpacity.textSecondary))
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(MangoxPressStyle())
    }
}
