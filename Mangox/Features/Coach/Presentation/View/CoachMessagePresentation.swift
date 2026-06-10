import SwiftUI

// MARK: - Bubble chrome by delivery path / category

enum CoachResponseAppearance: Equatable {
    case cloud
    case onDevice
    case pcc
    case webSearch
    case planIntake

    init(messageCategory: String?) {
        switch messageCategory?.lowercased() ?? "" {
        case "on_device", "on_device_coach":
            self = .onDevice
        case "pcc_coach":
            self = .pcc
        case "pcc_web_search":
            self = .webSearch
        case "plan_intake", "plan_analysis":
            self = .planIntake
        case "recovery":
            self = .cloud
        default:
            self = .cloud
        }
    }

    var icon: String {
        switch self {
        case .cloud: "sparkles"
        case .onDevice: "apple.intelligence"
        case .pcc: "cloud.fill"
        case .webSearch: "globe.americas.fill"
        case .planIntake: "map.fill"
        }
    }

    var label: String {
        switch self {
        case .cloud: "Coach"
        case .onDevice: "On-device"
        case .pcc: "Private Cloud"
        case .webSearch: "Web + PCC"
        case .planIntake: "Plan design"
        }
    }

    var accent: Color {
        switch self {
        case .cloud: AppColor.mango
        case .onDevice: Color.cyan.opacity(0.9)
        case .pcc: Color.indigo.opacity(0.92)
        case .webSearch: AppColor.mango.opacity(0.95)
        case .planIntake: Color.purple.opacity(0.88)
        }
    }

    var stripGradient: LinearGradient {
        LinearGradient(
            colors: stripColors,
            startPoint: .top,
            endPoint: .bottom
        )
    }

    var bubbleFill: LinearGradient {
        LinearGradient(
            colors: [fillTop, fillBottom],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var bubbleStroke: LinearGradient {
        LinearGradient(
            colors: strokeColors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var statusFill: Color {
        switch self {
        case .cloud: Color.white.opacity(0.05)
        case .onDevice: Color.cyan.opacity(0.08)
        case .pcc: Color.indigo.opacity(0.09)
        case .webSearch: AppColor.mango.opacity(0.07)
        case .planIntake: Color.purple.opacity(0.08)
        }
    }

    var statusStroke: Color {
        switch self {
        case .cloud: AppColor.mango.opacity(0.24)
        case .onDevice: Color.cyan.opacity(0.26)
        case .pcc: Color.indigo.opacity(0.3)
        case .webSearch: AppColor.mango.opacity(0.32)
        case .planIntake: Color.purple.opacity(0.28)
        }
    }

    var showsOnDevicePrivacyFooter: Bool {
        self == .onDevice
    }

    // MARK: - Header overrides by semantic category

    static func headerIcon(category: String?, appearance: CoachResponseAppearance) -> String {
        switch category?.lowercased() ?? "" {
        case "training_advice": return "bicycle"
        case "plan_analysis", "plan_intake": return "chart.bar.fill"
        case "nutrition": return "fork.knife"
        case "recovery": return "waveform.path.ecg"
        case "equipment": return "gearshape.fill"
        case "clarification": return "questionmark.circle.fill"
        case "pcc_web_search": return "globe"
        default: return appearance.icon
        }
    }

    static func headerLabel(category: String?, appearance: CoachResponseAppearance) -> String {
        switch category?.lowercased() ?? "" {
        case "training_advice": return "Training"
        case "plan_analysis": return "Plan"
        case "plan_intake": return "Plan setup"
        case "nutrition": return "Nutrition"
        case "recovery": return "Recovery"
        case "equipment": return "Equipment"
        case "clarification": return "Clarify"
        case "on_device", "on_device_coach": return appearance.label
        case "pcc_coach": return appearance.label
        case "pcc_web_search": return "Web research"
        default: return appearance.label
        }
    }

    private var stripColors: [Color] {
        switch self {
        case .cloud:
            [AppColor.mango.opacity(0.9), AppColor.mango.opacity(0.32)]
        case .onDevice:
            [Color.cyan.opacity(0.85), Color.blue.opacity(0.34)]
        case .pcc:
            [Color.indigo.opacity(0.88), Color.blue.opacity(0.35)]
        case .webSearch:
            [AppColor.mango.opacity(0.92), Color.orange.opacity(0.38)]
        case .planIntake:
            [Color.purple.opacity(0.85), Color.indigo.opacity(0.32)]
        }
    }

    private var fillTop: Color {
        switch self {
        case .cloud: Color.white.opacity(0.09)
        case .onDevice: Color.cyan.opacity(0.11)
        case .pcc: Color.indigo.opacity(0.1)
        case .webSearch: AppColor.mango.opacity(0.09)
        case .planIntake: Color.purple.opacity(0.09)
        }
    }

    private var fillBottom: Color {
        Color.white.opacity(0.045)
    }

    private var strokeColors: [Color] {
        switch self {
        case .cloud:
            [Color.white.opacity(0.14), Color.white.opacity(0.06), AppColor.mango.opacity(0.12)]
        case .onDevice:
            [Color.cyan.opacity(0.34), Color.white.opacity(0.08), Color.blue.opacity(0.18)]
        case .pcc:
            [Color.indigo.opacity(0.36), Color.white.opacity(0.08), Color.blue.opacity(0.16)]
        case .webSearch:
            [AppColor.mango.opacity(0.38), Color.white.opacity(0.08), Color.orange.opacity(0.2)]
        case .planIntake:
            [Color.purple.opacity(0.34), Color.white.opacity(0.08), Color.indigo.opacity(0.18)]
        }
    }
}

// MARK: - Semantic tag pill colors

enum CoachTagPillPalette {
    case ftp
    case tss
    case recovery
    case power
    case plan
    case web
    case nutrition
    case neutral

    static func forTag(_ raw: String) -> CoachTagPillPalette {
        let tag = raw.lowercased().replacingOccurrences(of: " ", with: "_")
        if tag.contains("ftp") { return .ftp }
        if tag.contains("tss") || tag.contains("load") { return .tss }
        if tag.contains("recovery") || tag.contains("whoop") || tag.contains("hrv") { return .recovery }
        if tag.contains("power") || tag.contains("watt") { return .power }
        if tag.contains("plan") || tag.contains("period") { return .plan }
        if tag.contains("web") { return .web }
        if tag.contains("nutrition") || tag.contains("fuel") { return .nutrition }
        return .neutral
    }

    var foreground: Color {
        switch self {
        case .ftp: Color.orange.opacity(0.95)
        case .tss: Color.yellow.opacity(0.92)
        case .recovery: Color.green.opacity(0.9)
        case .power: Color.red.opacity(0.88)
        case .plan: Color.indigo.opacity(0.9)
        case .web: AppColor.mango.opacity(0.95)
        case .nutrition: Color.mint.opacity(0.9)
        case .neutral: AppColor.fg2
        }
    }

    var fill: Color {
        switch self {
        case .ftp: Color.orange.opacity(0.14)
        case .tss: Color.yellow.opacity(0.12)
        case .recovery: Color.green.opacity(0.12)
        case .power: Color.red.opacity(0.11)
        case .plan: Color.indigo.opacity(0.14)
        case .web: AppColor.mango.opacity(0.14)
        case .nutrition: Color.mint.opacity(0.12)
        case .neutral: Color.white.opacity(0.06)
        }
    }

    var stroke: Color {
        switch self {
        case .ftp: Color.orange.opacity(0.35)
        case .tss: Color.yellow.opacity(0.32)
        case .recovery: Color.green.opacity(0.32)
        case .power: Color.red.opacity(0.3)
        case .plan: Color.indigo.opacity(0.34)
        case .web: AppColor.mango.opacity(0.36)
        case .nutrition: Color.mint.opacity(0.3)
        case .neutral: Color.white.opacity(0.1)
        }
    }
}

enum CoachTagPillFormatting {
    static func displayLabel(for raw: String) -> String {
        let spaced = raw.replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !spaced.isEmpty else { return raw }
        return spaced.localizedCapitalized
    }
}

enum CoachMessagePresentation {
    private static let semanticCategories: Set<String> = [
        "training_advice", "plan_analysis", "recovery", "nutrition", "equipment", "clarification",
    ]

    /// Semantic topic for the bubble header when `category` holds a delivery path (`on_device`, `pcc_coach`, …).
    static func semanticCategory(category: String?, tags: [String]) -> String? {
        if let cat = category?.lowercased(), semanticCategories.contains(cat) { return cat }
        for tag in tags {
            let normalized = tag.lowercased().replacingOccurrences(of: " ", with: "_")
            if semanticCategories.contains(normalized) { return normalized }
        }
        return nil
    }

    static func headerCategory(message: ChatMessage, appearance: CoachResponseAppearance) -> String? {
        switch message.category?.lowercased() {
        case "pcc_web_search":
            return "pcc_web_search"
        case "on_device", "pcc_coach", "plan_intake":
            break
        default:
            break
        }
        if appearance == .webSearch { return "pcc_web_search" }
        return semanticCategory(category: message.category, tags: message.tags) ?? message.category
    }

    static func isWebResearchMessage(_ message: ChatMessage) -> Bool {
        if message.usedWebSearch { return true }
        let cat = message.category?.lowercased() ?? ""
        return cat == "pcc_web_search"
    }

    static func shouldShowPlanIntakeChrome(for message: ChatMessage) -> Bool {
        if isWebResearchMessage(message) { return false }
        let cat = message.category?.lowercased() ?? ""
        if cat == "plan_intake" || cat == "plan_analysis" { return true }
        if message.followUpBlocks.count > 1 { return true }
        if cat == "clarification" {
            let q = (message.followUpBlocks.first?.question ?? message.followUpQuestion ?? "").lowercased()
            let body = message.content.lowercased()
            return body.contains("plan intake")
                || body.contains("build your plan")
                || body.contains("collect the key details")
                || q.contains("weekly hour")
                || q.contains("experience level")
        }
        return false
    }

    /// Slim inline chips under the bubble instead of the full "PRIVATE CLOUD ASKS" card.
    static func shouldUseCompactFollowUp(for message: ChatMessage) -> Bool {
        guard message.followUpBlocks.count <= 1 else { return false }
        let cat = message.category?.lowercased() ?? ""
        if cat == "plan_intake" || cat == "plan_analysis" { return false }
        if !message.followUpBlocks.isEmpty { return false }
        if isWebResearchMessage(message) { return true }
        let hasQuestion = !(message.followUpQuestion?
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let hasActions = !message.suggestedActions.isEmpty
        if hasQuestion || hasActions {
            return cat != "clarification"
        }
        return false
    }

    static func displayTags(for message: ChatMessage, isShortReply: Bool) -> [String] {
        if isShortReply, message.tags.count <= 1, !isWebResearchMessage(message) { return [] }
        let filtered = message.tags.filter { !isNoisyTag($0, webResearch: isWebResearchMessage(message)) }
        let cap = isWebResearchMessage(message) ? 2 : 4
        return Array(filtered.prefix(cap))
    }

    private static func isNoisyTag(_ raw: String, webResearch: Bool) -> Bool {
        guard webResearch else { return false }
        let tag = raw.lowercased().replacingOccurrences(of: " ", with: "_")
        if tag.contains("event") && tag.contains("date") { return true }
        if tag == "date" || tag == "web" { return true }
        return false
    }
}

struct CoachInlineFollowUpModel {
    let question: String?
    let actions: [SuggestedAction]
    let isEnabled: Bool
    let messageID: UUID
    let sentChipKey: String?
    let onSelect: (SuggestedAction) -> Void
}

// MARK: - Compact delivery badge (short replies)

struct CoachDeliveryBadge: View {
    let appearance: CoachResponseAppearance
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: appearance.icon)
                .font(.system(size: compact ? 9 : 10, weight: .semibold))
            if !compact {
                Text(appearance.label)
                    .font(.system(size: 9, weight: .semibold))
            }
        }
        .foregroundStyle(appearance.accent.opacity(compact ? 0.82 : 0.9))
        .padding(.horizontal, compact ? 7 : 9)
        .padding(.vertical, compact ? 4 : 5)
        .background(
            Capsule(style: .continuous)
                .fill(appearance.accent.opacity(0.12))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(appearance.accent.opacity(0.28), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Answered via \(appearance.label)")
    }
}
