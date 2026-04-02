import SwiftUI

/// Subscribes to `FTPRefreshTrigger` so **only** this subtree re-renders when `PowerZone.ftp` changes
/// (via `generation`). Use instead of `let _ = ftpRefresh.generation` at the root of large screens.
struct FTPRefreshScope<Content: View>: View {
    @Environment(FTPRefreshTrigger.self) private var ftpRefresh
    @ViewBuilder var content: () -> Content

    var body: some View {
        let _ = ftpRefresh.generation
        content()
    }
}
