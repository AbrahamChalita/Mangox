import SwiftUI

/// Vector mango logo from asset catalog — use for coach / AI affordances instead of generic brain icons.
struct MangoxMark: View {
    var size: CGFloat = 24

    var body: some View {
        Image("MangoxLogo")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityLabel("Mangox")
    }
}
