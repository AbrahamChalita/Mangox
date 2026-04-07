import Foundation
import UIKit
import os.log

private let instagramStoryLogger = Logger(subsystem: "com.abchalita.Mangox", category: "InstagramStoryShare")

// MARK: - Instagram Stories (no login)

/// Shares a full-screen story image to Instagram using Meta’s **Sharing to Stories** flow (no Instagram login in Mangox).
///
/// **Documentation:** [Sharing to Stories](https://developers.facebook.com/docs/instagram-platform/sharing-to-stories/)
///
/// iOS flow (matches Meta’s sample):
/// 1. Declare `instagram-stories` in `LSApplicationQueriesSchemes` (required before `canOpenURL` works).
/// 2. Put image bytes on the pasteboard as `com.instagram.sharedSticker.backgroundImage` (JPEG or PNG per Meta).
/// 3. Open `instagram-stories://share?source_application=<Facebook App ID>`.
///
/// **App ID (required since Jan 2023):** `source_application` must be your Facebook App ID or users see
/// *“The app you shared from doesn't currently support sharing to Stories.”*
///
/// **Size:** Meta asks for at least **720×1280** and recommends **9:16** or **9:18**; Mangox uses **1080×1920** (9:16).
///
/// Meta describes separate **background** and **sticker** layers; Mangox sends one full-bleed **background** image.
/// Optional `backgroundTopColor` / `backgroundBottomColor` on the pasteboard are mainly for sticker-only shares; when a
/// background image is present, Meta’s docs state gradient colors are not used for the image case on some platforms.
enum InstagramStoryShare {

    /// Exported story bitmap (9:16 @1080pt — meets minimum size and recommended aspect from Meta’s doc).
    static let storySize = CGSize(width: 1080, height: 1920)

    /// Numeric Facebook / Meta App ID from `FacebookAppID` in Info.plist (build setting `FACEBOOK_APP_ID`).
    static var facebookAppID: String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "FacebookAppID") as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// `instagram-stories://share?source_application=<Facebook App ID>` — required for Instagram to accept the share.
    static func instagramStoriesShareURL() -> URL? {
        guard let appID = facebookAppID else { return nil }
        var components = URLComponents()
        components.scheme = "instagram-stories"
        components.host = "share"
        components.queryItems = [
            URLQueryItem(name: "source_application", value: appID)
        ]
        return components.url
    }

    /// Whether the Instagram app can handle the Stories share URL (requires `LSApplicationQueriesSchemes` + valid `FACEBOOK_APP_ID`).
    static func canOpenInstagramStories() -> Bool {
        guard let url = instagramStoriesShareURL() else { return false }
        return UIApplication.shared.canOpenURL(url)
    }

    // MARK: - Render

    /// Renders a **full-bleed** 1080×1920 story bitmap (same as ``/storySize``) — no letterboxing, no corner logo.
    @MainActor
    static func renderWorkoutStory(
        workout: Workout,
        dominantZone: PowerZone,
        routeName: String?,
        totalElevationGain: Double
    ) -> UIImage {
        InstagramStoryCardRenderer.render(
            workout: workout,
            dominantZone: dominantZone,
            routeName: routeName,
            totalElevationGain: totalElevationGain
        )
    }

    // MARK: - Open Instagram

    /// Copies **PNG or JPEG** bytes to `UIPasteboard` using Meta’s key `com.instagram.sharedSticker.backgroundImage`, then opens
    /// `instagram-stories://share?source_application=…`. Prefer this overload when encoding was done off the main thread.
    ///
    /// Returns `true` if the Instagram URL was opened; `false` if App ID is missing or the URL cannot be opened.
    @discardableResult
    static func presentStories(withPNGData imageData: Data) -> Bool {
        guard let storiesURL = instagramStoriesShareURL() else {
            instagramStoryLogger.error("Instagram Stories: set FACEBOOK_APP_ID in Xcode build settings (FacebookAppID in Info.plist). See https://developers.facebook.com/docs/instagram-platform/sharing-to-stories/")
            return false
        }

        var item: [String: Any] = [
            "com.instagram.sharedSticker.backgroundImage": imageData
        ]
        // Per Meta: if a background *image* is supplied, gradient colors are typically ignored; kept as fallback only.
        item["com.instagram.sharedSticker.backgroundTopColor"] = "050510"
        item["com.instagram.sharedSticker.backgroundBottomColor"] = "100818"

        UIPasteboard.general.setItems(
            [item],
            options: [.expirationDate: Date().addingTimeInterval(300)]
        )

        guard UIApplication.shared.canOpenURL(storiesURL) else { return false }
        UIApplication.shared.open(storiesURL, options: [:], completionHandler: nil)
        return true
    }

    /// Encodes on the caller’s thread, then presents. For large story assets, prefer encoding with ``presentStories(withPNGData:)`` on a background executor.
    @discardableResult
    static func presentStories(with image: UIImage) -> Bool {
        // Meta accepts JPG or PNG for the background asset; PNG keeps gradients and text sharp on the generated card.
        guard let imageData = image.pngData() else { return false }
        return presentStories(withPNGData: imageData)
    }
}
