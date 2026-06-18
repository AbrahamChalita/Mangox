// Features/Social/Presentation/View/DaySummaryStudioView.swift
import PhotosUI
import SwiftUI
import UIKit

struct DaySummaryStudioView: View {
    let date: Date
    let navigationPath: Binding<NavigationPath>

    private let mango = AppColor.mango

    @State private var viewModel: DaySummaryStudioViewModel
    @State private var showCustomizeSheet = false
    @State private var renderTask: Task<Void, Never>?
    @State private var shareError: String?
    @State private var successMessage: String?
    @State private var selectedPhotoItem: PhotosPickerItem?
    /// Namespace for Liquid Glass morphing of side-rail controls (e.g. the remove-photo button appearing/disappearing).
    @Namespace private var sideRailGlassNamespace

    init(date: Date, viewModel: DaySummaryStudioViewModel, navigationPath: Binding<NavigationPath>) {
        self.date = date
        self.navigationPath = navigationPath
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                canvas.frame(maxWidth: .infinity, maxHeight: .infinity)
                bottomDeck
            }

            topToolbar
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .allowsHitTesting(true)

            feedbackOverlay
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, 72)
                .padding(.horizontal, 16)
        }
        .preferredColorScheme(.dark)
        .navigationBarHidden(true)
        .onAppear {
            viewModel.load()
            scheduleRender(immediate: true)
        }
        .onChange(of: viewModel.cardOptions) { _, _ in
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            scheduleRender()
            viewModel.renderThumbnails()
        }
        .onChange(of: selectedPhotoItem) { _, item in
            guard let item else { return }
            Task { await loadSelectedPhoto(item) }
        }
        .sheet(isPresented: Binding(
            get: { viewModel.showShareFallback },
            set: { viewModel.showShareFallback = $0 }
        )) {
            ShareSheet(activityItems: viewModel.shareFallbackItems)
        }
        .sheet(isPresented: $showCustomizeSheet) {
            customizeSheet
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .preferredColorScheme(.dark)
        }
    }

    // MARK: - Render scheduling

    private func scheduleRender(immediate: Bool = false) {
        renderTask?.cancel()
        renderTask = Task { @MainActor in
            if !immediate {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
            }
            await viewModel.renderPreview()
            if immediate { viewModel.renderThumbnails() }
        }
    }

    // MARK: - Canvas

    private var canvas: some View {
        GeometryReader { geo in
            ZStack {
                Color.black

                if let img = viewModel.previewImage {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(
                            width: min(geo.size.width - 40, (geo.size.height - 36) * 9 / 16),
                            height: geo.size.height - 36
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .shadow(color: .black.opacity(0.45), radius: 18, x: 0, y: 10)
                } else {
                    ProgressView().tint(mango)
                }

                if viewModel.isRendering, viewModel.previewImage != nil {
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

                if viewModel.cardOptions.backgroundSource == .photo,
                   viewModel.customBackgroundImage == nil
                {
                    VStack(spacing: 8) {
                        Image(systemName: "photo.badge.plus")
                            .font(.title2)
                        Text("Choose a photo")
                            .font(MangoxFont.bodyBold.scaled())
                        Text("The photo is used only for this editing session.")
                            .font(MangoxFont.caption.scaled())
                            .foregroundStyle(AppColor.fg1)
                    }
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(18)
                    .background(Color.black.opacity(0.72), in: .rect(cornerRadius: 16))
                    .accessibilityElement(children: .combine)
                }

                VStack {
                    Spacer()
                    sideRail
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.trailing, 14)
                        .padding(.bottom, 14)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Top toolbar

    private var topToolbar: some View {
        GlassEffectContainer(spacing: 8) {
            HStack {
                circularButton(systemName: "xmark", label: "Close") {
                    navigationPath.wrappedValue.removeLast()
                }
                Spacer()
                circularButton(systemName: "square.and.arrow.down", label: "Save to Photos") {
                    Task { await saveStoryToPhotos() }
                }
                circularButton(systemName: "slider.horizontal.3", label: "Customize") {
                    showCustomizeSheet = true
                }
            }
        }
    }

    private func circularButton(systemName: String, label: String, action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .glassEffect(.regular.interactive(), in: .circle)
        }
        .buttonStyle(MangoxPressStyle())
        .accessibilityLabel(label)
    }

    // MARK: - Side rail

    private var sideRail: some View {
        let hasPhoto = viewModel.customBackgroundImage != nil
        let glassNamespace = sideRailGlassNamespace

        return GlassEffectContainer(spacing: 10) {
            VStack(spacing: 10) {
                // Photo picker
                PhotosPicker(
                    selection: $selectedPhotoItem,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    Image(systemName: hasPhoto ? "photo.fill" : "photo.badge.plus")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(hasPhoto ? mango : .white)
                        .frame(width: 44, height: 44)
                        .glassEffect(.regular.interactive(), in: .circle)
                        .glassEffectID("photos", in: glassNamespace)
                }
                .accessibilityLabel(hasPhoto ? "Change background photo" : "Add background photo")

                if hasPhoto {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        viewModel.customBackgroundImage = nil
                        selectedPhotoItem = nil
                        var opts = viewModel.cardOptions
                        opts.backgroundSource = .gradient
                        viewModel.saveOptions(opts)
                        viewModel.invalidateThumbnails()
                        scheduleRender(immediate: true)
                        viewModel.renderThumbnails()
                    } label: {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppColor.destructive)
                            .frame(width: 44, height: 44)
                            .glassEffect(.regular.tint(AppColor.destructive.opacity(0.22)).interactive(), in: .circle)
                            .glassEffectID("remove-photo", in: glassNamespace)
                    }
                    .buttonStyle(MangoxPressStyle())
                    .transition(.scale.combined(with: .opacity))
                    .accessibilityLabel(A11yL10n.removeBackgroundPhoto)
                }

                // Gradient scheme cycle (only when on gradient mode)
                if viewModel.cardOptions.backgroundSource == .gradient {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        var opts = viewModel.cardOptions
                        opts.backgroundGradientIndex = (opts.backgroundGradientIndex + 1) % 5
                        viewModel.saveOptions(opts)
                    } label: {
                        Circle()
                            .fill(gradientSwatchColor)
                            .frame(width: 18, height: 18)
                            .overlay(Circle().strokeBorder(Color.white.opacity(0.4), lineWidth: 1))
                            .padding(11)
                            .glassEffect(.regular.interactive(), in: .circle)
                            .glassEffectID("gradient-cycle", in: glassNamespace)
                    }
                    .buttonStyle(MangoxPressStyle())
                    .accessibilityLabel(A11yL10n.cycleBackgroundColor)
                }

                // Brand badge toggle
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    var opts = viewModel.cardOptions
                    opts.showBrandBadge.toggle()
                    viewModel.saveOptions(opts)
                } label: {
                    Image(systemName: viewModel.cardOptions.showBrandBadge ? "m.square.fill" : "m.square")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(viewModel.cardOptions.showBrandBadge ? mango : .white)
                        .frame(width: 44, height: 44)
                        .glassEffect(.regular.interactive(), in: .circle)
                        .glassEffectID("brand-badge", in: glassNamespace)
                }
                .buttonStyle(MangoxPressStyle())
                .accessibilityLabel(A11yL10n.brandBadge)
                .accessibilityValue(viewModel.cardOptions.showBrandBadge ? "Visible" : "Hidden")
            }
            .animation(MangoxMotion.exit, value: hasPhoto)
            .animation(MangoxMotion.exit, value: viewModel.cardOptions.backgroundSource)
        }
    }

    private var gradientSwatchColor: Color {
        let colors: [Color] = [mango, AppColor.blue, .green, .purple, .teal]
        let idx = min(viewModel.cardOptions.backgroundGradientIndex, colors.count - 1)
        return colors[idx]
    }

    // MARK: - Bottom deck

    private var bottomDeck: some View {
        VStack(spacing: 12) {
            templateCarousel
            Text(viewModel.cardOptions.template.displayName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppColor.fg1)
                .frame(maxWidth: .infinity)
                .animation(MangoxMotion.exit, value: viewModel.cardOptions.template)
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
                    ForEach(DaySummaryCardOptions.Template.allCases) { template in
                        templateThumb(template)
                            .id(template)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 4)
            }
            .onAppear {
                proxy.scrollTo(viewModel.cardOptions.template, anchor: .center)
            }
            .onChange(of: viewModel.cardOptions.template) { _, template in
                withAnimation(MangoxMotion.standard) {
                    proxy.scrollTo(template, anchor: .center)
                }
            }
        }
    }

    private func templateThumb(_ template: DaySummaryCardOptions.Template) -> some View {
        let selected = viewModel.cardOptions.template == template
        let thumb = viewModel.thumbnails[template]
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            var opts = viewModel.cardOptions
            opts.template = template
            viewModel.saveOptions(opts)
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
                    if viewModel.summary != nil {
                        ProgressView().scaleEffect(0.6).tint(AppColor.fg2)
                    }
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
                    onError: { shareError = $0 },
                    onDismiss: { navigationPath.wrappedValue.removeLast() }
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
                Text(viewModel.isSharing ? "Opening Instagram…" : "Share to Instagram Stories")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 52)
            .padding(.vertical, 14)
            .background(Capsule().fill(AppColor.instagram))
        }
        .buttonStyle(MangoxPressStyle())
        .disabled(viewModel.isSharing || viewModel.isRendering)
    }

    // MARK: - Customize sheet

    private var customizeSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    sheetSection(title: "Background") { backgroundSection }
                    sheetSection(title: "Stats") { statsSection }
                    sheetSection(title: "Privacy") { privacySection }
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

    private var backgroundSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Source", selection: optionBinding(\.backgroundSource)) {
                ForEach(DaySummaryCardOptions.BackgroundSource.allCases) { src in
                    Text(src.pickerTitle).tag(src)
                }
            }
            .pickerStyle(.segmented)

            if viewModel.cardOptions.backgroundSource == .gradient {
                Text("Gradient Theme")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppColor.fg2)
                HStack(spacing: 14) {
                    ForEach(0..<5, id: \.self) { idx in
                        let selected = viewModel.cardOptions.backgroundGradientIndex == idx
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            var opts = viewModel.cardOptions
                            opts.backgroundGradientIndex = idx
                            viewModel.saveOptions(opts)
                        } label: {
                            Circle()
                                .fill(gradientSwatchColors[idx])
                                .frame(width: 34, height: 34)
                                .overlay(
                                    Circle().strokeBorder(
                                        selected ? mango : Color.white.opacity(0.15),
                                        lineWidth: selected ? 2.5 : 1
                                    )
                                )
                                .shadow(color: selected ? mango.opacity(0.4) : .clear, radius: 5)
                        }
                        .buttonStyle(MangoxPressStyle())
                    }
                }
            } else {
                photoControls
            }
            Toggle("Show Mangox badge", isOn: optionBinding(\.showBrandBadge))
                .tint(mango)
        }
    }

    private var photoControls: some View {
        let hasPhoto = viewModel.customBackgroundImage != nil
        let pickerTint = mango
        return VStack(spacing: 10) {
            PhotosPicker(
                selection: $selectedPhotoItem,
                matching: .images,
                photoLibrary: .shared()
            ) {
                Label(hasPhoto ? "Change Photo" : "Choose Photo", systemImage: "photo.badge.plus")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(pickerTint)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(pickerTint.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            if hasPhoto {
                Button(role: .destructive) {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    viewModel.customBackgroundImage = nil
                    selectedPhotoItem = nil
                    var opts = viewModel.cardOptions
                    opts.backgroundSource = .gradient
                    viewModel.saveOptions(opts)
                    viewModel.invalidateThumbnails()
                    scheduleRender(immediate: true)
                    viewModel.renderThumbnails()
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
            } else {
                Text("Pictures from your day make stories pop — try one.")
                    .font(.system(size: 11))
                    .foregroundStyle(AppColor.fg3)
            }
        }
    }

    private var gradientSwatchColors: [Color] {
        [mango, AppColor.blue, .green, .purple, .teal]
    }

    private var statsSection: some View {
        VStack(spacing: 10) {
            ForEach(0..<3, id: \.self) { index in
                statSlotMenu(index: index)
            }
        }
    }

    private func statSlotMenu(index: Int) -> some View {
        let slots = normalizedStatSlots()
        let selected = slots[index]
        return Menu {
            ForEach(DaySummaryCardOptions.StatSlot.allCases) { slot in
                Button(slot.displayName) {
                    var opts = viewModel.cardOptions
                    var updated = normalizedStatSlots()
                    updated[index] = slot
                    opts.statSlots = updated
                    viewModel.saveOptions(opts)
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

    private func normalizedStatSlots() -> [DaySummaryCardOptions.StatSlot] {
        let defaults: [DaySummaryCardOptions.StatSlot] = [.totalTime, .totalDistance, .totalKJ]
        var slots = viewModel.cardOptions.statSlots
        for fallback in defaults where slots.count < 3 { slots.append(fallback) }
        return Array(slots.prefix(3))
    }

    private var privacySection: some View {
        VStack(spacing: 12) {
            Toggle("Hide power / energy", isOn: optionBinding(\.privacyHidePower))
                .tint(mango)
            Toggle("Hide heart rate", isOn: optionBinding(\.privacyHideHeartRate))
                .tint(mango)
            Toggle("Hide strength load details", isOn: optionBinding(\.privacyHideStrengthLoad))
                .tint(mango)
        }
    }

    private var resetButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            selectedPhotoItem = nil
            viewModel.resetOptions()
            scheduleRender(immediate: true)
            viewModel.renderThumbnails()
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

    // MARK: - Binding helpers

    private func optionBinding<Value>(_ keyPath: WritableKeyPath<DaySummaryCardOptions, Value>) -> Binding<Value> {
        Binding(
            get: { viewModel.cardOptions[keyPath: keyPath] },
            set: {
                var opts = viewModel.cardOptions
                opts[keyPath: keyPath] = $0
                viewModel.saveOptions(opts)
            }
        )
    }

    @ViewBuilder
    private var feedbackOverlay: some View {
        if let shareError {
            MangoxErrorBanner(
                message: shareError,
                severity: .error,
                onDismiss: { self.shareError = nil }
            )
        } else if let successMessage {
            MangoxErrorBanner(
                message: successMessage,
                severity: .info,
                onDismiss: { self.successMessage = nil }
            )
        }
    }

    @MainActor
    private func loadSelectedPhoto(_ item: PhotosPickerItem) async {
        defer { selectedPhotoItem = nil }
        shareError = nil
        do {
            viewModel.customBackgroundImage = try await StoryMediaService.loadStoryBackground(from: item)
            var options = viewModel.cardOptions
            options.backgroundSource = .photo
            viewModel.saveOptions(options)
            scheduleRender(immediate: true)
            viewModel.renderThumbnails()
            presentSuccess("Photo background added.")
        } catch is CancellationError {
            return
        } catch {
            shareError = error.localizedDescription
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    @MainActor
    private func saveStoryToPhotos() async {
        shareError = nil
        do {
            try await viewModel.saveToPhotos()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            presentSuccess("Day Story saved to Photos.")
        } catch {
            shareError = error.localizedDescription
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    @MainActor
    private func presentSuccess(_ message: String) {
        successMessage = message
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            if successMessage == message {
                successMessage = nil
            }
        }
    }
}
