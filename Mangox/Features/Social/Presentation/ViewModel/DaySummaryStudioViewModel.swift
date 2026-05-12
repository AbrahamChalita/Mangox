// Features/Social/Presentation/ViewModel/DaySummaryStudioViewModel.swift
import Foundation
import SwiftData
import UIKit

@Observable
@MainActor
final class DaySummaryStudioViewModel {

    let date: Date

    private(set) var summary: DaySummary?
    var cardOptions: DaySummaryCardOptions
    var customBackgroundImage: UIImage?
    private(set) var previewImage: UIImage?
    private(set) var thumbnails: [DaySummaryCardOptions.Template: UIImage] = [:]
    private(set) var isRendering = false
    private var thumbnailDate: Date?
    private var thumbnailTask: Task<Void, Never>?
    private(set) var isSharing = false
    var showShareFallback = false
    private(set) var shareFallbackItems: [Any] = []

    private let buildSummary: BuildDaySummaryUseCase
    private let enrichStravaStreams: EnrichStravaStreamsUseCase
    private var enrichmentTask: Task<Void, Never>?

    private static let prefsKey = "mangox.daySummaryCardOptions"

    init(
        date: Date,
        modelContext: ModelContext,
        repository: LoggedActivityRepository,
        enrichStravaStreams: EnrichStravaStreamsUseCase
    ) {
        self.date = date
        self.buildSummary = BuildDaySummaryUseCase(modelContext: modelContext, activityRepository: repository)
        self.enrichStravaStreams = enrichStravaStreams
        if let data = UserDefaults.standard.data(forKey: Self.prefsKey),
           let opts = try? JSONDecoder().decode(DaySummaryCardOptions.self, from: data) {
            self.cardOptions = opts
        } else {
            self.cardOptions = .default
        }
    }

    // MARK: - Data

    func load() {
        guard let s = try? buildSummary(for: date) else { return }
        summary = s
        scheduleStreamEnrichmentIfNeeded()
    }

    /// Triggers lazy stream enrichment for any Strava activities in this day that are still
    /// missing best-km / HR-zone data. As each activity finishes, we rebuild the summary and
    /// re-render so richer details appear without the user having to leave the screen.
    private func scheduleStreamEnrichmentIfNeeded() {
        guard let summary else { return }
        let candidates = summary.loggedActivities.filter(EnrichStravaStreamsUseCase.needsEnrichment)
        guard !candidates.isEmpty else { return }

        enrichmentTask?.cancel()
        enrichmentTask = Task { @MainActor [weak self] in
            guard let self else { return }
            _ = await self.enrichStravaStreams.enrich(candidates) { [weak self] _ in
                guard let self, !Task.isCancelled else { return }
                // Each per-activity update writes through SwiftData; rebuild the summary so the
                // next render picks up the new metrics. Only re-render once at the end of the
                // batch in `await` form below — interim renders would just thrash on a fast pipe.
                if let refreshed = try? self.buildSummary(for: self.date) {
                    self.summary = refreshed
                }
            }
            guard !Task.isCancelled else { return }
            await self.renderPreview()
            self.invalidateThumbnails()
            self.renderThumbnails()
        }
    }

    // MARK: - Options persistence

    func resetOptions() {
        invalidateThumbnails()
        customBackgroundImage = nil
        saveOptions(.default)
    }

    func saveOptions(_ opts: DaySummaryCardOptions) {
        cardOptions = opts
        if let data = try? JSONEncoder().encode(opts) {
            UserDefaults.standard.set(data, forKey: Self.prefsKey)
        }
    }

    // MARK: - Rendering

    func renderPreview() async {
        guard let summary, !Task.isCancelled else { return }
        isRendering = true
        defer { isRendering = false }
        guard !Task.isCancelled else { return }
        let image = InstagramStoryCardRenderer.renderDaySummary(
            summary: summary,
            options: cardOptions,
            backgroundImage: customBackgroundImage
        )
        guard !Task.isCancelled else { return }
        previewImage = image
    }

    func invalidateThumbnails() {
        thumbnailTask?.cancel()
        thumbnailTask = nil
        thumbnailDate = nil
        thumbnails = [:]
    }

    func renderThumbnails() {
        guard let summary else { return }
        guard thumbnailDate != date || thumbnails.isEmpty else { return }
        thumbnailTask?.cancel()
        let s = summary
        let base = cardOptions
        let bg = customBackgroundImage
        let targetDate = date
        thumbnailTask = Task { @MainActor [weak self] in
            for template in DaySummaryCardOptions.Template.allCases {
                guard let self, !Task.isCancelled else { return }
                var opts = base
                opts.template = template
                let full = InstagramStoryCardRenderer.renderDaySummary(
                    summary: s,
                    options: opts,
                    backgroundImage: bg
                )
                let thumb = await full.byPreparingThumbnail(ofSize: CGSize(width: 256, height: 456)) ?? full
                guard !Task.isCancelled else { return }
                thumbnails[template] = thumb
                thumbnailDate = targetDate
            }
        }
    }

    // MARK: - Sharing

    func shareToInstagram(onError: @escaping (String) -> Void, onDismiss: @escaping () -> Void) async {
        guard let summary else { return }
        isSharing = true
        defer { isSharing = false }
        let image = InstagramStoryCardRenderer.renderDaySummary(
            summary: summary,
            options: cardOptions,
            backgroundImage: customBackgroundImage
        )
        if InstagramStoryShare.canOpenInstagramStories() {
            let opened = InstagramStoryShare.presentStories(with: image)
            if opened {
                onDismiss()
            } else {
                onError("Could not open Instagram Stories. Make sure Instagram is installed.")
            }
        } else {
            shareFallbackItems = [image]
            showShareFallback = true
        }
    }

    func saveToPhotos() {
        guard let summary else { return }
        let image = InstagramStoryCardRenderer.renderDaySummary(
            summary: summary,
            options: cardOptions,
            backgroundImage: customBackgroundImage
        )
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
    }
}
