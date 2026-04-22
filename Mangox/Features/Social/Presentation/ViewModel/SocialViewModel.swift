// Features/Social/Presentation/ViewModel/SocialViewModel.swift
import Foundation
import UIKit

@MainActor
@Observable
final class SocialViewModel {
    private weak var whoopService: WhoopServiceProtocol?

    init(whoopService: WhoopServiceProtocol? = nil) {
        self.whoopService = whoopService
    }

    private func whoopMetricsForStory() -> (strain: Double?, recovery: Double?) {
        guard let whoop = whoopService, whoop.isConnected else { return (nil, nil) }
        let recovery = whoop.latestRecoveryScore.flatMap { $0 > 0 ? $0 : nil }
        return (nil, recovery)
    }

    // MARK: - View state
    var isSharing: Bool = false
    var shareError: String? = nil
    var storyOptions: InstagramStoryCardOptions = InstagramStoryStudioPreferences.load()
    var previewImage: UIImage? = nil
    var isRendering: Bool = false

    // MARK: - Transient background image (not persisted — lives here, not in options)
    /// Set by the PhotosPicker in InstagramStoryStudioView. Cleared on reset or source change.
    var customBackgroundImage: UIImage? = nil

    // MARK: - AI generation state
    var aiCaption: String?
    var isCaptionGenerating: Bool = false
    /// True when ``aiCaption`` was filled from ``OnDeviceModelFallbackCopy`` (no on-device language model).
    var instagramCaptionUsesStatsFallback: Bool = false
    var aiTitle: String?
    var isTitleGenerating: Bool = false

    /// Unstructured tasks so SwiftUI `.task` / sheet churn does not cancel on-device model calls mid-flight.
    private var storyTitleWork: Task<Void, Never>?
    private var storyCaptionWork: Task<Void, Never>?

    // MARK: - Share fallback state
    var showShareFallback: Bool = false
    var shareFallbackItems: [UIImage] = []

    /// When this matches the current share request, ``previewImage`` is safe to reuse (skips a second full-card raster for single-layer shares).
    private struct PreviewReuseKey: Equatable {
        var workoutID: UUID
        var storyOptions: InstagramStoryCardOptions
        var aiTitle: String?
        var backgroundObjectID: ObjectIdentifier?
        var whoopRecovery: Double?
        var whoopStrain: Double?
    }

    private var previewReuseKey: PreviewReuseKey?

    func saveStoryOptions(_ options: InstagramStoryCardOptions) {
        storyOptions = options
        InstagramStoryStudioPreferences.save(options)
    }

    /// When options are still factory defaults and the workout looks like a trainer session, prefer NP over elevation in quick stats.
    func applySessionRecommendedOptionsIfDefault(
        workout: Workout,
        routeName: String?,
        totalElevationGain: Double
    ) {
        guard storyOptions == InstagramStoryCardOptions.default else { return }
        let kind = InstagramStoryCardSessionKind.resolve(
            workout: workout,
            routeName: routeName,
            totalElevationGain: totalElevationGain
        )
        guard kind == .indoorTrainer else { return }
        var o = storyOptions
        o.showElevation = false
        saveStoryOptions(o)
    }

    func resetStoryOptions() {
        customBackgroundImage = nil
        previewReuseKey = nil
        saveStoryOptions(.default)
    }

    // MARK: - AI generation

    /// Starts story headline generation when `aiTitle` is still empty. Uses an unstructured `Task` so it is not a child of SwiftUI’s `.task` and survives brief view cancellation / sheet rebuilds.
    func beginStoryCardTitleGenerationIfNeeded(
        workout: Workout,
        dominantZoneName: String,
        routeName: String?,
        totalElevationGain: Double
    ) {
        guard aiTitle == nil else { return }
        if let storyTitleWork, !storyTitleWork.isCancelled { return }
        guard OnDeviceCoachEngine.isOnDeviceWritingModelAvailable else { return }
        storyTitleWork = Task { @MainActor in
            isTitleGenerating = true
            defer {
                isTitleGenerating = false
                storyTitleWork = nil
            }
            let generated = await OnDeviceCoachEngine.generateStoryCardTitle(
                workout: workout,
                dominantZoneName: dominantZoneName,
                routeName: routeName,
                totalElevationGain: totalElevationGain
            )
            guard aiTitle == nil else { return }
            aiTitle = generated
        }
    }

    /// Starts caption generation when `aiCaption` is still empty. Same unstructured pattern as ``beginStoryCardTitleGenerationIfNeeded``.
    func beginInstagramCaptionGenerationIfNeeded(
        workout: Workout,
        dominantZoneName: String,
        routeName: String?,
        ftpWatts: Int,
        powerZoneLine: String
    ) {
        guard aiCaption == nil else { return }
        if let storyCaptionWork, !storyCaptionWork.isCancelled { return }
        if !OnDeviceCoachEngine.isOnDeviceWritingModelAvailable {
            aiCaption = OnDeviceModelFallbackCopy.instagramStoryCaption(
                workout: workout,
                dominantZoneName: dominantZoneName,
                routeName: routeName,
                ftpWatts: ftpWatts,
                powerZoneLine: powerZoneLine
            )
            instagramCaptionUsesStatsFallback = true
            return
        }
        storyCaptionWork = Task { @MainActor in
            isCaptionGenerating = true
            defer {
                isCaptionGenerating = false
                storyCaptionWork = nil
            }
            let generated = await OnDeviceCoachEngine.generateInstagramCaption(
                workout: workout,
                dominantZoneName: dominantZoneName,
                routeName: routeName,
                ftpWatts: ftpWatts,
                powerZoneLine: powerZoneLine
            )
            guard aiCaption == nil else { return }
            if let generated, !generated.isEmpty {
                aiCaption = generated
                instagramCaptionUsesStatsFallback = false
            } else {
                aiCaption = OnDeviceModelFallbackCopy.instagramStoryCaption(
                    workout: workout,
                    dominantZoneName: dominantZoneName,
                    routeName: routeName,
                    ftpWatts: ftpWatts,
                    powerZoneLine: powerZoneLine
                )
                instagramCaptionUsesStatsFallback = true
            }
        }
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
        let session = InstagramStoryCardSessionKind.resolve(
            workout: workout,
            routeName: routeName,
            totalElevationGain: totalElevationGain
        )
        let whoop = whoopMetricsForStory()
        let img = InstagramStoryShare.renderWorkoutStory(
            workout: workout,
            dominantZone: dominantZone,
            routeName: routeName,
            totalElevationGain: totalElevationGain,
            personalRecordNames: personalRecordNames,
            options: storyOptions,
            sessionKind: session,
            whoopStrain: whoop.strain,
            whoopRecovery: whoop.recovery,
            aiTitle: aiTitle,
            backgroundImage: customBackgroundImage
        )
        previewImage = img
        previewReuseKey = PreviewReuseKey(
            workoutID: workout.id,
            storyOptions: storyOptions,
            aiTitle: aiTitle,
            backgroundObjectID: customBackgroundImage.map { ObjectIdentifier($0 as AnyObject) },
            whoopRecovery: whoop.recovery,
            whoopStrain: whoop.strain
        )
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

        let opts   = storyOptions
        let title  = aiTitle
        let bgImg  = customBackgroundImage
        let session = InstagramStoryCardSessionKind.resolve(
            workout: workout,
            routeName: routeName,
            totalElevationGain: totalElevationGain
        )
        let whoop = whoopMetricsForStory()
        let shareKey = PreviewReuseKey(
            workoutID: workout.id,
            storyOptions: opts,
            aiTitle: title,
            backgroundObjectID: bgImg.map { ObjectIdentifier($0 as AnyObject) },
            whoopRecovery: whoop.recovery,
            whoopStrain: whoop.strain
        )
        let reuseStudioPreview = !opts.layeredShare
            && previewReuseKey == shareKey
            && previewImage != nil

        // 1. Full composite card (reuse studio preview when inputs match — avoids duplicate raster for single-layer share)
        let full: UIImage
        if reuseStudioPreview, let cached = previewImage {
            full = cached
        } else {
            full = InstagramStoryShare.renderWorkoutStory(
                workout: workout,
                dominantZone: dominantZone,
                routeName: routeName,
                totalElevationGain: totalElevationGain,
                personalRecordNames: personalRecordNames,
                options: opts,
                sessionKind: session,
                whoopStrain: whoop.strain,
                whoopRecovery: whoop.recovery,
                aiTitle: title,
                backgroundImage: bgImg
            )
        }

        let bgData: Data?
        let stickerData: Data?

        // 2. Layered mode: separate background + sticker layers (encode on the main actor; avoid `async let` here — Swift 6 can treat child tasks as non‑MainActor before the first `await`, which breaks UIImage encoding isolation).
        if opts.layeredShare {
            let bgImage = InstagramStoryCardRenderer.renderBackgroundOnly(
                dominantZone: dominantZone, options: opts, backgroundImage: bgImg)
            let stickerImage = InstagramStoryCardRenderer.renderStickerLayer(fullCard: full)
            bgData = await InstagramStoryShare.encodeBackgroundImageDataAsync(bgImage)
            stickerData = await InstagramStoryShare.encodeStickerImageDataAsync(stickerImage)
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
            if InstagramStoryShare.presentStories(backgroundPNGData: bgData, stickerPNGData: stickerData) {
                InstagramStoryStudioPreferences.save(opts)
                onDismiss()
                return
            }
        } else {
            guard let shareData = await InstagramStoryShare.encodeBackgroundImageDataAsync(full) else {
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
