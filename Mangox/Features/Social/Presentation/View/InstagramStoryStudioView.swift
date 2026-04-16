import PhotosUI
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
    @State private var viewModel: SocialViewModel

    @State private var captionCopied = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    /// Coalesces rapid toggle changes so we do not re-rasterize 1080×1920 on every `storyOptions` mutation.
    @State private var previewRenderTask: Task<Void, Never>?

    private var dominantZone: PowerZone {
        PowerZone.zone(for: Int(workout.avgPower.rounded()))
    }

    private var storySessionKind: InstagramStoryCardSessionKind {
        InstagramStoryCardSessionKind.resolve(
            workout: workout,
            routeName: routeName,
            totalElevationGain: totalElevationGain
        )
    }

    private var sessionKindFootnote: String {
        switch storySessionKind {
        case .outdoor:
            return "Outdoor (route, GPX/directions ride, elevation, or long road-like stats). Eyebrow: route if shown, else Outdoor cycling."
        case .indoorTrainer:
            return "Indoor-style. Unchanged factory options default the third quick stat to NP."
        case .unknown:
            return "Unclear session. Without route name, eyebrow uses your dominant zone."
        }
    }

    init(
        workout: Workout,
        routeName: String?,
        totalElevationGain: Double,
        personalRecordNames: [String],
        onDismiss: @escaping () -> Void,
        onShareError: @escaping (String) -> Void,
        viewModel: SocialViewModel
    ) {
        self.workout = workout
        self.routeName = routeName
        self.totalElevationGain = totalElevationGain
        self.personalRecordNames = personalRecordNames
        self.onDismiss = onDismiss
        self.onShareError = onShareError
        _viewModel = State(initialValue: viewModel)
    }

    private func binding<Value>(_ keyPath: ReferenceWritableKeyPath<SocialViewModel, Value>)
        -> Binding<Value>
    {
        Binding(
            get: { viewModel[keyPath: keyPath] },
            set: { viewModel[keyPath: keyPath] = $0 }
        )
    }

    private func optionBinding<Value>(_ keyPath: WritableKeyPath<InstagramStoryCardOptions, Value>)
        -> Binding<Value>
    {
        Binding(
            get: { viewModel.storyOptions[keyPath: keyPath] },
            set: {
                var options = viewModel.storyOptions
                options[keyPath: keyPath] = $0
                viewModel.saveStoryOptions(options)
            }
        )
    }

    private func schedulePreviewRenderDebounced() {
        previewRenderTask?.cancel()
        let w = workout
        let rn = routeName
        let elev = totalElevationGain
        let prs = personalRecordNames
        let dz = dominantZone
        previewRenderTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled else { return }
            await viewModel.renderPreview(
                workout: w,
                dominantZone: dz,
                routeName: rn,
                totalElevationGain: elev,
                personalRecordNames: prs
            )
        }
    }

    private func renderPreviewImmediately() {
        previewRenderTask?.cancel()
        let w = workout
        let rn = routeName
        let elev = totalElevationGain
        let prs = personalRecordNames
        let dz = dominantZone
        previewRenderTask = Task { @MainActor in
            await viewModel.renderPreview(
                workout: w,
                dominantZone: dz,
                routeName: rn,
                totalElevationGain: elev,
                personalRecordNames: prs
            )
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    storyPreview
                    backgroundSection
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
                        InstagramStoryStudioPreferences.save(viewModel.storyOptions)
                        onDismiss()
                    }
                    .foregroundStyle(Color.white.opacity(AppOpacity.textSecondary))
                }
            }
            .onAppear {
                viewModel.applySessionRecommendedOptionsIfDefault(
                    workout: workout,
                    routeName: routeName,
                    totalElevationGain: totalElevationGain
                )
                if viewModel.previewImage == nil { renderPreviewImmediately() }
            }
            .onChange(of: viewModel.storyOptions) { _, _ in
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                schedulePreviewRenderDebounced()
            }
            .onChange(of: viewModel.aiTitle) { _, _ in
                renderPreviewImmediately()
            }
            .onChange(of: selectedPhotoItem) { _, item in
                guard let item else { return }
                Task { @MainActor in
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let raw = UIImage(data: data)
                    {
                        let prepared = ImageProcessing.prepareStoryBackground(from: raw)
                        viewModel.customBackgroundImage = prepared
                        var opts = viewModel.storyOptions
                        opts.backgroundSource = .custom
                        viewModel.saveStoryOptions(opts)
                    }
                    renderPreviewImmediately()
                }
            }
            .task(id: workout.id) {
                viewModel.beginStoryCardTitleGenerationIfNeeded(
                    workout: workout,
                    dominantZoneName: dominantZone.name,
                    routeName: routeName,
                    totalElevationGain: totalElevationGain
                )
                viewModel.beginInstagramCaptionGenerationIfNeeded(
                    workout: workout,
                    dominantZoneName: dominantZone.name,
                    routeName: routeName,
                    ftpWatts: PowerZone.ftp,
                    powerZoneLine: dominantZone.name
                )
            }
            .preferredColorScheme(.dark)
            .sheet(isPresented: binding(\.showShareFallback)) {
                ShareSheet(activityItems: viewModel.shareFallbackItems as [Any])
            }
        }
    }

    // MARK: - Preview

    private var storyPreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("PREVIEW")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.white.opacity(AppOpacity.textTertiary))
                    .tracking(1.5)
                Spacer()
                if viewModel.isRendering {
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

                if let previewImage = viewModel.previewImage {
                    Image(uiImage: previewImage)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .padding(8)
                } else if viewModel.isRendering {
                    ProgressView().tint(AppColor.mango)
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

    // MARK: - Background section

    private var backgroundSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            MangoxSectionLabel(title: "Background", horizontalPadding: 0)
            Spacer(minLength: 14)
            VStack(spacing: 16) {

                // Source picker
                Picker("Source", selection: optionBinding(\.backgroundSource)) {
                    ForEach(InstagramStoryCardOptions.BackgroundSource.allCases) { src in
                        Text(src.pickerTitle).tag(src)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: viewModel.storyOptions.backgroundSource) { _, _ in
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }

                // Preset thumbnail strip
                if viewModel.storyOptions.backgroundSource == .preset {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(InstagramStoryCardOptions.StoryPreset.allCases) { preset in
                                Button {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    var opts = viewModel.storyOptions
                                    opts.selectedPreset = preset
                                    viewModel.saveStoryOptions(opts)
                                } label: {
                                    VStack(spacing: 6) {
                                        Group {
                                            if let img = UIImage(named: preset.assetName) {
                                                Image(uiImage: img)
                                                    .resizable()
                                                    .scaledToFill()
                                            } else {
                                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                    .fill(Color.white.opacity(0.08))
                                            }
                                        }
                                        .frame(width: 56, height: 100)
                                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                .strokeBorder(
                                                    viewModel.storyOptions.selectedPreset == preset
                                                        ? AppColor.mango : Color.clear,
                                                    lineWidth: 2
                                                )
                                        )

                                        Text(preset.displayName)
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundStyle(
                                                viewModel.storyOptions.selectedPreset == preset
                                                    ? AppColor.mango
                                                    : Color.white.opacity(0.50)
                                            )
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 2)
                        .padding(.vertical, 4)
                    }
                }

                // Photo picker button
                if viewModel.storyOptions.backgroundSource == .custom {
                    let hasCustomImage = viewModel.customBackgroundImage != nil
                    PhotosPicker(
                        selection: $selectedPhotoItem,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        Label(
                            hasCustomImage ? "Change Photo" : "Choose Photo",
                            systemImage: "photo.badge.plus"
                        )
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppColor.mango)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(AppColor.mango.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }

                    if viewModel.customBackgroundImage != nil {
                        Button(role: .destructive) {
                            viewModel.customBackgroundImage = nil
                            selectedPhotoItem = nil
                            renderPreviewImmediately()
                        } label: {
                            Label("Remove Photo", systemImage: "trash")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Color.red.opacity(0.8))
                        }
                    }
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

    // MARK: - Appearance section

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            MangoxSectionLabel(title: "Appearance", horizontalPadding: 0)
            Spacer(minLength: 14)
            VStack(spacing: 12) {
                Picker("Accent", selection: optionBinding(\.accent)) {
                    ForEach(InstagramStoryCardOptions.Accent.allCases) { a in
                        HStack {
                            Circle().fill(a.color).frame(width: 12, height: 12)
                            Text(a.pickerTitle)
                        }
                        .tag(a)
                    }
                }
                .pickerStyle(.menu)
                .tint(AppColor.mango)

                Toggle("Layered share (gradient + movable card)", isOn: optionBinding(\.layeredShare))
                    .tint(AppColor.mango)
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

    // MARK: - Content section

    private var contentSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            MangoxSectionLabel(title: "Content", horizontalPadding: 0)
            Spacer(minLength: 14)
            VStack(spacing: 12) {
                Toggle("Header chip + date", isOn: optionBinding(\.showHeader))
                    .tint(AppColor.mango)
                Toggle("Hero title", isOn: optionBinding(\.showHeroTitle))
                    .tint(AppColor.mango)
                Toggle("Route subtitle", isOn: optionBinding(\.showRouteName))
                    .tint(viewModel.storyOptions.showHeroTitle ? AppColor.mango : .gray)
                    .disabled(!viewModel.storyOptions.showHeroTitle)
                Toggle("Training load highlight", isOn: optionBinding(\.showTrainingLoad))
                    .tint(viewModel.storyOptions.showHeroTitle ? AppColor.mango : .gray)
                    .disabled(!viewModel.storyOptions.showHeroTitle)
                Toggle("WHOOP recovery on card", isOn: optionBinding(\.showWhoopReadiness))
                    .tint(viewModel.storyOptions.showTrainingLoad ? AppColor.mango : .gray)
                    .disabled(!viewModel.storyOptions.showTrainingLoad)
                Toggle("Bottom performance cards", isOn: optionBinding(\.showSummaryCards))
                    .tint(AppColor.mango)
                Toggle("Quick stats row", isOn: optionBinding(\.showBottomStrip))
                    .tint(AppColor.mango)
                Text(sessionKindFootnote)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.38))
                    .fixedSize(horizontal: false, vertical: true)
                Toggle("HR average", isOn: optionBinding(\.showQuickStatHeartRate))
                    .tint(viewModel.storyOptions.showBottomStrip ? AppColor.mango : .gray)
                    .disabled(!viewModel.storyOptions.showBottomStrip)
                Toggle("Cadence (RPM)", isOn: optionBinding(\.showQuickStatCadence))
                    .tint(viewModel.storyOptions.showBottomStrip ? AppColor.mango : .gray)
                    .disabled(!viewModel.storyOptions.showBottomStrip)
                Toggle("Third stat column", isOn: optionBinding(\.showQuickStatThird))
                    .tint(viewModel.storyOptions.showBottomStrip ? AppColor.mango : .gray)
                    .disabled(!viewModel.storyOptions.showBottomStrip)
                Toggle("Third column shows elevation (off = NP)", isOn: optionBinding(\.showElevation))
                    .tint(viewModel.storyOptions.showBottomStrip && viewModel.storyOptions.showQuickStatThird ? AppColor.mango : .gray)
                    .disabled(!viewModel.storyOptions.showBottomStrip || !viewModel.storyOptions.showQuickStatThird)
                Toggle("Average speed", isOn: optionBinding(\.showQuickStatSpeed))
                    .tint(viewModel.storyOptions.showBottomStrip ? AppColor.mango : .gray)
                    .disabled(!viewModel.storyOptions.showBottomStrip)
                Toggle("Use Mangox brand badge", isOn: optionBinding(\.showBrandBadge))
                    .tint(AppColor.mango)
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

    // MARK: - Caption section

    private var captionSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                MangoxSectionLabel(title: "Caption", horizontalPadding: 0)
                Image(systemName: "apple.intelligence")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AppColor.mango)
                Spacer(minLength: 0)
                if viewModel.isCaptionGenerating {
                    ProgressView().scaleEffect(0.7).tint(AppColor.mango)
                }
            }
            Spacer(minLength: 12)

            if let caption = viewModel.aiCaption {
                VStack(alignment: .leading, spacing: 10) {
                    Text(caption)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.white.opacity(0.88))
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)

                    if viewModel.instagramCaptionUsesStatsFallback {
                        Text(
                            "Suggested from your ride stats. On-device AI captions need Apple Intelligence on a supported device."
                        )
                        .font(.system(size: 10))
                        .foregroundStyle(Color.white.opacity(0.38))
                        .fixedSize(horizontal: false, vertical: true)
                    }

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
            } else if !viewModel.isCaptionGenerating {
                VStack(spacing: 6) {
                    Image(systemName: "text.bubble")
                        .font(.system(size: 20))
                        .foregroundStyle(Color.white.opacity(AppOpacity.textQuaternary))
                    Text(
                        OnDeviceCoachEngine.isOnDeviceWritingModelAvailable
                            ? "Caption will appear here once generated."
                            : "Captions are built from your ride stats on this device."
                    )
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(AppOpacity.textSecondary))
                    .multilineTextAlignment(.center)
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
    }

    // MARK: - Export section

    private var exportSection: some View {
        VStack(spacing: 0) {
            Button {
                Task {
                    await viewModel.shareToInstagram(
                        workout: workout,
                        dominantZone: dominantZone,
                        routeName: routeName,
                        totalElevationGain: totalElevationGain,
                        personalRecordNames: personalRecordNames,
                        onError: onShareError,
                        onDismiss: onDismiss
                    )
                }
            } label: {
                HStack(spacing: 10) {
                    if viewModel.isSharing {
                        ProgressView().tint(.white)
                    } else {
                        Image("BrandInstagram")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 20, height: 20)
                    }
                    Text(viewModel.isSharing ? "Opening Instagram..." : "Share to Instagram Stories")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.88, green: 0.19, blue: 0.42))
            .disabled(viewModel.isSharing || viewModel.isRendering)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                viewModel.customBackgroundImage = nil
                selectedPhotoItem = nil
                viewModel.resetStoryOptions()
                renderPreviewImmediately()
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
}
