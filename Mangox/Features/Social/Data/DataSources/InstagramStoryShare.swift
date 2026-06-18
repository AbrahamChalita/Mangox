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

    /// Numeric Facebook / Meta App ID from `FacebookAppID` in Info.plist (sourced from `FACEBOOK_APP_ID` xcconfig).
    static var facebookAppID: String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "FacebookAppID") as? String else {
            return nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        // Strip unresolved xcconfig placeholders (e.g. $(FACEBOOK_APP_ID) when not defined)
        if trimmed.hasPrefix("$(") && trimmed.hasSuffix(")") { return nil }
        return trimmed
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
    ///
    /// `UIImage` encoding APIs are main-actor-isolated (Swift 6); keep encoding on the main actor.
    @MainActor
    static func encodeBackgroundImageData(_ image: UIImage) -> Data? {
        if let j = image.jpegData(compressionQuality: 0.92) { return j }
        return image.pngData()
    }

    /// Sticker layer must keep alpha — **PNG** only.
    @MainActor
    static func encodeStickerImageData(_ image: UIImage) -> Data? {
        image.pngData()
    }

    /// JPEG/PNG compression can be CPU-heavy; `async` preserves structured-concurrency cancellation checks while encoding on the main actor.
    @MainActor
    static func encodeBackgroundImageDataAsync(_ image: UIImage) async -> Data? {
        guard !Task.isCancelled else { return nil }
        return await MainActor.run {
            encodeBackgroundImageData(image)
        }
    }

    @MainActor
    static func encodeStickerImageDataAsync(_ image: UIImage) async -> Data? {
        guard !Task.isCancelled else { return nil }
        return await MainActor.run {
            encodeStickerImageData(image)
        }
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
        sessionKind: InstagramStoryCardSessionKind? = nil,
        whoopStrain: Double? = nil,
        whoopRecovery: Double? = nil,
        aiTitle: String? = nil,
        backgroundImage: UIImage? = nil
    ) -> UIImage {
        InstagramStoryCardRenderer.render(
            workout: workout,
            dominantZone: dominantZone,
            routeName: routeName,
            totalElevationGain: totalElevationGain,
            personalRecordNames: personalRecordNames,
            options: options,
            sessionKind: sessionKind,
            whoopStrain: whoopStrain,
            whoopRecovery: whoopRecovery,
            aiTitle: aiTitle,
            backgroundImage: backgroundImage
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
                "Instagram Stories: FACEBOOK_APP_ID not configured (via xcconfig → FacebookAppID in Info.plist). See https://developers.facebook.com/docs/instagram-platform/sharing-to-stories/"
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
        Task { @MainActor in
            await Task.yield()
            UIApplication.shared.open(storiesURL, options: [:], completionHandler: nil)
        }
        return true
    }

    /// Encodes on the main actor, then presents. For large story assets, prefer ``encodeBackgroundImageDataAsync`` then ``presentStories(withPNGData:)``.
    @discardableResult
    @MainActor
    static func presentStories(with image: UIImage) -> Bool {
        guard let imageData = encodeBackgroundImageData(image) else { return false }
        return presentStories(withPNGData: imageData)
    }

    // MARK: - Deep links (hashtags & profiles)

    /// Mangox's Instagram handle used by the "Tag us" attribution button in the caption sheet.
    static let mangoxInstagramHandle = "mangox.app"

    /// Extracts hashtags (without the leading `#`) from a caption, preserving order and de-duplicating.
    static func hashtags(in caption: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"#(\w+)"#) else { return [] }
        let ns = caption as NSString
        let matches = regex.matches(in: caption, range: NSRange(location: 0, length: ns.length))
        var seen = Set<String>()
        var out: [String] = []
        for m in matches {
            let r = m.range(at: 1)
            guard r.location != NSNotFound, let range = Range(r, in: caption) else { continue }
            let tag = String(caption[range])
            if seen.insert(tag).inserted { out.append(tag) }
        }
        return out
    }

    /// `instagram://tag?name=<hashtag>` — opens the hashtag page in the Instagram app.
    static func instagramHashtagURL(_ name: String) -> URL? {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines).drop(while: { $0 == "#" })
        guard !cleaned.isEmpty else { return nil }
        var c = URLComponents()
        c.scheme = "instagram"
        c.host = "tag"
        c.queryItems = [URLQueryItem(name: "name", value: String(cleaned))]
        return c.url
    }

    /// `instagram://user?username=<handle>` — opens a profile in the Instagram app.
    static func instagramProfileURL(username: String) -> URL? {
        let cleaned = username.trimmingCharacters(in: .whitespacesAndNewlines).drop(while: { $0 == "@" })
        guard !cleaned.isEmpty else { return nil }
        var c = URLComponents()
        c.scheme = "instagram"
        c.host = "user"
        c.queryItems = [URLQueryItem(name: "username", value: String(cleaned))]
        return c.url
    }

    /// Web fallback for a hashtag when the Instagram app is not installed.
    static func instagramHashtagWebURL(_ name: String) -> URL? {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines).drop(while: { $0 == "#" })
        guard !cleaned.isEmpty else { return nil }
        return URL(string: "https://www.instagram.com/explore/tags/\(cleaned)/")
    }

    /// Web fallback for a profile when the Instagram app is not installed.
    static func instagramProfileWebURL(username: String) -> URL? {
        let cleaned = username.trimmingCharacters(in: .whitespacesAndNewlines).drop(while: { $0 == "@" })
        guard !cleaned.isEmpty else { return nil }
        return URL(string: "https://www.instagram.com/\(cleaned)/")
    }

    /// Opens a hashtag in Instagram, falling back to the web page in Safari if the app is not installed.
    @discardableResult
    static func openHashtag(_ name: String) -> Bool {
        if let url = instagramHashtagURL(name), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
            return true
        }
        if let web = instagramHashtagWebURL(name) {
            UIApplication.shared.open(web)
            return true
        }
        return false
    }

    /// Opens an Instagram profile, falling back to the web page in Safari if the app is not installed.
    @discardableResult
    static func openProfile(username: String) -> Bool {
        if let url = instagramProfileURL(username: username), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
            return true
        }
        if let web = instagramProfileWebURL(username: username) {
            UIApplication.shared.open(web)
            return true
        }
        return false
    }
}
