import SwiftData
import SwiftUI
import UIKit

/// Preview and customize the ride summary card before opening Instagram Stories.
struct InstagramStoryStudioView: View {
    let workout: Workout
    let routeName: String?
    let totalElevationGain: Double
    let personalRecordNames: [String]
    let onDismiss: () -> Void
    let onShareError: (String) -> Void

    @State private var options = InstagramStoryStudioPreferences.load()
    @State private var previewImage: UIImage?
    @State private var isRendering = false
    @State private var isSharing = false
    @State private var showShareFallback = false
    @State private var shareFallbackItems: [Any] = []
    @State private var aiCaption: String?
    @State private var isCaptionGenerating = false
    @State private var captionCopied = false
    @State private var aiTitle: String?
    @State private var isTitleGenerating = false

    private var dominantZone: PowerZone {
        PowerZone.zone(for: Int(workout.avgPower.rounded()))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    storyPreview
                    appearanceSection
                    contentSection
                    captionSection
                    exportSection
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 28)
            }
            .background(AppColor.bg)
            .navigationTitle("Instagram Story")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        InstagramStoryStudioPreferences.save(options)
                        onDismiss()
                    }
                }
            }
            .onAppear {
                if previewImage == nil {
                    renderPreview()
                }
            }
            .onChange(of: options) { _, newValue in
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                InstagramStoryStudioPreferences.save(newValue)
                renderPreview()
            }
            .onChange(of: aiTitle) { _, _ in
                renderPreview()
            }
            .task {
                // Generate AI title on appear
                guard aiTitle == nil, !isTitleGenerating else { return }
                isTitleGenerating = true
                defer { isTitleGenerating = false }
                aiTitle = await OnDeviceCoachEngine.generateStoryCardTitle(
                    workout: workout,
                    dominantZoneName: dominantZone.name,
                    routeName: routeName,
                    totalElevationGain: totalElevationGain
                )
            }
            .preferredColorScheme(.dark)
            .sheet(isPresented: $showShareFallback) {
                ShareSheet(activityItems: shareFallbackItems)
            }
        }
    }

    private var storyPreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Preview")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.white.opacity(AppOpacity.textSecondary))

            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.black.opacity(0.35))

                if let previewImage {
                    Image(uiImage: previewImage)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .padding(8)
                } else if isRendering {
                    ProgressView()
                        .tint(AppColor.mango)
                } else {
                    Text("Tap a setting to render")
                        .font(.caption)
                        .foregroundStyle(Color.white.opacity(AppOpacity.textSecondary))
                }
            }
            .aspectRatio(9 / 16, contentMode: .fit)
            .frame(maxWidth: 420)

            Text("Safe areas at top and bottom are reserved for Instagram’s UI.")
                .font(.caption2)
                .foregroundStyle(Color.white.opacity(AppOpacity.textTertiary))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Appearance")
            Picker("Accent", selection: $options.accent) {
                ForEach(InstagramStoryCardOptions.Accent.allCases) { a in
                    Text(a.pickerTitle).tag(a)
                }
            }
            .pickerStyle(.menu)

            Toggle(
                "Layered share (gradient background + movable card)", isOn: $options.layeredShare
            )
            .tint(AppColor.mango)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var contentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Content")
            Toggle("Power / HR chart", isOn: $options.showPowerHRChart)
            Toggle("Heart rate line on chart", isOn: $options.showHeartRateLineOnChart)
                .disabled(!options.showPowerHRChart)
            Toggle("Detail line (cadence, route, …)", isOn: $options.showMetaLine)
            Toggle("NP · TSS · IF row", isOn: $options.showNPAndTSS)
            Toggle("Elevation on card (or in detail line)", isOn: $options.showElevation)
            Toggle("Mangox footer", isOn: $options.showFooterBranding)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tint(AppColor.mango)
    }

    private var captionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                sectionLabel("Caption")
                Image(systemName: "apple.intelligence")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppColor.mango)
                Spacer(minLength: 0)
                if isCaptionGenerating {
                    ProgressView()
                        .scaleEffect(0.75)
                        .tint(AppColor.mango)
                }
            }

            if let caption = aiCaption {
                VStack(alignment: .leading, spacing: 8) {
                    Text(caption)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.white.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)

                    Button {
                        UIPasteboard.general.string = caption
                        captionCopied = true
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        Task {
                            try? await Task.sleep(for: .seconds(2))
                            captionCopied = false
                        }
                    } label: {
                        Label(
                            captionCopied ? "Copied!" : "Copy caption",
                            systemImage: captionCopied ? "checkmark" : "doc.on.doc"
                        )
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(captionCopied ? AppColor.mango : Color.white.opacity(0.65))
                    }
                }
                .padding(12)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else if !isCaptionGenerating {
                Text("Caption will appear here once generated.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.35))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task {
            guard aiCaption == nil, !isCaptionGenerating else { return }
            isCaptionGenerating = true
            defer { isCaptionGenerating = false }
            aiCaption = await OnDeviceCoachEngine.generateInstagramCaption(
                workout: workout,
                dominantZoneName: dominantZone.name,
                routeName: routeName,
                ftpWatts: PowerZone.ftp,
                powerZoneLine: dominantZone.name
            )
        }
    }

    private var exportSection: some View {
        VStack(spacing: 12) {
            Button {
                shareToInstagram()
            } label: {
                HStack(spacing: 10) {
                    if isSharing {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image("BrandInstagram")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 22, height: 22)
                    }
                    Text(isSharing ? "Opening Instagram…" : "Share to Instagram Stories")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            }
            .buttonStyle(.borderedProminent)
            .tint(
                Color(
                    red: 0.88,
                    green: 0.19,
                    blue: 0.42
                )
            )
            .disabled(isSharing || isRendering)

            Button("Reset to defaults") {
                options = .default
            }
            .font(.subheadline)
            .foregroundStyle(Color.white.opacity(AppOpacity.textSecondary))
        }
        .padding(.top, 8)
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.white.opacity(AppOpacity.textSecondary))
    }

    private func renderPreview() {
        isRendering = true
        Task { @MainActor in
            await Task.yield()
            let img = InstagramStoryShare.renderWorkoutStory(
                workout: workout,
                dominantZone: dominantZone,
                routeName: routeName,
                totalElevationGain: totalElevationGain,
                personalRecordNames: personalRecordNames,
                options: options,
                whoopStrain: nil,
                whoopRecovery: nil,
                aiTitle: aiTitle
            )
            previewImage = img
            isRendering = false
        }
    }

    private func shareToInstagram() {
        guard InstagramStoryShare.facebookAppID != nil else {
            onShareError(
                "Instagram Stories needs a Meta/Facebook App ID. Set FACEBOOK_APP_ID in Xcode build settings (see Meta: Sharing to Stories)."
            )
            return
        }

        isSharing = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        Task { @MainActor in
            await Task.yield()
            let opts = options
            let title = aiTitle
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

            if opts.layeredShare {
                let bgImage = InstagramStoryCardRenderer.renderAtmosphericBackgroundOnly(
                    dominantZone: dominantZone,
                    options: opts
                )
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
                    onShareError("Could not encode story images.")
                    return
                }
                if InstagramStoryShare.presentStories(
                    backgroundPNGData: bgData,
                    stickerPNGData: stickerData
                ) {
                    InstagramStoryStudioPreferences.save(opts)
                    onDismiss()
                    return
                }
            } else {
                guard let shareData = InstagramStoryShare.encodeBackgroundImageData(full) else {
                    onShareError("Could not encode story image.")
                    return
                }
                if InstagramStoryShare.presentStories(withPNGData: shareData) {
                    InstagramStoryStudioPreferences.save(opts)
                    onDismiss()
                    return
                }
            }

            shareFallbackItems = [full]
            showShareFallback = true
        }
    }
}
