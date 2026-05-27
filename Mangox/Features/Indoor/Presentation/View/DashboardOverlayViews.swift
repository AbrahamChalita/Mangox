// Features/Indoor/Presentation/View/DashboardOverlayViews.swift
import SwiftUI

// MARK: - Screen Lock Overlay

struct ScreenLockOverlay: View {
    @Binding var isScreenLocked: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.7)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 48, weight: .medium))
                    .foregroundStyle(AppColor.fg2)

                Text("Screen Locked")
                    .mangoxFont(.title)
                    .fontWeight(.bold)
                    .foregroundStyle(AppColor.fg0)

                Text("Tap and hold to unlock")
                    .mangoxFont(.callout)
                    .foregroundStyle(AppColor.fg3)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 0)
                .fill(Color.clear)
                .contentShape(Rectangle())
                .gesture(
                    LongPressGesture(minimumDuration: 0.5)
                        .onEnded { _ in
                            withAnimation(MangoxMotion.micro) {
                                isScreenLocked = false
                            }
                        }
                )
        )
        .allowsHitTesting(true)
    }
}

// MARK: - Ride Tips Onboarding Overlay

struct RideTipsOnboardingOverlay: View {
    let onDecline: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        MangoxConfirmOverlay(
            title: "Try Smart Ride Tips?",
            message:
                "Get occasional fueling, cadence, and posture nudges for long indoor rides. You can change this anytime in Settings.",
            onDismiss: onDecline
        ) {
            MangoxConfirmDualButtonRow(
                cancelTitle: "Not now",
                confirmTitle: "Enable Essentials",
                trailingStyle: .hero,
                onCancel: onDecline,
                onConfirm: onConfirm
            )
        }
    }
}

// MARK: - Indoor End Workout Overlay

struct IndoorEndWorkoutOverlay: View {
    let onDismiss: () -> Void
    let onEndAndSave: () -> Void
    let onDiscard: () -> Void

    var body: some View {
        MangoxConfirmOverlay(
            title: "End workout?",
            message:
                "We’ll open the summary next so you can review power, heart rate, and time — or discard this session with no save.",
            onDismiss: onDismiss
        ) {
            MangoxConfirmDualButtonRow(
                cancelTitle: "Cancel",
                confirmTitle: "End & Save",
                trailingStyle: .hero,
                onCancel: onDismiss,
                onConfirm: onEndAndSave
            )

            Button {
                onDiscard()
            } label: {
                Text("Discard without saving")
                    .mangoxFont(.bodyBold)
                    .mangoxButtonChrome(.destructive)
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Persistence Error Overlay

struct PersistenceErrorOverlay: View {
    let message: String
    @Binding var errorMessage: String?

    var body: some View {
        MangoxConfirmOverlay(
            title: "Save Failed",
            message: message,
            onDismiss: { errorMessage = nil }
        ) {
            Button {
                errorMessage = nil
            } label: {
                Text("OK")
                    .mangoxButtonChrome(.hero)
            }
            .buttonStyle(.plain)
        }
    }
}
