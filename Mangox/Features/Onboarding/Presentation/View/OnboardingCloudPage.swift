import SwiftUI

/// Final onboarding step before "Get Started" — explains that cloud is optional
/// and offers email + OTP sign-in inline.
struct OnboardingCloudPage: View {
    @Environment(AuthState.self) private var auth
    @Environment(SyncCoordinator.self) private var sync
    let reduceMotion: Bool
    let onSkip: () -> Void
    let onSignedIn: () -> Void

    private enum Stage: Equatable {
        case intro
        case enterEmail
        case enterCode(email: String)
    }

    @State private var emailController = EmailSignInController()
    @State private var stage: Stage = .intro
    @State private var emailField: String = ""
    @State private var codeField: String = ""
    @State private var inFlight = false
    @State private var errorMessage: String?
    @State private var resendAvailableAt: Date?
    @State private var lastSubmittedCode: String?
    @FocusState private var focusedField: Field?

    private enum Field: Hashable { case email, code }

    var body: some View {
        GeometryReader { proxy in
            ScrollView(.vertical) {
                VStack(spacing: 24) {
                    Spacer(minLength: 0)

                    ZStack {
                        Circle()
                            .fill(AppColor.mango.opacity(0.08))
                            .frame(width: 160, height: 160)
                        Circle()
                            .fill(AppColor.mango.opacity(0.05))
                            .frame(width: 200, height: 200)
                        Image(systemName: "icloud")
                            .font(.system(size: 64, weight: .light))
                            .foregroundStyle(AppColor.mango)
                    }
                    .accessibilityHidden(true)

                    VStack(spacing: 12) {
                        Text("Cloud Backup (Optional)")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(AppColor.fg0)
                            .multilineTextAlignment(.center)

                        Text("Mangox works fully on this device — nothing leaves your phone unless you sign in. You can always turn this on later in Settings → Account.")
                            .font(.body)
                            .foregroundStyle(AppColor.fg2)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 32)
                    }

                    if auth.isSignedIn {
                        signedInBadge
                    } else {
                        signInArea
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(AppColor.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: proxy.size.height)
                .padding(.vertical, 24)
            }
        }
    }

    @ViewBuilder
    private var signInArea: some View {
        switch stage {
        case .intro:
            VStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 12) {
                    bullet(icon: "iphone", text: "Local-only by default — no account needed.")
                    bullet(icon: "icloud.and.arrow.up", text: "Sign in to back up rides, settings, and chats.")
                    bullet(icon: "lock.shield", text: "Only you can access your data.")
                }
                .padding(.horizontal, 36)

                Button {
                    stage = .enterEmail
                    focusedField = .email
                } label: {
                    Text("Sign in with Email")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(AppColor.bg)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(AppColor.mango)
                        .clipShape(RoundedRectangle(cornerRadius: MangoxRadius.card.rawValue, style: .continuous))
                }
                .buttonStyle(MangoxPressStyle())
                .padding(.horizontal, 32)
                .disabled(!MangoxSupabase.isConfigured)
            }
        case .enterEmail:
            emailEntryCard
        case .enterCode(let email):
            codeEntryCard(email: email)
        }
    }

    private var emailEntryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("EMAIL")
                .mangoxFont(.label)
                .foregroundStyle(AppColor.fg3)
                .tracking(1.1)

            TextField("you@example.com", text: $emailField)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focusedField, equals: .email)
                .submitLabel(.send)
                .onSubmit { Task { await sendCode() } }
                .font(.body.weight(.semibold))
                .foregroundStyle(AppColor.fg1)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(AppColor.hair)
                .clipShape(RoundedRectangle(cornerRadius: MangoxRadius.button.rawValue, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: MangoxRadius.button.rawValue, style: .continuous)
                        .strokeBorder(AppColor.hair2, lineWidth: 1)
                )

            Button {
                Task { await sendCode() }
            } label: {
                Text(inFlight ? "Sending…" : "Send Code")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(AppColor.bg)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(canSendCode ? AppColor.mango : AppColor.mango.opacity(0.4))
                    .clipShape(RoundedRectangle(cornerRadius: MangoxRadius.card.rawValue, style: .continuous))
            }
            .buttonStyle(MangoxPressStyle())
            .disabled(!canSendCode)

            Text("We'll email you a \(EmailSignInController.otpCodeLength)-digit code. No password needed.")
                .mangoxFont(.caption)
                .foregroundStyle(AppColor.fg3)
        }
        .padding(.horizontal, 32)
    }

    private func codeEntryCard(email: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Text("Code sent to")
                    .mangoxFont(.caption)
                    .foregroundStyle(AppColor.fg3)
                Text(email)
                    .mangoxFont(.caption)
                    .foregroundStyle(AppColor.fg1)
            }

            TextField(String(repeating: "0", count: EmailSignInController.otpCodeLength), text: $codeField)
                .textContentType(.oneTimeCode)
                .keyboardType(.numberPad)
                .focused($focusedField, equals: .code)
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppColor.fg1)
                .monospacedDigit()
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(AppColor.hair)
                .clipShape(RoundedRectangle(cornerRadius: MangoxRadius.button.rawValue, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: MangoxRadius.button.rawValue, style: .continuous)
                        .strokeBorder(AppColor.hair2, lineWidth: 1)
                )
                .onChange(of: codeField) { _, new in
                    let digits = new.filter(\.isNumber)
                    let trimmed = String(digits.prefix(EmailSignInController.otpCodeLength))
                    if trimmed != new { codeField = trimmed }
                    if trimmed.count < EmailSignInController.otpCodeLength {
                        lastSubmittedCode = nil
                    }
                    if trimmed.count == EmailSignInController.otpCodeLength,
                       trimmed != lastSubmittedCode {
                        Task { await verifyCode(email: email) }
                    }
                }

            HStack(spacing: 16) {
                Button {
                    stage = .enterEmail
                    codeField = ""
                    lastSubmittedCode = nil
                    errorMessage = nil
                    focusedField = .email
                } label: {
                    Text("Use a different email")
                        .mangoxFont(.caption)
                        .foregroundStyle(AppColor.fg2)
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    Task { await sendCode(resend: true) }
                } label: {
                    Text(resendButtonTitle)
                        .mangoxFont(.caption)
                        .foregroundStyle(canResendCode ? AppColor.mango : AppColor.fg3)
                }
                .buttonStyle(.plain)
                .disabled(!canResendCode)
            }
        }
        .padding(.horizontal, 32)
    }

    private var signedInBadge: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(AppColor.success)
            Text(auth.email.map { "Signed in as \($0)" } ?? "Signed in")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppColor.fg1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(AppColor.hair2)
        .clipShape(Capsule())
    }

    private func bullet(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppColor.mango)
                .frame(width: 22)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(AppColor.fg2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var canSendCode: Bool {
        !inFlight
            && MangoxSupabase.isConfigured
            && emailField.contains("@")
            && emailField.contains(".")
    }

    private var canResendCode: Bool {
        !inFlight && resendAvailableAt == nil
    }

    private var resendButtonTitle: String {
        guard let resendAvailableAt else {
            return inFlight ? "Sending…" : "Resend code"
        }

        let seconds = max(1, Int(ceil(resendAvailableAt.timeIntervalSinceNow)))
        return "Resend in \(seconds)s"
    }

    // MARK: - Actions

    private func sendCode(resend: Bool = false) async {
        guard !inFlight else { return }
        inFlight = true
        errorMessage = nil
        defer { inFlight = false }
        do {
            try await emailController.sendCode(to: emailField)
            beginResendCooldown()
            stage = .enterCode(email: EmailSignInController.normalizedEmail(emailField))
            codeField = ""
            lastSubmittedCode = nil
            if !resend { focusedField = .code }
        } catch let error as EmailSignInController.EmailSignInError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func verifyCode(email: String) async {
        guard !inFlight else { return }
        inFlight = true
        errorMessage = nil
        defer { inFlight = false }
        auth.setSigningIn()
        do {
            lastSubmittedCode = codeField
            _ = try await emailController.verify(email: email, code: codeField)
            // SyncCoordinator's auth listener triggers the first push automatically.
            // We still kick syncNow as a belt-and-braces hint for snappier feel.
            Task { await sync.syncNow() }
            HapticManager.shared.onboardingStepCompleted()
            onSignedIn()
        } catch let error as EmailSignInController.EmailSignInError {
            errorMessage = error.errorDescription
            auth.reportError(error)
        } catch {
            errorMessage = error.localizedDescription
            auth.reportError(error)
        }
    }

    private func beginResendCooldown() {
        let cooldown = EmailSignInController.resendCooldownSeconds
        resendAvailableAt = Date().addingTimeInterval(TimeInterval(cooldown))
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(cooldown))
            resendAvailableAt = nil
        }
    }
}
