import PhotosUI
import SwiftUI

struct CoachInputBarWrapper: View {
    @Binding var navigationPath: NavigationPath
    @Binding var chatSheetPresented: Bool
    @Binding var auxiliarySheet: CoachAuxiliarySheet?
    let showComposerLimitBanner: Bool
    let onPlanBuilder: () -> Void
    let sendAction: (String, CoachUserImageAttachment?) -> Bool
    let onFocusChanged: (Bool) -> Void

    @State private var inputText = ""
    @State private var attachedImage: CoachUserImageAttachment?
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var hasAttachedPhoto = false
    @FocusState private var inputFocused: Bool

    var body: some View {
        InputBarView(
            navigationPath: $navigationPath,
            chatSheetPresented: $chatSheetPresented,
            auxiliarySheet: $auxiliarySheet,
            inputText: $inputText,
            attachedImage: $attachedImage,
            photoPickerItem: $photoPickerItem,
            hasAttachedPhoto: $hasAttachedPhoto,
            inputFocused: _inputFocused,
            showComposerLimitBanner: showComposerLimitBanner,
            onPlanBuilder: onPlanBuilder,
            sendAction: { text in
                let wasFocused = inputFocused
                let image = attachedImage
                let accepted = sendAction(text, image)
                guard accepted else { return false }
                inputText = ""
                attachedImage = nil
                photoPickerItem = nil
                hasAttachedPhoto = false
                if wasFocused {
                    inputFocused = true
                }
                return true
            }
        )
        // Removed `ToolbarItemGroup(placement: .keyboard)`. The system toolbar adds
        // ~44pt above the keyboard that the ScrollView's safeAreaInset doesn't
        // account for, so the last bubble could hide under it. Send is already
        // inline; long-press on the TextField still surfaces Paste; interactive
        // drag dismisses the keyboard.
        .onChange(of: inputFocused) { _, focused in
            onFocusChanged(focused)
        }
    }
}

private struct InputBarView: View {
    @Environment(CoachViewModel.self) private var coachViewModel
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    @Binding var navigationPath: NavigationPath
    @Binding var chatSheetPresented: Bool
    @Binding var auxiliarySheet: CoachAuxiliarySheet?
    @Binding var inputText: String
    @Binding var attachedImage: CoachUserImageAttachment?
    @Binding var photoPickerItem: PhotosPickerItem?
    @Binding var hasAttachedPhoto: Bool
    @FocusState var inputFocused: Bool
    let showComposerLimitBanner: Bool
    let onPlanBuilder: () -> Void
    let sendAction: (String) -> Bool

    var body: some View {
        @Bindable var coach = coachViewModel

        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        let passesCoachLimit = coach.canSendCoachMessage(
            trimmed,
            isPro: coach.isPro,
            hasImage: hasAttachedPhoto
        )
        let canSend =
            (!trimmed.isEmpty || hasAttachedPhoto)
            && !coach.isLoading
            && passesCoachLimit
        let sendButtonHint: String = {
            if !passesCoachLimit {
                return "Cloud coach limit reached. Upgrade for live web search, or keep using on-device stats and Private Cloud."
            }
            if coach.isLoading {
                return "Coach is replying. Wait for the response to finish."
            }
            if trimmed.isEmpty {
                return "Type a message to enable send."
            }
            return ""
        }()

        VStack(spacing: 0) {
            if let draft = coach.planConfirmationDraft {
                CoachPlanConfirmBanner(draft: draft, navigationPath: $navigationPath)
                    .padding(.horizontal, 14)
                    .padding(.top, 8)
                    .padding(.bottom, 6)
            } else if let draft = coach.workoutConfirmationDraft {
                CoachWorkoutConfirmBanner(draft: draft)
                    .padding(.horizontal, 14)
                    .padding(.top, 8)
                    .padding(.bottom, 6)
            } else if let celeb = coach.planSaveCelebration {
                CoachPlanSuccessBanner(
                    celebration: celeb,
                    navigationPath: $navigationPath,
                    dismissChat: { chatSheetPresented = false }
                )
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, 6)
            } else if let celeb = coach.workoutSaveCelebration {
                CoachWorkoutSuccessBanner(
                    celebration: celeb,
                    navigationPath: $navigationPath,
                    dismissChat: { chatSheetPresented = false }
                )
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, 6)
            }

            if showComposerLimitBanner {
                Button {
                    auxiliarySheet = .paywall
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Image(systemName: "cloud.fill")
                                .font(.system(size: 11, weight: .semibold))
                            Text("Cloud coach limit reached")
                                .font(.system(size: 12, weight: .semibold))
                            Spacer(minLength: 0)
                            Text("Upgrade")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(AppColor.mango.opacity(0.95))
                        }
                        Text("On-device stats and Private Cloud still work — cloud web search needs Mangox Cloud.")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.42))
                            .multilineTextAlignment(.leading)
                    }
                    .foregroundStyle(AppColor.mango.opacity(0.92))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(AppColor.mango.opacity(0.08))
                }
                .buttonStyle(.plain)
                .accessibilityHint(A11yL10n.opensSubscriptionHint)
                .transition(
                    accessibilityReduceMotion
                        ? .opacity
                        : .move(edge: .bottom).combined(with: .opacity)
                )
            }

            if let errorMessage = coach.error, !errorMessage.isEmpty {
                MangoxErrorBanner(
                    message: errorMessage,
                    severity: .error,
                    layout: .inlineStrip,
                    onDismiss: { coach.dismissError() }
                )
                .transition(
                    accessibilityReduceMotion
                        ? .opacity
                        : .move(edge: .bottom).combined(with: .opacity)
                )
            }

            if hasAttachedPhoto {
                HStack(spacing: 10) {
                    if let image = attachedImage?.uiImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 52, height: 52)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    Text("Photo attached")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.72))
                    Spacer(minLength: 0)
                    Button {
                        attachedImage = nil
                        photoPickerItem = nil
                        hasAttachedPhoto = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(.white.opacity(0.45))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove photo")
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }

            HStack(alignment: .bottom, spacing: 10) {
                Button(action: onPlanBuilder) {
                    Image(systemName: "calendar.badge.plus")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(AppColor.mango.opacity(0.9))
                        .frame(width: 44, height: 44)
                        .background(AppColor.bg2)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(AppColor.mango.opacity(0.28), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(A11yL10n.planBuilder)
                .disabled(coach.isLoading)

                CoachAttachPhotoPicker(
                    photoPickerItem: $photoPickerItem,
                    attachedImage: $attachedImage,
                    hasAttachedPhoto: $hasAttachedPhoto,
                    isDisabled: coach.isLoading
                )

                TextField(
                    "Message",
                    text: $inputText,
                    prompt: Text("Message").foregroundStyle(AppColor.fg3),
                    axis: .vertical
                )
                .font(.body)
                .foregroundStyle(.white)
                .tint(AppColor.mango)
                .textInputAutocapitalization(.sentences)
                .textContentType(.none)
                .lineLimit(1...6)
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .background(inputFocused ? AppColor.bg2 : AppColor.bg1)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(
                            inputFocused ? AppColor.mango.opacity(0.35) : AppColor.hair2,
                            lineWidth: 1
                        )
                )
                .focused($inputFocused)
                .submitLabel(.send)
                .accessibilityLabel(A11yL10n.messageInput)
                .onSubmit { _ = sendAction(inputText) }

                Button {
                    _ = sendAction(inputText)
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(canSend ? AppColor.bg0 : AppColor.fg3)
                        .frame(width: 44, height: 44)
                        .background(canSend ? AppColor.mango : AppColor.bg2)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(canSend ? AppColor.mango.opacity(0.45) : AppColor.hair2, lineWidth: 1)
                        )
                }
                .buttonStyle(MangoxPressStyle())
                .disabled(!canSend)
                .accessibilityLabel(coach.isLoading ? "Sending message" : "Send message")
                .accessibilityHintIf(sendButtonHint)
                .animation(
                    accessibilityReduceMotion ? .easeInOut(duration: 0.12) : .smooth(duration: 0.22),
                    value: canSend
                )
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(AppColor.bg.opacity(0.94))
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(AppColor.hair)
                    .frame(height: 1)
            }
        }
    }
}

private struct CoachPhotoPickerLabel: View {
    let hasAttachedPhoto: Bool

    var body: some View {
            Image(systemName: "photo.on.rectangle")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(AppColor.mango.opacity(hasAttachedPhoto ? 1 : 0.9))
                .frame(width: 44, height: 44)
                .background(AppColor.bg2)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        hasAttachedPhoto
                            ? AppColor.mango.opacity(0.55) : AppColor.mango.opacity(0.28),
                        lineWidth: 1
                    )
            )
    }
}

private struct CoachAttachPhotoPicker: View {
    @Binding var photoPickerItem: PhotosPickerItem?
    @Binding var attachedImage: CoachUserImageAttachment?
    @Binding var hasAttachedPhoto: Bool
    let isDisabled: Bool

    var body: some View {
        let attached = hasAttachedPhoto
        PhotosPicker(selection: $photoPickerItem, matching: .images) {
            CoachPhotoPickerLabel(hasAttachedPhoto: attached)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityLabel("Attach photo")
        .onChange(of: photoPickerItem) { _, item in
            guard let item else { return }
            Task {
                do {
                    guard let data = try await item.loadTransferable(type: Data.self) else {
                        throw PhotoPickerError.noData
                    }
                    guard let uiImage = UIImage(data: data) else {
                        throw PhotoPickerError.invalidImage
                    }
                    guard let attachment = CoachUserImageAttachment.fromUIImage(uiImage) else {
                        throw PhotoPickerError.unsupportedFormat
                    }
                    await MainActor.run {
                        attachedImage = attachment
                        hasAttachedPhoto = true
                    }
                } catch {
                    await MainActor.run {
                        photoPickerItem = nil
                        hasAttachedPhoto = false
                    }
                }
            }
        }
    }
}

private enum PhotoPickerError: Error {
    case noData
    case invalidImage
    case unsupportedFormat
}
