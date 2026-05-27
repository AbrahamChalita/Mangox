import SwiftUI

/// Reusable error banner with severity levels.
struct MangoxErrorBanner: View {
    enum Severity {
        case info, warning, error

        var icon: String {
            switch self {
            case .info: "info.circle.fill"
            case .warning: "exclamationmark.triangle.fill"
            case .error: "xmark.circle.fill"
            }
        }

        var tint: Color {
            switch self {
            case .info: AppColor.blue
            case .warning: AppColor.yellow
            case .error: AppColor.red
            }
        }

        func accessibilityLabel(for message: String) -> String {
            switch self {
            case .info: A11yL10n.infoFormat(message)
            case .warning: A11yL10n.warningFormat(message)
            case .error: A11yL10n.errorFormat(message)
            }
        }
    }

    enum Layout {
        case card
        case inlineStrip
    }

    let message: String
    var severity: Severity = .error
    var layout: Layout = .card
    var onDismiss: (() -> Void)?

    var body: some View {
        switch layout {
        case .card:
            cardBody
        case .inlineStrip:
            inlineStripBody
        }
    }

    private var cardBody: some View {
        HStack(spacing: 10) {
            Image(systemName: severity.icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(severity.tint)

            Text(message)
                .font(MangoxFont.caption.value)
                .foregroundStyle(AppColor.fg1)
                .lineLimit(3)

            Spacer(minLength: 4)

            dismissButton(foreground: AppColor.fg3)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(severity.tint.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: MangoxRadius.overlay.rawValue))
        .overlay(
            RoundedRectangle(cornerRadius: MangoxRadius.overlay.rawValue)
                .strokeBorder(severity.tint.opacity(0.2), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(severity.accessibilityLabel(for: message))
    }

    private var inlineStripBody: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: severity.icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(severity.tint.opacity(0.85))
                .padding(.top, 1)

            Text(message)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.78))
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            dismissButton(foreground: .white.opacity(0.55))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(severity.tint.opacity(0.10))
        .overlay(alignment: .top) { Divider().opacity(0.18) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(severity.accessibilityLabel(for: message))
    }

    @ViewBuilder
    private func dismissButton(foreground: Color) -> some View {
        if let onDismiss {
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(foreground)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(A11yL10n.dismissError)
        }
    }
}

// MARK: - View Modifier

private struct MangoxErrorModifier: ViewModifier {
    let error: String?
    let severity: MangoxErrorBanner.Severity
    let layout: MangoxErrorBanner.Layout
    let onDismiss: (() -> Void)?

    func body(content: Content) -> some View {
        VStack(spacing: 0) {
            if let error, !error.isEmpty {
                MangoxErrorBanner(
                    message: error,
                    severity: severity,
                    layout: layout,
                    onDismiss: onDismiss
                )
                .padding(.horizontal, layout == .card ? 16 : 0)
                .padding(.bottom, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            content
        }
        .animation(MangoxMotion.standard, value: error)
    }
}

extension View {
    /// Shows an error banner above the content when `error` is non-nil.
    func mangoxError(
        _ error: String?,
        severity: MangoxErrorBanner.Severity = .error,
        layout: MangoxErrorBanner.Layout = .card,
        onDismiss: (() -> Void)? = nil
    ) -> some View {
        modifier(MangoxErrorModifier(error: error, severity: severity, layout: layout, onDismiss: onDismiss))
    }
}
