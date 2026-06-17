import SwiftUI

struct MangoxSectionLabel: View {
    let title: String
    var horizontalPadding: CGFloat = MangoxSpacing.page

    var body: some View {
        Text(title)
            .mangoxFont(.label)
            .textCase(.uppercase)
            .foregroundStyle(AppColor.fg3)
            .tracking(1.4)
            .padding(.horizontal, horizontalPadding)
    }
}
