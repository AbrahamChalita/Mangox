import SwiftUI

/// Defers building a tab’s root until the user selects it at least once, while keeping
/// `NavigationStack` state in `ContentView` once loaded. Use for secondary tabs only (not Home).
struct LazyTabRootContent<Content: View>: View {
    let tabIndex: Int
    let selectedTab: Int
    @ViewBuilder var content: () -> Content

    @State private var hasLoaded = false

    var body: some View {
        Group {
            if hasLoaded || selectedTab == tabIndex {
                content()
            } else {
                AppColor.bg
                    .ignoresSafeArea()
            }
        }
        .onAppear {
            if selectedTab == tabIndex {
                hasLoaded = true
            }
        }
        .onChange(of: selectedTab) { _, new in
            if new == tabIndex {
                hasLoaded = true
            }
        }
    }
}
