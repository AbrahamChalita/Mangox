import SwiftUI

struct MangoxSectionLabel: View {
    let title: String
    var horizontalPadding: CGFloat = MangoxSpacing.page

    var body: some View {
        Text(title.uppercased())
            .mangoxFont(.label)
            .foregroundStyle(AppColor.fg3)
            .tracking(1.4)
            .padding(.horizontal, horizontalPadding)
    }
}
