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

    private var dominantZone: PowerZone {
        PowerZone.zone(for: Int(workout.avgPower.rounded()))
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
                        InstagramStoryStudioPreferences.save(viewModel.storyOptions)
                        onDismiss()
                    }
                    .foregroundStyle(Color.white.opacity(AppOpacity.textSecondary))
                }
            }
            .onAppear {
                if viewModel.previewImage == nil {
                    Task {
                        await viewModel.renderPreview(
                            workout: workout,
                            dominantZone: dominantZone,
                            routeName: routeName,
                            totalElevationGain: totalElevationGain,
                            personalRecordNames: personalRecordNames
                        )
                    }
                }
            }
            .onChange(of: viewModel.storyOptions) { _, newValue in
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                viewModel.saveStoryOptions(newValue)
                Task {
                    await viewModel.renderPreview(
                        workout: workout,
                        dominantZone: dominantZone,
                        routeName: routeName,
                        totalElevationGain: totalElevationGain,
                        personalRecordNames: personalRecordNames
                    )
                }
            }
            .onChange(of: viewModel.aiTitle) { _, _ in
                Task {
                    await viewModel.renderPreview(
                        workout: workout,
                        dominantZone: dominantZone,
                        routeName: routeName,
                        totalElevationGain: totalElevationGain,
                        personalRecordNames: personalRecordNames
                    )
                }
            }
            .task {
                await viewModel.generateTitle(
                    workout: workout,
                    dominantZoneName: dominantZone.name,
                    routeName: routeName,
                    totalElevationGain: totalElevationGain
                )
            }
            .preferredColorScheme(.dark)
            .sheet(isPresented: binding(\.showShareFallback)) {
                ShareSheet(activityItems: viewModel.shareFallbackItems as [Any])
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
            MangoxSectionLabel(title: "Appearance", horizontalPadding: 0)
            Spacer()
            VStack(spacing: 12) {
                Picker("Accent", selection: optionBinding(\.accent)) {
                    ForEach(InstagramStoryCardOptions.Accent.allCases) { a in
                        HStack {
                            Circle()
                                .fill(a.color)
                                .frame(width: 12, height: 12)
                            Text(a.pickerTitle)
                        }
                        .tag(a)
                    }
                }
                .pickerStyle(.menu)
                .tint(AppColor.mango)
                .onChange(of: viewModel.storyOptions.accent) { _, _ in
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }

                Toggle(
                    "Layered share (gradient + movable card)", isOn: optionBinding(\.layeredShare)
                )
                .tint(AppColor.mango)
                .onChange(of: viewModel.storyOptions.layeredShare) { _, _ in
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
            MangoxSectionLabel(title: "Content", horizontalPadding: 0)
            Spacer()
            VStack(spacing: 12) {
                Toggle("Power / HR chart", isOn: optionBinding(\.showPowerHRChart))
                    .onChange(of: viewModel.storyOptions.showPowerHRChart) { _, _ in
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                Toggle("Heart rate line on chart", isOn: optionBinding(\.showHeartRateLineOnChart))
                    .disabled(!viewModel.storyOptions.showPowerHRChart)
                    .tint(viewModel.storyOptions.showPowerHRChart ? AppColor.mango : Color.gray)
                Toggle("Detail line (cadence, route, …)", isOn: optionBinding(\.showMetaLine))
                    .onChange(of: viewModel.storyOptions.showMetaLine) { _, _ in
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                Toggle("NP · TSS · IF row", isOn: optionBinding(\.showNPAndTSS))
                    .onChange(of: viewModel.storyOptions.showNPAndTSS) { _, _ in
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                Toggle("Elevation on card", isOn: optionBinding(\.showElevation))
                    .onChange(of: viewModel.storyOptions.showElevation) { _, _ in
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                Toggle("Mangox footer", isOn: optionBinding(\.showFooterBranding))
                    .onChange(of: viewModel.storyOptions.showFooterBranding) { _, _ in
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
                MangoxSectionLabel(title: "Caption", horizontalPadding: 0)
                Image(systemName: "apple.intelligence")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AppColor.mango)
                Spacer(minLength: 0)
                if viewModel.isCaptionGenerating {
                    ProgressView()
                        .scaleEffect(0.7)
                        .tint(AppColor.mango)
                }
            }
            Spacer()

            if let caption = viewModel.aiCaption {
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
            } else if !viewModel.isCaptionGenerating {
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
            await viewModel.generateCaption(
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
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image("BrandInstagram")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 20, height: 20)
                    }
                    Text(
                        viewModel.isSharing ? "Opening Instagram..." : "Share to Instagram Stories"
                    )
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
            .disabled(viewModel.isSharing || viewModel.isRendering)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                viewModel.resetStoryOptions()
                Task {
                    await viewModel.renderPreview(
                        workout: workout,
                        dominantZone: dominantZone,
                        routeName: routeName,
                        totalElevationGain: totalElevationGain,
                        personalRecordNames: personalRecordNames
                    )
                }
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
