// Features/Social/Data/DataSources/InstagramStoryShare.swift
import Foundation
import UIKit
import os.log

private let instagramStoryLogger = Logger(
    subsystem: "com.abchalita.Mangox", category: "InstagramStoryShare")

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
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "FacebookAppID") as? String else {
            return nil
        }
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

    // MARK: - Encoding (pasteboard size)

    /// Opaque story layers: prefer **JPEG** so two-layer shares stay under iOS pasteboard limits (large dual-PNG payloads often fail silently).
    static func encodeBackgroundImageData(_ image: UIImage) -> Data? {
        if let j = image.jpegData(compressionQuality: 0.92) { return j }
        return image.pngData()
    }

    /// Sticker layer must keep alpha — **PNG** only.
    static func encodeStickerImageData(_ image: UIImage) -> Data? {
        image.pngData()
    }

    // MARK: - Render

    /// Renders a **full-bleed** 1080×1920 story bitmap (same as ``/storySize``) — no letterboxing, no corner logo.
    @MainActor
    static func renderWorkoutStory(
        workout: Workout,
        dominantZone: PowerZone,
        routeName: String?,
        totalElevationGain: Double,
        personalRecordNames: [String] = [],
        options: InstagramStoryCardOptions? = nil,
        whoopStrain: Double? = nil,
        whoopRecovery: Double? = nil,
        aiTitle: String? = nil
    ) -> UIImage {
        InstagramStoryCardRenderer.render(
            workout: workout,
            dominantZone: dominantZone,
            routeName: routeName,
            totalElevationGain: totalElevationGain,
            personalRecordNames: personalRecordNames,
            options: options,
            whoopStrain: whoopStrain,
            whoopRecovery: whoopRecovery,
            aiTitle: aiTitle
        )
    }

    // MARK: - Open Instagram

    /// Copies **PNG or JPEG** bytes to `UIPasteboard` using Meta’s key `com.instagram.sharedSticker.backgroundImage`, then opens
    /// `instagram-stories://share?source_application=…`. Prefer this overload when encoding was done off the main thread.
    ///
    /// Returns `true` if the Instagram URL was opened; `false` if App ID is missing or the URL cannot be opened.
    @discardableResult
    static func presentStories(withPNGData imageData: Data) -> Bool {
        return presentStories(backgroundPNGData: imageData, stickerPNGData: nil)
    }

    /// Opens Instagram Stories with optional **background** and/or **sticker** assets (Meta pasteboard API).
    /// Pass at least one of `backgroundPNGData` or `stickerPNGData`.
    ///
    /// Pasteboard keys follow Meta’s iOS samples: **no** gradient keys when a background image is present (only sticker-only mode sets colors).
    @discardableResult
    static func presentStories(
        backgroundPNGData: Data?,
        stickerPNGData: Data?,
        backgroundTopColorHex: String = "050510",
        backgroundBottomColorHex: String = "100818"
    ) -> Bool {
        guard let storiesURL = instagramStoriesShareURL() else {
            instagramStoryLogger.error(
                "Instagram Stories: set FACEBOOK_APP_ID in Xcode build settings (FacebookAppID in Info.plist). See https://developers.facebook.com/docs/instagram-platform/sharing-to-stories/"
            )
            return false
        }

        guard backgroundPNGData != nil || stickerPNGData != nil else { return false }

        var item: [String: Any] = [:]
        switch (backgroundPNGData, stickerPNGData) {
        case (let bg?, nil):
            item["com.instagram.sharedSticker.backgroundImage"] = bg
        case (nil, let st?):
            item["com.instagram.sharedSticker.stickerImage"] = st
            item["com.instagram.sharedSticker.backgroundTopColor"] = backgroundTopColorHex
            item["com.instagram.sharedSticker.backgroundBottomColor"] = backgroundBottomColorHex
        case (let bg?, let st?):
            item["com.instagram.sharedSticker.backgroundImage"] = bg
            item["com.instagram.sharedSticker.stickerImage"] = st
        default:
            return false
        }

        UIPasteboard.general.setItems(
            [item],
            options: [.expirationDate: Date().addingTimeInterval(300)]
        )

        guard UIApplication.shared.canOpenURL(storiesURL) else {
            instagramStoryLogger.warning(
                "Instagram Stories: canOpenURL(instagram-stories) is false — is Instagram installed?"
            )
            return false
        }

        // Defer `open` one run-loop turn so the pasteboard commit is visible to Instagram when it foregrounds.
        DispatchQueue.main.async {
            UIApplication.shared.open(storiesURL, options: [:], completionHandler: nil)
        }
        return true
    }

    /// Encodes on the caller’s thread, then presents. For large story assets, prefer encoding with ``presentStories(withPNGData:)`` on a background executor.
    @discardableResult
    static func presentStories(with image: UIImage) -> Bool {
        guard let imageData = encodeBackgroundImageData(image) else { return false }
        return presentStories(withPNGData: imageData)
    }
}
