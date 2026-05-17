# AGENTS.md

## Project

Mangox is an iOS app in a single Xcode target, `Mangox`, with tests in `MangoxTests` and `MangoxUITests`. The repo also contains a small TypeScript helper package in `backend/` for coach-related parsing and schema utilities.

## Repo layout

- `Mangox/`: main app source, assets, plist, privacy manifest
- `Mangox/App/`: app entry and root navigation
- `Mangox/Core/`: shared infrastructure, persistence, utilities, UI components
- `Mangox/Features/`: product features grouped by domain
- `MangoxTests/`: unit and integration-style tests
- `MangoxUITests/`: UI tests
- `Docs/`: product and engineering notes
- `backend/`: TypeScript helper package

## Architecture notes

- The app is physically organized by feature, but compiles as one Swift module.
- Prefer existing domain boundaries in `Docs/MODULES.md`:
  - `Core` stays feature-agnostic.
  - `Features/*` can depend on `Core` and shared services.
  - Shared service logic should not grow feature-specific coupling unless routed through protocols or plain data.

## Build and test

Use the shared `Mangox` scheme.

- Build:
  - `xcodebuild -project Mangox.xcodeproj -scheme Mangox -configuration Debug -destination 'generic/platform=iOS Simulator' build`
- Test:
  - `xcodebuild -project Mangox.xcodeproj -scheme Mangox -destination 'id=<simulator-id>' test`
- Focused tests:
  - `xcodebuild -project Mangox.xcodeproj -scheme Mangox -destination 'id=<simulator-id>' test -only-testing:MangoxTests`

The app scheme enables `MANGOX_DEV_PRO=1` for launches.

For `backend/`:

- Install: `npm install`
- Typecheck: `npm run check`

## Change guidance

- Keep edits scoped to the feature or service being changed.
- Follow existing SwiftUI and Swift naming/style patterns in the touched area before introducing new abstractions.
- Avoid broad file moves or architectural rewrites unless the task requires them.
- When changing shared logic in `Core` or cross-feature services, add or update tests in `MangoxTests`.
- When changing `backend/`, keep the package type-safe and validated through its existing Zod-based schema flow.

## Documentation

Check `Docs/` before making product-shaping changes. In particular:

- `Docs/MODULES.md` for code organization
- `Docs/SUPABASE_SETUP.md` for backend integration assumptions
- `Docs/MONETIZATION_SETUP.md` for paywall and billing work
- `Docs/AI_CONNECTION.md` for AI-related flows

## Agent expectations

- Read the surrounding feature area before editing.
- Do not revert unrelated user changes.
- Prefer small, verifiable changes with targeted tests.
- Update docs when behavior, setup, or architecture expectations materially change.
