import SwiftUI

/// Account & cloud backup settings.
///
/// Signed-out: explains local-first, runs the email + OTP sign-in flow.
/// Signed-in: shows email, last backup, sign-out, manual "Back Up Now".
struct AccountView: View {
    @Environment(AuthState.self) private var auth
    @Environment(SyncCoordinator.self) private var sync

    private enum SignInStage: Equatable {
        case enterEmail
        case enterCode(email: String)
    }

    @State private var emailController = EmailSignInController()
    @State private var stage: SignInStage = .enterEmail
    @State private var emailField: String = ""
    @State private var codeField: String = ""
    @State private var inFlight = false
    @State private var localError: String?
    @State private var resendAvailableAt: Date?
    @State private var lastSubmittedCode: String?
    @State private var showingSignOutConfirm = false
    @FocusState private var focusedField: Field?

    private enum Field: Hashable { case email, code }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                if auth.isSignedIn {
                    signedInContent
                } else {
                    signedOutContent
                }

                if let pending = displayedError {
                    Text(pending)
                        .mangoxFont(.caption)
                        .foregroundStyle(AppColor.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, MangoxSpacing.page)
                }
            }
            .padding(.vertical, 16)
        }
        .scrollIndicators(.hidden)
        .background(AppColor.bg.ignoresSafeArea())
        .navigationTitle("Account & Cloud")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Sign out of Mangox?",
            isPresented: $showingSignOutConfirm,
            titleVisibility: .visible
        ) {
            Button("Sign Out", role: .destructive) {
                Task { await sync.signOut() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your local data stays on this device. Cloud data is preserved and will be available when you sign back in.")
        }
    }

    private var displayedError: String? {
        localError ?? auth.pendingError
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Cloud Backup")
                .mangoxFont(.label)
                .foregroundStyle(AppColor.fg3)
                .tracking(1.1)

            Text(auth.isSignedIn
                 ? "Your rides, settings, and coach chats are backed up to your account."
                 : "Mangox works fully on this device. Sign in to back up your data to your account.")
                .mangoxFont(.body)
                .foregroundStyle(AppColor.fg1)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, MangoxSpacing.page)
    }

    // MARK: - Signed out

    private var signedOutContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                bullet(icon: "iphone", text: "Everything you've recorded so far is stored on this device.")
                bullet(icon: "icloud.and.arrow.up", text: "Sign in to back up current data to the cloud on your next upload.")
                bullet(icon: "lock.shield", text: "Only you can read your data; access is enforced by row-level security.")
            }
            .padding(.horizontal, MangoxSpacing.page)

            switch stage {
            case .enterEmail:
                emailEntryCard
            case .enterCode(let email):
                codeEntryCard(email: email)
            }

            if !MangoxSupabase.isConfigured {
                Text("Cloud sync isn't configured in this build. Add SUPABASE_URL_HOST and SUPABASE_PUBLISHABLE_KEY to Config/Secrets.xcconfig.")
                    .mangoxFont(.caption)
                    .foregroundStyle(AppColor.fg3)
                    .padding(.horizontal, MangoxSpacing.page)
            }
        }
    }

    // Stage 1 — enter email
    private var emailEntryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Email")
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
                .mangoxFont(.bodyBold)
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
                    .mangoxFont(.bodyBold)
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
        .padding(.horizontal, MangoxSpacing.page)
    }

    // Stage 2 — enter the OTP
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
                .mangoxFont(.bodyBold)
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

            Button {
                Task { await verifyCode(email: email) }
            } label: {
                Text(inFlight ? "Verifying…" : "Verify & Sign In")
                    .mangoxFont(.bodyBold)
                    .foregroundStyle(AppColor.bg)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(canVerify ? AppColor.mango : AppColor.mango.opacity(0.4))
                    .clipShape(RoundedRectangle(cornerRadius: MangoxRadius.card.rawValue, style: .continuous))
            }
            .buttonStyle(MangoxPressStyle())
            .disabled(!canVerify)

            HStack(spacing: 16) {
                Button {
                    stage = .enterEmail
                    codeField = ""
                    lastSubmittedCode = nil
                    localError = nil
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
        .padding(.horizontal, MangoxSpacing.page)
    }

    private var canSendCode: Bool {
        !inFlight
            && MangoxSupabase.isConfigured
            && emailField.contains("@")
            && emailField.contains(".")
    }

    private var canVerify: Bool {
        !inFlight && codeField.count == EmailSignInController.otpCodeLength
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

    private func bullet(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppColor.mango)
                .frame(width: 22)
            Text(text)
                .mangoxFont(.callout)
                .foregroundStyle(AppColor.fg1)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Signed in

    private var signedInContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Label(auth.email ?? "Signed in", systemImage: "envelope.fill")
                    .mangoxFont(.bodyBold)
                    .foregroundStyle(AppColor.fg1)
                Text(lastSyncedSummary)
                    .mangoxFont(.caption)
                    .foregroundStyle(AppColor.fg3)
            }
            .padding(.horizontal, MangoxSpacing.page)

            VStack(spacing: 0) {
                Button {
                    Task { await sync.syncNow() }
                } label: {
                    syncRow
                }
                .buttonStyle(.plain)
                .disabled(sync.state == .running)

                Divider().background(AppColor.hair).padding(.leading, 60)

                Button(role: .destructive) {
                    showingSignOutConfirm = true
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .frame(width: 28, height: 28)
                            .foregroundStyle(AppColor.red)
                        Text("Sign Out")
                            .mangoxFont(.bodyBold)
                            .foregroundStyle(AppColor.red)
                        Spacer()
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                }
                .buttonStyle(.plain)
            }
            .cardStyle(cornerRadius: MangoxRadius.sharp.rawValue)
            .padding(.horizontal, MangoxSpacing.page)
        }
    }

    @ViewBuilder
    private var syncRow: some View {
        HStack(spacing: 14) {
            Image(systemName: sync.state == .running ? "arrow.triangle.2.circlepath" : "icloud.and.arrow.up")
                .frame(width: 28, height: 28)
                .foregroundStyle(AppColor.mango)
            VStack(alignment: .leading, spacing: 2) {
                Text(sync.state == .running ? "Backing up…" : "Back Up Now")
                    .mangoxFont(.bodyBold)
                    .foregroundStyle(AppColor.fg1)
                if case .error(let message) = sync.state {
                    Text(message)
                        .mangoxFont(.caption)
                        .foregroundStyle(AppColor.red)
                        .lineLimit(2)
                }
            }
            Spacer()
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
    }

    private var lastSyncedSummary: String {
        guard let last = sync.lastSyncedAt ?? auth.lastSyncedAt else { return "Not yet backed up." }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return "Last backed up \(formatter.localizedString(for: last, relativeTo: .now))."
    }

    // MARK: - Actions

    private func sendCode(resend: Bool = false) async {
        guard !inFlight else { return }
        inFlight = true
        localError = nil
        defer { inFlight = false }
        do {
            try await emailController.sendCode(to: emailField)
            beginResendCooldown()
            stage = .enterCode(email: EmailSignInController.normalizedEmail(emailField))
            codeField = ""
            lastSubmittedCode = nil
            if !resend { focusedField = .code }
        } catch let error as EmailSignInController.EmailSignInError {
            localError = error.errorDescription
        } catch {
            localError = error.localizedDescription
        }
    }

    private func verifyCode(email: String) async {
        guard !inFlight else { return }
        inFlight = true
        localError = nil
        defer { inFlight = false }
        auth.setSigningIn()
        do {
            lastSubmittedCode = codeField
            _ = try await emailController.verify(email: email, code: codeField)
            // AuthState picks up the new session; SyncCoordinator triggers a push.
            stage = .enterEmail
            emailField = ""
            codeField = ""
            lastSubmittedCode = nil
        } catch let error as EmailSignInController.EmailSignInError {
            localError = error.errorDescription
            auth.reportError(error)
        } catch {
            localError = error.localizedDescription
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
