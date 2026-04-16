import Foundation

/// Legal document URLs from `Info.plist` (`MangoxPrivacyPolicyURL`, `MangoxTermsOfUseURL`).
/// Update those keys to your production HTTPS URLs before App Store submission.
enum MangoxLegalURLs {
    static var privacyPolicy: URL? { url(forInfoKey: "MangoxPrivacyPolicyURL") }
    static var termsOfUse: URL? { url(forInfoKey: "MangoxTermsOfUseURL") }

    private static func url(forInfoKey key: String) -> URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http"
        else { return nil }
        return url
    }
}
