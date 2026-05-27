import PhotosUI
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

    private let mango = AppColor.mango

    @State private var viewModel: SocialViewModel

    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showCustomizeSheet = false
    @State private var showCaptionSheet = false
    @State private var captionCopied = false
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
            return "Outdoor ride detected — route name shows when available."
        case .indoorTrainer:
            return "Indoor session detected — power and zones are highlighted."
        case .unknown:
            return "Session type unclear — defaults to zone-based card style."
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

    private func renderTemplateThumbnails() {
        viewModel.renderTemplateThumbnails(
            workout: workout,
            dominantZone: dominantZone,
            routeName: routeName,
            totalElevationGain: totalElevationGain,
            personalRecordNames: personalRecordNames
        )
    }

    var body: some View {
        ZStack {
            AppColor.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                canvas
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                bottomDeck
            }

            topToolbar
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .allowsHitTesting(true)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            viewModel.applySessionRecommendedOptionsIfDefault(
                workout: workout,
                routeName: routeName,
                totalElevationGain: totalElevationGain,
                personalRecordNames: personalRecordNames
            )
            if viewModel.previewImage == nil { renderPreviewImmediately() }
            renderTemplateThumbnails()
        }
        .onChange(of: viewModel.storyOptions) { _, _ in
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            schedulePreviewRenderDebounced()
        }
        .onChange(of: viewModel.aiTitle) { _, _ in
            renderPreviewImmediately()
        }
        .onChange(of: viewModel.customBackgroundImage) { _, _ in
            viewModel.invalidateTemplateThumbnails()
            renderTemplateThumbnails()
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
        .sheet(isPresented: binding(\.showShareFallback)) {
            ShareSheet(activityItems: viewModel.shareFallbackItems as [Any])
        }
        .sheet(isPresented: $showCustomizeSheet) {
            customizeSheet
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showCaptionSheet) {
            captionSheet
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                .preferredColorScheme(.dark)
        }
    }

    // MARK: - Canvas

    private var canvas: some View {
        GeometryReader { geo in
            ZStack {
                Color.black

                if let previewImage = viewModel.previewImage {
                    Image(uiImage: previewImage)
                        .resizable()
                        .scaledToFit()
                        .frame(
                            width: min(geo.size.width - 40, (geo.size.height - 36) * 9 / 16),
                            height: geo.size.height - 36
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .shadow(color: .black.opacity(0.45), radius: 18, x: 0, y: 10)
                } else if viewModel.isRendering {
                    ProgressView().tint(mango)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "photo")
                            .font(.system(size: 28))
                            .foregroundStyle(AppColor.fg3)
                        Text("Rendering preview…")
                            .font(.caption)
                            .foregroundStyle(AppColor.fg2)
                    }
                }

                if viewModel.isRendering && viewModel.previewImage != nil {
                    VStack {
                        HStack {
                            Spacer()
                            ProgressView()
                                .scaleEffect(0.7)
                                .tint(.white)
                                .padding(8)
                                .background(.ultraThinMaterial, in: Circle())
                                .padding(.top, 56)
                                .padding(.trailing, 16)
                        }
                        Spacer()
                    }
                }

                VStack {
                    Spacer()
                    sideRail
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.trailing, 14)
                        .padding(.bottom, 14)
                }

                VStack {
                    Spacer()
                    captionPill
                        .padding(.leading, 14)
                        .padding(.trailing, 72)
                        .padding(.bottom, 14)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Top toolbar

    private var topToolbar: some View {
        HStack {
            circularToolButton(systemName: "xmark", accessibilityLabel: "Close story studio") {
                InstagramStoryStudioPreferences.save(viewModel.storyOptions)
                onDismiss()
            }

            Spacer()

            accentSwatchButton

            circularToolButton(systemName: "ellipsis", accessibilityLabel: "Customize story") {
                showCustomizeSheet = true
            }
        }
    }

    private var accentSwatchButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            var opts = viewModel.storyOptions
            opts.accent = (opts.accent == .dominantZone) ? .brandMango : .dominantZone
            viewModel.saveStoryOptions(opts)
        } label: {
            Circle()
                .fill(viewModel.storyOptions.accent.color)
                .frame(width: 18, height: 18)
                .overlay(Circle().strokeBorder(Color.white.opacity(0.4), lineWidth: 1))
                .padding(11)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5))
        }
        .buttonStyle(MangoxPressStyle())
        .accessibilityLabel(A11yL10n.accentColor)
        .accessibilityValue(viewModel.storyOptions.accent.pickerTitle)
    }

    private func circularToolButton(
        systemName: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        }) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5))
        }
        .buttonStyle(MangoxPressStyle())
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: - Side rail

    private var sideRail: some View {
        let hasCustomBackgroundImage = viewModel.customBackgroundImage != nil

        return VStack(spacing: 10) {
            PhotosPicker(
                selection: $selectedPhotoItem,
                matching: .images,
                photoLibrary: .shared()
            ) {
                Image(systemName: hasCustomBackgroundImage ? "photo.fill" : "photo.badge.plus")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(hasCustomBackgroundImage ? mango : .white)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5))
            }
            .accessibilityLabel(hasCustomBackgroundImage ? "Change background photo" : "Add background photo")

            if hasCustomBackgroundImage {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    viewModel.customBackgroundImage = nil
                    selectedPhotoItem = nil
                    var opts = viewModel.storyOptions
                    if opts.backgroundSource == .custom { opts.backgroundSource = .preset }
                    viewModel.saveStoryOptions(opts)
                    renderPreviewImmediately()
                } label: {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color(red: 1.0, green: 0.45, blue: 0.45))
                        .frame(width: 44, height: 44)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay(Circle().strokeBorder(Color.red.opacity(0.32), lineWidth: 0.6))
                }
                .buttonStyle(MangoxPressStyle())
                .transition(.scale.combined(with: .opacity))
                .accessibilityLabel(A11yL10n.removeBackgroundPhoto)
            }

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                viewModel.aiTitle = nil
                viewModel.beginStoryCardTitleGenerationIfNeeded(
                    workout: workout,
                    dominantZoneName: dominantZone.name,
                    routeName: routeName,
                    totalElevationGain: totalElevationGain
                )
            } label: {
                Group {
                    if viewModel.isTitleGenerating {
                        ProgressView().scaleEffect(0.7).tint(.white)
                    } else {
                        Image(systemName: "sparkles")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5))
            }
            .buttonStyle(MangoxPressStyle())
            .disabled(viewModel.isTitleGenerating)
            .accessibilityLabel(A11yL10n.regenerateStoryTitle)

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                var opts = viewModel.storyOptions
                opts.showBrandBadge.toggle()
                viewModel.saveStoryOptions(opts)
            } label: {
                Image(systemName: viewModel.storyOptions.showBrandBadge ? "m.square.fill" : "m.square")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(viewModel.storyOptions.showBrandBadge ? mango : .white)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5))
            }
            .buttonStyle(MangoxPressStyle())
            .accessibilityLabel(A11yL10n.mangoxBrandBadge)
            .accessibilityValue(viewModel.storyOptions.showBrandBadge ? "Visible" : "Hidden")
        }
    }

    // MARK: - Caption pill

    private var captionPill: some View {
        Group {
            if viewModel.isCaptionGenerating {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.6).tint(.white)
                    Text("Writing caption…")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5))
            } else if let caption = viewModel.aiCaption, !caption.isEmpty {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showCaptionSheet = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "text.bubble.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(mango)
                        Text(captionPreviewSnippet(caption))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.white.opacity(0.5))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5))
                }
                .buttonStyle(MangoxPressStyle())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func captionPreviewSnippet(_ caption: String) -> String {
        let trimmed = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        let firstLine = trimmed.split(whereSeparator: \.isNewline).first.map(String.init) ?? trimmed
        if firstLine.count <= 50 { return firstLine }
        return String(firstLine.prefix(50)).trimmingCharacters(in: .whitespaces) + "…"
    }

    // MARK: - Bottom deck

    private var bottomDeck: some View {
        VStack(spacing: 12) {
            templateCarousel
            Text(viewModel.storyOptions.template.displayName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppColor.fg1)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .animation(MangoxMotion.exit, value: viewModel.storyOptions.template)
            shareButton
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 14)
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0), Color.black.opacity(0.6), Color.black],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var templateCarousel: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(InstagramStoryCardOptions.Template.allCases) { template in
                        templateThumb(template)
                            .id(template)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 4)
            }
            .onAppear {
                proxy.scrollTo(viewModel.storyOptions.template, anchor: .center)
            }
            .onChange(of: viewModel.storyOptions.template) { _, template in
                withAnimation(MangoxMotion.standard) {
                    proxy.scrollTo(template, anchor: .center)
                }
            }
        }
    }

    private func templateThumb(_ template: InstagramStoryCardOptions.Template) -> some View {
        let selected = viewModel.storyOptions.template == template
        let thumb = viewModel.templateThumbnails[template]
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            viewModel.applyTemplate(template)
        } label: {
            ZStack {
                if let thumb {
                    Image(uiImage: thumb)
                        .resizable()
                        .scaledToFill()
                } else {
                    LinearGradient(
                        colors: [Color.white.opacity(0.08), Color.white.opacity(0.03)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    ProgressView()
                        .scaleEffect(0.6)
                        .tint(AppColor.fg2)
                }
            }
            .frame(width: 64, height: 112)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        selected ? mango : Color.white.opacity(0.12),
                        lineWidth: selected ? 2 : 1
                    )
            )
            .shadow(color: selected ? mango.opacity(0.35) : .clear, radius: 6, x: 0, y: 2)
        }
        .buttonStyle(MangoxPressStyle())
        .accessibilityLabel(template.displayName)
    }

    private var shareButton: some View {
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
                        .frame(width: 18, height: 18)
                }
                Text(
                    viewModel.isSharing
                        ? (viewModel.storyOptions.carouselExport ? "Preparing slides…" : "Opening Instagram…")
                        : (viewModel.storyOptions.carouselExport ? "Export Story Carousel" : "Share to Instagram Stories")
                )
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 52)
            .padding(.vertical, 14)
            .background(
                Capsule().fill(Color(red: 0.88, green: 0.19, blue: 0.42))
            )
        }
        .buttonStyle(MangoxPressStyle())
        .disabled(viewModel.isSharing || viewModel.isRendering)
    }

    // MARK: - Customize sheet

    private var customizeSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    sheetSection(title: "Background") {
                        backgroundControls
                    }
                    sheetSection(title: "Style") {
                        styleControls
                    }
                    sheetSection(title: "Content") {
                        contentControls
                    }
                    sheetSection(title: "Stats") {
                        statSlotControls
                    }
                    sheetSection(title: "Privacy") {
                        privacyControls
                    }
                    sheetSection(title: "Sharing") {
                        sharingControls
                    }
                    resetButton
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .background(AppColor.bg)
            .navigationTitle("Customize")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showCustomizeSheet = false }
                        .foregroundStyle(mango)
                }
            }
        }
    }

    private func sheetSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            MangoxSectionLabel(title: title, horizontalPadding: 0)
            Spacer(minLength: 14)
            content()
        }
        .padding(16)
        .background(Color.white.opacity(AppOpacity.cardBg))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(AppOpacity.cardBorder), lineWidth: 1)
        )
    }

    private var backgroundControls: some View {
        VStack(spacing: 16) {
            ViewThatFits(in: .vertical) {
                Picker("Source", selection: optionBinding(\.backgroundSource)) {
                    ForEach(InstagramStoryCardOptions.BackgroundSource.allCases) { src in
                        Text(src.pickerTitle).tag(src)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Source", selection: optionBinding(\.backgroundSource)) {
                    ForEach(InstagramStoryCardOptions.BackgroundSource.allCases) { src in
                        Text(src.pickerTitle).tag(src)
                    }
                }
                .pickerStyle(.menu)
                .tint(mango)
            }
            .onChange(of: viewModel.storyOptions.backgroundSource) { _, _ in
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }

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
                                                    ? mango : Color.clear,
                                                lineWidth: 2
                                            )
                                    )

                                    Text(preset.displayName)
                                        .font(.system(size: 10, weight: .medium))
                                        .lineLimit(2)
                                        .multilineTextAlignment(.center)
                                        .foregroundStyle(
                                            viewModel.storyOptions.selectedPreset == preset
                                                ? mango
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

            if viewModel.storyOptions.backgroundSource == .custom {
                let hasCustomImage = viewModel.customBackgroundImage != nil
                let pickerTint = Color(red: 1.0, green: 0.70, blue: 0.10)
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
                    .foregroundStyle(pickerTint)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(pickerTint.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                if hasCustomImage {
                    Button(role: .destructive) {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        viewModel.customBackgroundImage = nil
                        selectedPhotoItem = nil
                        renderPreviewImmediately()
                    } label: {
                        Label("Remove Photo", systemImage: "trash.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color(red: 1.0, green: 0.42, blue: 0.42))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.red.opacity(0.10))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(Color.red.opacity(0.22), lineWidth: 1)
                            )
                    }
                }
            }
        }
    }

    private var styleControls: some View {
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
            .tint(mango)

            Picker("Style", selection: optionBinding(\.visualStyle)) {
                ForEach(InstagramStoryCardOptions.VisualStyle.allCases) { style in
                    Text(style.displayName).tag(style)
                }
            }
            .pickerStyle(.menu)
            .tint(mango)
        }
    }

    private var contentControls: some View {
        VStack(spacing: 12) {
            Toggle("Header chip + date", isOn: optionBinding(\.showHeader))
                .tint(mango)
            Toggle("Hero title", isOn: optionBinding(\.showHeroTitle))
                .tint(mango)
            Toggle("Route subtitle", isOn: optionBinding(\.showRouteName))
                .tint(viewModel.storyOptions.showHeroTitle ? mango : .gray)
                .disabled(!viewModel.storyOptions.showHeroTitle)
            Toggle("Training load highlight", isOn: optionBinding(\.showTrainingLoad))
                .tint(viewModel.storyOptions.showHeroTitle ? mango : .gray)
                .disabled(!viewModel.storyOptions.showHeroTitle)
            Toggle("WHOOP recovery on card", isOn: optionBinding(\.showWhoopReadiness))
                .tint(viewModel.storyOptions.showTrainingLoad ? mango : .gray)
                .disabled(!viewModel.storyOptions.showTrainingLoad)
            Toggle("Bottom performance cards", isOn: optionBinding(\.showSummaryCards))
                .tint(mango)
            Toggle("Quick stats row", isOn: optionBinding(\.showBottomStrip))
                .tint(mango)
            Toggle("Use Mangox brand badge", isOn: optionBinding(\.showBrandBadge))
                .tint(mango)
            Text(sessionKindFootnote)
                .font(.system(size: 11))
                .foregroundStyle(Color.white.opacity(0.38))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var statSlotControls: some View {
        VStack(spacing: 10) {
            ForEach(0..<4, id: \.self) { index in
                metricSlotMenu(index: index)
            }
        }
    }

    private func metricSlotMenu(index: Int) -> some View {
        let slots = normalizedQuickStatSlots()
        let selected = slots[index]
        return Menu {
            ForEach(InstagramStoryCardOptions.MetricSlot.allCases) { slot in
                Button(slot.displayName) {
                    var opts = viewModel.storyOptions
                    var updated = normalizedQuickStatSlots()
                    updated[index] = slot
                    opts.quickStatSlots = updated
                    viewModel.saveStoryOptions(opts)
                }
            }
        } label: {
            HStack {
                Text("Slot \(index + 1)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.58))
                Spacer()
                Text(selected.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.88))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(mango)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(Color.white.opacity(0.055))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private func normalizedQuickStatSlots() -> [InstagramStoryCardOptions.MetricSlot] {
        let defaults: [InstagramStoryCardOptions.MetricSlot] = [.heartRate, .cadence, .elevation, .speed]
        var slots = viewModel.storyOptions.quickStatSlots
        for fallback in defaults where slots.count < 4 {
            slots.append(fallback)
        }
        return Array(slots.prefix(4))
    }

    private var privacyControls: some View {
        VStack(spacing: 12) {
            Toggle("Hide route/location name", isOn: optionBinding(\.privacyHideRoute))
                .tint(mango)
            Toggle("Hide power numbers", isOn: optionBinding(\.privacyHidePower))
                .tint(mango)
            Toggle("Hide heart rate", isOn: optionBinding(\.privacyHideHeartRate))
                .tint(mango)
        }
    }

    private var sharingControls: some View {
        VStack(spacing: 12) {
            Toggle("Layered share (gradient + movable card)", isOn: optionBinding(\.layeredShare))
                .tint(mango)
            Toggle("Carousel export (3 slides)", isOn: optionBinding(\.carouselExport))
                .tint(mango)
        }
    }

    private var resetButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            viewModel.aiTitle = nil
            viewModel.customBackgroundImage = nil
            selectedPhotoItem = nil
            viewModel.resetStoryOptions()
            renderPreviewImmediately()
            renderTemplateThumbnails()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 12, weight: .medium))
                Text("Reset to defaults")
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(Color.white.opacity(AppOpacity.textSecondary))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Caption sheet

    private var captionSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 6) {
                        Image(systemName: "apple.intelligence")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(mango)
                        Text("AI caption")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AppColor.fg1)
                        Spacer()
                        if viewModel.isCaptionGenerating {
                            ProgressView().scaleEffect(0.7).tint(mango)
                        }
                    }

                    if let caption = viewModel.aiCaption {
                        Text(caption)
                            .font(.system(size: 15))
                            .foregroundStyle(AppColor.fg0)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)

                        if viewModel.instagramCaptionUsesStatsFallback {
                            Text(
                                "Suggested from your ride stats. On-device AI captions need Apple Intelligence on a supported device."
                            )
                            .font(.system(size: 11))
                            .foregroundStyle(AppColor.fg3)
                            .fixedSize(horizontal: false, vertical: true)
                        }

                        HStack(spacing: 10) {
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
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(captionCopied ? mango : .white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(
                                    Capsule().fill(Color.white.opacity(0.08))
                                )
                            }
                            .buttonStyle(MangoxPressStyle())

                            if OnDeviceCoachEngine.isOnDeviceWritingModelAvailable {
                                Button {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    viewModel.aiCaption = nil
                                    viewModel.instagramCaptionUsesStatsFallback = false
                                    viewModel.beginInstagramCaptionGenerationIfNeeded(
                                        workout: workout,
                                        dominantZoneName: dominantZone.name,
                                        routeName: routeName,
                                        ftpWatts: PowerZone.ftp,
                                        powerZoneLine: dominantZone.name
                                    )
                                } label: {
                                    Label("Regenerate", systemImage: "sparkles")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(mango)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(
                                            Capsule().fill(mango.opacity(0.12))
                                        )
                                }
                                .buttonStyle(MangoxPressStyle())
                                .disabled(viewModel.isCaptionGenerating)
                            }
                        }
                    } else if !viewModel.isCaptionGenerating {
                        Text(
                            OnDeviceCoachEngine.isOnDeviceWritingModelAvailable
                                ? "Caption will appear here once generated."
                                : "Captions are built from your ride stats on this device."
                        )
                        .font(.system(size: 13))
                        .foregroundStyle(AppColor.fg2)
                    }
                }
                .padding(20)
            }
            .background(AppColor.bg)
            .navigationTitle("Caption")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showCaptionSheet = false }
                        .foregroundStyle(mango)
                }
            }
        }
    }
}
