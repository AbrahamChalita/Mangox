# Native Liquid Glass Guide (Apple Docs -> Mangox)

This guide maps Apple documentation and WWDC25 guidance to concrete changes in Mangox.

## 1) What counts as native Liquid Glass

From Apple guidance:

- Prefer system UI containers first (toolbars, bars, menus, controls). They adapt automatically when you build with the latest SDK.
- Use Liquid Glass as a control/navigation layer over content, not as a full-screen decorative effect.
- For custom controls, use native Liquid Glass APIs instead of custom blur + overlays.

Primary Apple references:

- [Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass)
- [Applying Liquid Glass to custom views](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views)
- [Build a SwiftUI app with the new design (WWDC25-323)](https://developer.apple.com/videos/play/wwdc2025/323/)
- [Get to know the new design system (WWDC25-219)](https://developer.apple.com/videos/play/wwdc2025/219/)
- [What’s new in SwiftUI (WWDC25-256)](https://developer.apple.com/videos/play/wwdc2025/256/)
- [HIG](https://developer.apple.com/design/human-interface-guidelines/)

## 2) Native APIs to use

SwiftUI:

- `glassEffect(_:in:isEnabled:)`
- `Glass`
- `GlassEffectContainer`
- `glassEffectID(_:in:)` for related glass elements
- `GlassEffectTransition` (`identity`, `materialize`, `matchedGeometry`)
- `GlassButtonStyle` / `GlassProminentButtonStyle`

UIKit (only if a screen is UIKit-backed):

- `UIGlassEffect`
- `UIGlassContainerEffect`
- `UIVisualEffectView(effect: UIGlassEffect(...))`

## 3) Mangox placement map (recommended)

Home (`HomeView.swift`):

- Keep workout list rows plain for scanability.
- Add one floating glass action group:
  - `New Ride`
  - `Import Route`
  - `Resume` (when active workout exists)
- Remove custom faux-glass decoration from large surfaces.

Ride setup (`ConnectionView.swift`):

- Use glass only for the bottom action cluster (`Start Ride`, `Cancel`, route action).
- Keep scanning/device rows plain and high-contrast.

Dashboard (`DashboardView.swift`):

- Glass on header controls and the bottom control bar only.
- Keep power arc, zones, graph, and metric cards mostly non-glass for readability.
- Keep map visible but not glass-heavy.

Summary (`SummaryView.swift`):

- Glass for navigation/action strip only (back/home/export/delete).
- Keep stat cards, zone bars, and lap table opaque/plain.

## 4) Glass menu pattern for Mangox (Apple-style)

Use a single menu anchor, not multiple glass blocks:

- iPhone: bottom trailing floating menu
- iPad: trailing rail menu
- Menu label: prominent action (`New Ride` or `More`)
- Menu contents: 2-4 high-value actions max

Suggested menu actions:

1. `New Ride`
2. `Import Route`
3. `Resume Ride` (if available)
4. `Settings` (future)

Menu content should follow HIG menu labeling rules: concise verb phrases, most-used actions first, separators for related groups.

## 5) Implementation template (SwiftUI)

```swift
import SwiftUI

struct HomeGlassMenu: View {
    let onNewRide: () -> Void
    let onImportRoute: () -> Void
    let onResumeRide: (() -> Void)?

    var body: some View {
        Menu {
            Button("New Ride", systemImage: "play.fill", action: onNewRide)
            Button("Import Route", systemImage: "map", action: onImportRoute)
            if let onResumeRide {
                Divider()
                Button("Resume Ride", systemImage: "arrow.clockwise", action: onResumeRide)
            }
        } label: {
            Label("Add", systemImage: "plus")
                .font(.system(size: 16, weight: .semibold))
        }
        .buttonStyle(.glassProminent)
    }
}
```

For custom small control surfaces:

```swift
CustomControlSurface()
    .glassEffect()
```

If supporting pre-Liquid-Glass OS versions, gate usage:

```swift
if #available(iOS 26.0, *) {
    glassControl.buttonStyle(.glassProminent)
} else {
    glassControl.buttonStyle(.borderedProminent)
}
```

## 6) Practical do/don’t rules for this app

Do:

- Use one glass action cluster per screen.
- Keep numeric training data high-contrast and mostly non-glass.
- Validate on iPhone + iPad, portrait + landscape.
- Verify readability in Light and Dark appearance.

Don’t:

- Put glass behind every card.
- Layer multiple translucent backgrounds in metric-heavy sections.
- Use decorative glass where it competes with watts, zones, or route readability.

## 7) Rollout order (lowest risk first)

1. Home: add one native glass menu and remove faux-glass backgrounds.
2. Connection: convert bottom action group to native glass styles.
3. Dashboard: keep current data layout; apply glass only to controls/header.
4. Summary: restrict glass to top and bottom action rows.
5. Add optional glass transitions (`GlassEffectTransition`) only after readability QA passes.
