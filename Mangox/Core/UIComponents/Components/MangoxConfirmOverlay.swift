import SwiftUI

struct MangoxConfirmOverlay<Actions: View>: View {
    let title: String
    let message: String
    let onDismiss: () -> Void
    @ViewBuilder let actions: Actions

    var body: some View {
        ZStack {
            Color.black.opacity(0.52)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)

            VStack(alignment: .leading, spacing: MangoxSpacing.lg.rawValue) {
                Text(title)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)

                Text(message)
                    .mangoxFont(.body)
                    .foregroundStyle(.white.opacity(AppOpacity.textSecondary))
                    .fixedSize(horizontal: false, vertical: true)

                actions
            }
            .padding(MangoxSpacing.xxl.rawValue)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(AppColor.bg)
                    .shadow(color: .black.opacity(0.45), radius: 30, y: 8)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            )
            .padding(.horizontal, MangoxSpacing.xxl.rawValue)
        }
        .allowsHitTesting(true)
    }
}
