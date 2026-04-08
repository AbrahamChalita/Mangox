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
                VStack(spacing: 24) {
                    storyPreview
                    appearanceSection
                    contentSection
                    captionSection
                    exportSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
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
                    .foregroundStyle(Color.white.opacity(AppOpacity.textSecondary))
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
            HStack {
                Text("PREVIEW")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.white.opacity(AppOpacity.textTertiary))
                    .tracking(1.5)
                Spacer()
                if isRendering {
                    ProgressView()
                        .scaleEffect(0.6)
                        .tint(AppColor.mango)
                }
            }

            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white.opacity(AppOpacity.cardBg))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(Color.white.opacity(AppOpacity.cardBorder), lineWidth: 1)
                    )

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
                    VStack(spacing: 8) {
                        Image(systemName: "photo")
                            .font(.system(size: 28))
                            .foregroundStyle(Color.white.opacity(AppOpacity.textQuaternary))
                        Text("Tap a setting to render")
                            .font(.caption)
                            .foregroundStyle(Color.white.opacity(AppOpacity.textSecondary))
                    }
                }
            }
            .aspectRatio(9 / 16, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .frame(maxWidth: 380, alignment: .center)

            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 10))
                Text("Safe areas at top and bottom are reserved for Instagram's UI")
                    .font(.system(size: 11))
            }
            .foregroundStyle(Color.white.opacity(AppOpacity.textQuaternary))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("APPEARANCE")
            Spacer()
            VStack(spacing: 12) {
                Picker("Accent", selection: $options.accent) {
                    ForEach(InstagramStoryCardOptions.Accent.allCases) { a in
                        HStack {
                            Circle()
                                .fill(a.swiftUIColor)
                                .frame(width: 12, height: 12)
                            Text(a.pickerTitle)
                        }
                        .tag(a)
                    }
                }
                .pickerStyle(.menu)
                .tint(AppColor.mango)
                .onChange(of: options.accent) { _, _ in
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }

                Toggle(
                    "Layered share (gradient + movable card)", isOn: $options.layeredShare
                )
                .tint(AppColor.mango)
                .onChange(of: options.layeredShare) { _, _ in
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            }
        }
        .padding(16)
        .background(Color.white.opacity(AppOpacity.cardBg))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(AppOpacity.cardBorder), lineWidth: 1)
        )
    }

    private var contentSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("CONTENT")
            Spacer()
            VStack(spacing: 12) {
                Toggle("Power / HR chart", isOn: $options.showPowerHRChart)
                    .onChange(of: options.showPowerHRChart) { _, _ in
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                Toggle("Heart rate line on chart", isOn: $options.showHeartRateLineOnChart)
                    .disabled(!options.showPowerHRChart)
                    .tint(options.showPowerHRChart ? AppColor.mango : Color.gray)
                Toggle("Detail line (cadence, route, …)", isOn: $options.showMetaLine)
                    .onChange(of: options.showMetaLine) { _, _ in
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                Toggle("NP · TSS · IF row", isOn: $options.showNPAndTSS)
                    .onChange(of: options.showNPAndTSS) { _, _ in
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                Toggle("Elevation on card", isOn: $options.showElevation)
                    .onChange(of: options.showElevation) { _, _ in
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                Toggle("Mangox footer", isOn: $options.showFooterBranding)
                    .onChange(of: options.showFooterBranding) { _, _ in
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
            }
        }
        .padding(16)
        .background(Color.white.opacity(AppOpacity.cardBg))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(AppOpacity.cardBorder), lineWidth: 1)
        )
    }

    private var captionSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                sectionLabel("CAPTION")
                Image(systemName: "apple.intelligence")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AppColor.mango)
                Spacer(minLength: 0)
                if isCaptionGenerating {
                    ProgressView()
                        .scaleEffect(0.7)
                        .tint(AppColor.mango)
                }
            }
            Spacer()

            if let caption = aiCaption {
                VStack(alignment: .leading, spacing: 10) {
                    Text(caption)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.white.opacity(0.88))
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
                            captionCopied ? "Copied!" : "Copy",
                            systemImage: captionCopied ? "checkmark" : "doc.on.doc"
                        )
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(captionCopied ? AppColor.mango : Color.white.opacity(0.6))
                    }
                }
            } else if !isCaptionGenerating {
                VStack(spacing: 6) {
                    Image(systemName: "text.bubble")
                        .font(.system(size: 20))
                        .foregroundStyle(Color.white.opacity(AppOpacity.textQuaternary))
                    Text("Caption will appear here once generated.")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.white.opacity(AppOpacity.textSecondary))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            }
        }
        .padding(16)
        .background(Color.white.opacity(AppOpacity.cardBg))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(AppOpacity.cardBorder), lineWidth: 1)
        )
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
        VStack(spacing: 0) {
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
                            .frame(width: 20, height: 20)
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
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                options = .default
                renderPreview()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 12, weight: .medium))
                    Text("Reset to defaults")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(Color.white.opacity(AppOpacity.textSecondary))
            }
            .padding(.top, 8)
        }
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(Color.white.opacity(AppOpacity.textTertiary))
            .tracking(1.5)
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
