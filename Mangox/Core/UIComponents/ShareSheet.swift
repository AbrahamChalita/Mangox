import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - Workout File Activity Item Source

/// Custom UIActivityItemSource that properly declares file type metadata
/// so that Strava, Garmin Connect, TrainingPeaks, and other fitness apps
/// appear in the iOS share sheet.
///
/// The key issue with plain URL sharing via UIActivityViewController is that
/// the system doesn't always infer the correct UTType/MIME from a temp file URL.
/// By implementing UIActivityItemSource we explicitly tell the share sheet:
/// 1. The UTType of the file (so the system matches it to apps that accept that type)
/// 2. The MIME type (for apps that filter by MIME)
/// 3. A proper subject line (for email/message sharing)
/// 4. The data itself as a fallback
final class WorkoutFileActivityItem: NSObject, UIActivityItemSource {
    let fileURL: URL
    let fileName: String
    let utType: UTType
    let mimeType: String

    init(fileURL: URL) {
        self.fileURL = fileURL
        self.fileName = fileURL.lastPathComponent

        let ext = fileURL.pathExtension.lowercased()
        switch ext {
        case "tcx":
            self.utType = UTType(filenameExtension: "tcx") ?? UTType.xml
            self.mimeType = "application/vnd.garmin.tcx+xml"
        case "gpx":
            self.utType = UTType(filenameExtension: "gpx") ?? UTType.xml
            self.mimeType = "application/gpx+xml"
        case "fit":
            self.utType = UTType(filenameExtension: "fit") ?? UTType.data
            self.mimeType = "application/vnd.ant.fit"
        default:
            self.utType = UTType.xml
            self.mimeType = "application/xml"
        }

        super.init()
    }

    // MARK: - UIActivityItemSource

    /// Placeholder tells the share sheet what kind of item to expect.
    /// Returning the URL here lets the system inspect the file extension early.
    func activityViewControllerPlaceholderItem(
        _ activityViewController: UIActivityViewController
    ) -> Any {
        fileURL
    }

    /// The actual item to share. For file-based sharing, the URL is what apps receive.
    func activityViewController(
        _ activityViewController: UIActivityViewController,
        itemForActivityType activityType: UIActivity.ActivityType?
    ) -> Any? {
        fileURL
    }

    /// Subject line for email, messages, etc.
    func activityViewController(
        _ activityViewController: UIActivityViewController,
        subjectForActivityType activityType: UIActivity.ActivityType?
    ) -> String {
        "Mangox Cycling Workout"
    }

    /// Declare the UTType so the system can match against apps that accept this file type.
    /// This is the critical method that makes Strava appear in the share sheet.
    func activityViewController(
        _ activityViewController: UIActivityViewController,
        dataTypeIdentifierForActivityType activityType: UIActivity.ActivityType?
    ) -> String {
        utType.identifier
    }

    /// Provide a proper filename with extension for apps that use the LPLinkMetadata path.
    @available(iOS 13.0, *)
    func activityViewControllerLinkMetadata(
        _ activityViewController: UIActivityViewController
    ) -> LPLinkMetadata? {
        let metadata = LPLinkMetadata()
        metadata.title = fileName
        metadata.originalURL = fileURL
        return metadata
    }
}

// MARK: - Share Sheet (UIViewControllerRepresentable)

/// A SwiftUI wrapper around UIActivityViewController that properly handles
/// workout file sharing with fitness apps (Strava, Garmin Connect, etc.).
///
/// Usage:
/// ```
/// ShareSheet(fileURLs: [exportedFileURL])
/// ```
///
/// For backward compatibility, also supports raw activity items:
/// ```
/// ShareSheet(activityItems: [someURL])
/// ```
struct ShareSheet: UIViewControllerRepresentable {
    /// Preferred initializer: pass file URLs that will be wrapped in
    /// WorkoutFileActivityItem for proper UTType/MIME declaration.
    var fileURLs: [URL]

    /// Raw activity items (backward compatibility). If fileURLs is non-empty,
    /// these are ignored.
    var activityItems: [Any]

    /// Optional: excluded activity types (e.g. hide print, assign to contact, etc.)
    var excludedActivityTypes: [UIActivity.ActivityType]

    /// Called when the share sheet is dismissed.
    var onComplete: ((Bool) -> Void)?

    // MARK: - Initializers

    /// Preferred: share workout files with proper type metadata.
    init(
        fileURLs: [URL],
        excludedActivityTypes: [UIActivity.ActivityType] = Self.defaultExcluded,
        onComplete: ((Bool) -> Void)? = nil
    ) {
        self.fileURLs = fileURLs
        self.activityItems = []
        self.excludedActivityTypes = excludedActivityTypes
        self.onComplete = onComplete
    }

    /// Backward-compatible: share raw items. If items are URLs with known
    /// fitness file extensions, they'll be auto-wrapped for proper sharing.
    init(
        activityItems: [Any],
        excludedActivityTypes: [UIActivity.ActivityType] = Self.defaultExcluded,
        onComplete: ((Bool) -> Void)? = nil
    ) {
        // Auto-detect file URLs and wrap them
        var detectedFileURLs: [URL] = []
        var otherItems: [Any] = []

        for item in activityItems {
            if let url = item as? URL, url.isFileURL {
                let ext = url.pathExtension.lowercased()
                if ["tcx", "gpx", "fit", "xml"].contains(ext) {
                    detectedFileURLs.append(url)
                } else {
                    otherItems.append(item)
                }
            } else {
                otherItems.append(item)
            }
        }

        self.fileURLs = detectedFileURLs
        self.activityItems = otherItems
        self.excludedActivityTypes = excludedActivityTypes
        self.onComplete = onComplete
    }

    // MARK: - Default Exclusions

    /// Activity types that don't make sense for workout file sharing.
    static let defaultExcluded: [UIActivity.ActivityType] = [
        .assignToContact,
        .addToReadingList,
        .postToFlickr,
        .postToVimeo,
        .openInIBooks,
    ]

    // MARK: - UIViewControllerRepresentable

    func makeUIViewController(context: Context) -> UIActivityViewController {
        // Build the items list: wrapped file URLs + any other raw items
        var items: [Any] = fileURLs.map { WorkoutFileActivityItem(fileURL: $0) }
        items.append(contentsOf: activityItems)

        // If we somehow have no wrapped items but do have raw URLs, pass them directly
        if items.isEmpty {
            items = activityItems
        }

        let controller = UIActivityViewController(
            activityItems: items,
            applicationActivities: nil
        )

        controller.excludedActivityTypes = excludedActivityTypes

        controller.completionWithItemsHandler = { _, completed, _, _ in
            onComplete?(completed)
        }

        return controller
    }

    func updateUIViewController(
        _ uiViewController: UIActivityViewController,
        context: Context
    ) {
        // No dynamic updates needed
    }
}

// MARK: - LinkPresentation import

import LinkPresentation

// MARK: - Preview

#Preview {
    ShareSheet(activityItems: [URL(fileURLWithPath: "/tmp/test.tcx")])
}
