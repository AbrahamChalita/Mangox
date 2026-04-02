import Foundation
import UIKit

// MARK: - Instagram Stories (no login)

/// Shares a full-screen story image to Instagram via the official URL scheme + pasteboard.
/// See Meta’s “Sharing to Stories” docs: background PNG is passed through `UIPasteboard` keys,
/// then `instagram-stories://share` opens the Instagram app — no OAuth or Instagram login in Mangox.
enum InstagramStoryShare {

    /// Instagram Stories canvas (9:16, full HD width).
    static let storySize = CGSize(width: 1080, height: 1920)

    private static let storiesShareURL = URL(string: "instagram-stories://share")!

    /// Whether the Instagram app can handle the Stories share URL (requires `LSApplicationQueriesSchemes`).
    static func canOpenInstagramStories() -> Bool {
        UIApplication.shared.canOpenURL(storiesShareURL)
    }

    // MARK: - Render

    /// Renders the same rich summary card used for Strava, then letterboxes it into a 9:16 story
    /// with a Strava-style gradient frame and optional Mangox mark in the bottom margin.
    @MainActor
    static func renderWorkoutStory(
        workout: Workout,
        dominantZone: PowerZone,
        sortedSamples: [WorkoutSample],
        mmp: WorkoutMMP?,
        newPRFlags: [NewPRFlag],
        routeName: String?,
        totalElevationGain: Double,
        zoneBuckets: [(zone: PowerZone, percent: Double)]
    ) -> UIImage? {
        guard let card = StravaPostBuilder.renderSummaryCard(
            workout: workout,
            dominantZone: dominantZone,
            sortedSamples: sortedSamples,
            mmp: mmp,
            newPRFlags: newPRFlags,
            routeName: routeName,
            totalElevationGain: totalElevationGain,
            zoneBuckets: zoneBuckets
        ) else {
            return nil
        }
        return composeStoryImage(from: card)
    }

    /// Places the summary card on a 9:16 canvas with a gradient frame and a small Mangox mark (Instagram-safe zone).
    static func composeStoryImage(from card: UIImage) -> UIImage? {
        let renderer = UIGraphicsImageRenderer(size: storySize)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            drawStoryGradient(in: cg, size: storySize)

            let w = card.size.width
            let h = card.size.height
            let scale = min(storySize.width / w, storySize.height / h)
            let dw = w * scale
            let dh = h * scale
            let x = (storySize.width - dw) / 2
            let y = (storySize.height - dh) / 2
            card.draw(in: CGRect(x: x, y: y, width: dw, height: dh))

            if let logo = UIImage(named: "MangoxLogo") {
                let logoW: CGFloat = 100
                let aspect = logo.size.height / max(logo.size.width, 1)
                let logoH = logoW * aspect
                let margin: CGFloat = 40
                let logoRect = CGRect(
                    x: storySize.width - logoW - margin,
                    y: storySize.height - logoH - margin,
                    width: logoW,
                    height: logoH
                )
                logo.draw(in: logoRect, blendMode: .normal, alpha: 0.92)
            }
        }
    }

    private static func drawStoryGradient(in context: CGContext, size: CGSize) {
        context.saveGState()
        let colors: [CGColor] = [
            UIColor(red: 0.02, green: 0.03, blue: 0.08, alpha: 1).cgColor,
            UIColor(red: 0.18, green: 0.07, blue: 0.18, alpha: 1).cgColor,
            UIColor(red: 0.04, green: 0.06, blue: 0.04, alpha: 1).cgColor,
            UIColor(red: 0.02, green: 0.03, blue: 0.06, alpha: 1).cgColor
        ]
        let locations: [CGFloat] = [0, 0.35, 0.65, 1]
        let space = CGColorSpaceCreateDeviceRGB()
        guard let gradient = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: locations) else {
            context.restoreGState()
            return
        }
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: size.width * 0.5, y: 0),
            end: CGPoint(x: size.width * 0.5, y: size.height),
            options: []
        )
        context.restoreGState()
    }

    // MARK: - Open Instagram

    /// Copies the image to the pasteboard using Instagram’s keys and opens the Stories composer.
    /// Returns `true` if Instagram was opened; `false` if the app isn’t installed or image data failed.
    @discardableResult
    static func presentStories(with image: UIImage) -> Bool {
        guard let pngData = image.pngData() else { return false }

        var item: [String: Any] = [
            "com.instagram.sharedSticker.backgroundImage": pngData
        ]
        // Optional gradient hints when Instagram generates a fallback (we already bake a full-bleed image).
        item["com.instagram.sharedSticker.backgroundTopColor"] = "050510"
        item["com.instagram.sharedSticker.backgroundBottomColor"] = "100818"

        UIPasteboard.general.setItems(
            [item],
            options: [.expirationDate: Date().addingTimeInterval(300)]
        )

        guard UIApplication.shared.canOpenURL(storiesShareURL) else { return false }
        UIApplication.shared.open(storiesShareURL, options: [:], completionHandler: nil)
        return true
    }
}
