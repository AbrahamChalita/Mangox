// Features/Social/Presentation/ViewModel/SocialViewModel.swift
import Foundation
import UIKit

@MainActor
@Observable
final class SocialViewModel {
    // MARK: - View state
    var isSharing: Bool = false
    var shareError: String? = nil
    var storyOptions: InstagramStoryCardOptions = InstagramStoryStudioPreferences.load()
    var previewImage: UIImage? = nil
    var isRendering: Bool = false

    // MARK: - AI generation state
    var aiCaption: String?
    var isCaptionGenerating: Bool = false
    var aiTitle: String?
    var isTitleGenerating: Bool = false

    // MARK: - Share fallback state
    var showShareFallback: Bool = false
    var shareFallbackItems: [UIImage] = []

    func saveStoryOptions(_ options: InstagramStoryCardOptions) {
        storyOptions = options
        InstagramStoryStudioPreferences.save(options)
    }

    func resetStoryOptions() {
        saveStoryOptions(.default)
    }

    // MARK: - AI generation

    func generateTitle(
        workout: Workout,
        dominantZoneName: String,
        routeName: String?,
        totalElevationGain: Double
    ) async {
        guard aiTitle == nil, !isTitleGenerating else { return }
        isTitleGenerating = true
        defer { isTitleGenerating = false }
        aiTitle = await OnDeviceCoachEngine.generateStoryCardTitle(
            workout: workout,
            dominantZoneName: dominantZoneName,
            routeName: routeName,
            totalElevationGain: totalElevationGain
        )
    }

    func generateCaption(
        workout: Workout,
        dominantZoneName: String,
        routeName: String?,
        ftpWatts: Int,
        powerZoneLine: String
    ) async {
        guard aiCaption == nil, !isCaptionGenerating else { return }
        isCaptionGenerating = true
        defer { isCaptionGenerating = false }
        aiCaption = await OnDeviceCoachEngine.generateInstagramCaption(
            workout: workout,
            dominantZoneName: dominantZoneName,
            routeName: routeName,
            ftpWatts: ftpWatts,
            powerZoneLine: powerZoneLine
        )
    }

    // MARK: - Rendering

    @MainActor
    func renderPreview(
        workout: Workout,
        dominantZone: PowerZone,
        routeName: String?,
        totalElevationGain: Double,
        personalRecordNames: [String]
    ) async {
        isRendering = true
        await Task.yield()
        let img = InstagramStoryShare.renderWorkoutStory(
            workout: workout,
            dominantZone: dominantZone,
            routeName: routeName,
            totalElevationGain: totalElevationGain,
            personalRecordNames: personalRecordNames,
            options: storyOptions,
            whoopStrain: nil,
            whoopRecovery: nil,
            aiTitle: aiTitle
        )
        previewImage = img
        isRendering = false
    }

    @MainActor
    func shareToInstagram(
        workout: Workout,
        dominantZone: PowerZone,
        routeName: String?,
        totalElevationGain: Double,
        personalRecordNames: [String],
        onError: @escaping (String) -> Void,
        onDismiss: @escaping () -> Void
    ) async {
        guard InstagramStoryShare.facebookAppID != nil else {
            onError(
                "Instagram Stories needs a Meta/Facebook App ID. Add a FacebookAppID key to Info.plist."
            )
            return
        }

        isSharing = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        await Task.yield()

        let opts = storyOptions
        let title = aiTitle

        // 1. Render full card (always needed)
        let full = InstagramStoryShare.renderWorkoutStory(
            workout: workout,
            dominantZone: dominantZone,
            routeName: routeName,
            totalElevationGain: totalElevationGain,
            personalRecordNames: personalRecordNames,
            options: opts,
            whoopStrain: nil,
            whoopRecovery: nil,
            aiTitle: title
        )

        let bgData: Data?
        let stickerData: Data?

        // 2. If layered mode: separate bg + sticker
        if opts.layeredShare {
            let bgImage = InstagramStoryCardRenderer.renderAtmosphericBackgroundOnly(
                dominantZone: dominantZone, options: opts)
            let stickerImage = InstagramStoryCardRenderer.renderStickerLayer(fullCard: full)
            bgData = InstagramStoryShare.encodeBackgroundImageData(bgImage)
            stickerData = InstagramStoryShare.encodeStickerImageData(stickerImage)
        } else {
            bgData = nil
            stickerData = nil
        }

        defer { isSharing = false }

        if opts.layeredShare {
            guard let bgData, let stickerData else {
                onError("Could not encode story images.")
                return
            }
            if InstagramStoryShare.presentStories(
                backgroundPNGData: bgData, stickerPNGData: stickerData)
            {
                InstagramStoryStudioPreferences.save(opts)
                onDismiss()
                return
            }
        } else {
            guard let shareData = InstagramStoryShare.encodeBackgroundImageData(full) else {
                onError("Could not encode story image.")
                return
            }
            if InstagramStoryShare.presentStories(withPNGData: shareData) {
                InstagramStoryStudioPreferences.save(opts)
                onDismiss()
                return
            }
        }

        // Fallback: system share sheet
        shareFallbackItems = [full]
        showShareFallback = true
    }
}
