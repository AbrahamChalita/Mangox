# Mangox Monetization + AI Setup Guide

## 1. Add RevenueCat SDK

In Xcode:
1. **File → Add Package Dependencies**
2. Search for: `https://github.com/RevenueCat/purchases-ios.git`
3. Select **latest version** (v5.x+)
4. Add to **Mangox** target

## 2. Configure RevenueCat Dashboard

1. Go to [RevenueCat Dashboard](https://app.revenuecat.com/)
2. Create a new project "Mangox"
3. Add iOS app with your Bundle ID
4. Create entitlement: `pro`
5. Create products in App Store Connect:
   - `com.mangox.pro.monthly` — $4.99/month (Auto-renewable)
   - `com.mangox.pro.yearly` — $29.99/year (Auto-renewable)
6. Link products to the `pro` entitlement in RevenueCat
7. Create an Offering called "default" with both products
8. Get your **API Key** (Project Settings → API Keys)

## 3. Configure App Store Connect

1. Go to [App Store Connect](https://appstoreconnect.apple.com/)
2. Add In-App Purchase capability in Xcode (Signing & Capabilities → + → In-App Purchase)
3. Create the two subscription products with the IDs above
4. Create a Subscription Group "Mangox Pro"
5. Add both products to the group

## 4. Add RevenueCat API Key

Add to `MangoxApp.swift` init, after the existing setup:

```swift
init() {
    // ... existing setup ...
    
    // RevenueCat
    PurchasesManager.shared.configure(apiKey: "YOUR_REVENUECAT_API_KEY")
}
```

Or add to `Info.plist` as `RevenueCatAPIKey` and read it:

```swift
if let apiKey = Bundle.main.object(forInfoDictionaryKey: "RevenueCatAPIKey") as? String {
    PurchasesManager.shared.configure(apiKey: apiKey)
}
```

## 5. Deploy Cloudflare Worker

1. Install Wrangler: `npm install -g wrangler`
2. Create `wrangler.toml` in `backend/`:

```toml
name = "mangox-ai"
main = "worker.ts"
compatibility_date = "2025-01-01"

[vars]
AI_CHAT_SYSTEM_PROMPT = "..."
AI_PLAN_SYSTEM_PROMPT = "..."

[ai]
binding = "AI"

[[kv_namespaces]]
binding = "RATE_LIMIT_KV"
id = "your-kv-id"

[[kv_namespaces]]
binding = "USAGE_KV"
id = "your-kv-id-2"
```

3. Set secrets:
```bash
wrangler secret put OPENAI_API_KEY
wrangler secret put ANTHROPIC_API_KEY
wrangler secret put REVENUECAT_API_KEY
```

4. Deploy:
```bash
wrangler deploy
```

## 6. Update Backend URL

In `AIPlanService.swift` and `AIChatService.swift`, update the default `baseURL`:
```swift
self.baseURL = "https://mangox-ai.your-subdomain.workers.dev"
```

Or set via UserDefaults for testing:
```swift
UserDefaults.standard.set("http://localhost:8787", forKey: "mangox_ai_backend_url")
```

## 7. Test Flow

1. Build and run in Xcode (simulator or device)
2. Tap the brain icon on Home → opens ChatView
3. Tap "Generate AI Plan" in Training Plan → opens AIPlanGeneratorView
4. Tap "Upgrade to Pro" → opens PaywallView
5. Use sandbox account to test purchases

## Files Created

| File | Purpose |
|---|---|
| `Services/PurchasesManager.swift` | RevenueCat wrapper (replaces StoreKitManager) |
| `Services/AIChatService.swift` | Chat backend client with guardrails |
| `Services/AIPlanService.swift` | Plan generation backend client |
| `Services/PlanValidator.swift` | Validates AI output against model constraints |
| `Services/CreditManager.swift` | Tracks monthly AI allowance + purchased credits |
| `Core/Models/ChatMessage.swift` | SwiftData model for chat messages |
| `Core/Models/AIPlanDTOs.swift` | DTOs for plan generation request/response |
| `Core/Models/Entitlement.swift` | Feature gating state |
| `Views/PaywallView.swift` | RevenueCat-powered paywall |
| `Views/AIPlanGeneratorView.swift` | AI plan input form |
| `Views/ChatView.swift` | AI coaching chat UI |
| `backend/worker.ts` | Cloudflare Worker with all guardrails |

## Files Modified

| File | Changes |
|---|---|
| `App/MangoxApp.swift` | Added PurchasesManager, AIChatService, ChatMessage model container |
| `App/ContentView.swift` | Added `.chat`, `.aiPlanGenerator`, `.paywall` routes |
| `Views/HomeView.swift` | Added brain icon → ChatView sheet |
| `Views/TrainingPlanView.swift` | Added "Generate AI Plan" + "Upgrade to Pro" buttons |
| `Views/SettingsView.swift` | Added subscription management section |
