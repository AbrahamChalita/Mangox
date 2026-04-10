import SwiftUI

struct MangoxSectionLabel: View {
    let title: String
    var horizontalPadding: CGFloat = MangoxSpacing.page

    var body: some View {
        Text(title.uppercased())
            .mangoxFont(.label)
            .foregroundStyle(.white.opacity(AppOpacity.textTertiary))
            .tracking(1.0)
            .padding(.horizontal, horizontalPadding)
    }
}
