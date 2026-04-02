# How Mangox connected to AI models (archived)

This document describes the **removed** AI integration as it existed in this repository. It is kept for historical reference only.

## Architecture overview

The **iOS app never called OpenAI, Groq, or Anthropic directly.** All model calls went through a **Cloudflare Worker** (`backend/worker.ts`) deployed separately (e.g. Railway default URL `https://mangox-backend-production.up.railway.app`). API keys lived only in server environment variables.

### Client (Swift)

- **`AIChatService`** — `POST` to `{baseURL}/api/chat/stream` (Server-Sent Events, OpenAI-compatible deltas) with fallback to `POST` `{baseURL}/api/chat` for a full JSON body.
- **`AIPlanService`** — `POST` to `{baseURL}/api/generate-plan` with plan inputs and entitlement token; response decoded into `TrainingPlan`.

**Base URL** — `UserDefaults` key `mangox_ai_backend_url`; if unset, the production Railway host above was used.

**Payloads** — Chat sent `message`, `history`, `user_context` (`UserContextSnapshot`: FTP, plan summary, recent workouts), and `is_pro`. Plan generation sent `inputs` (event, FTP, constraints, etc.), `user_id`, and `entitlement_token`.

**Credits** — `CreditManager` tracked monthly Pro allowance and consumable credits (aligned with StoreKit IAP product IDs for credit packs in `StoreKitManager`, which was never wired into the main UI).

### Server (Cloudflare Worker)

Endpoints:

| Path | Purpose |
|------|---------|
| `POST /api/chat` | Non-streaming chat; JSON response validated against a fixed schema. |
| `POST /api/chat/stream` | Streaming chat; Groq or OpenAI SSE forwarded to the client; client reassembled JSON. |
| `POST /api/generate-plan` | Training plan JSON from LLM. |

**Provider selection** — `resolveLLMBackend(env)` in `worker.ts`:

1. If `GROQ_API_KEY` is set → **Groq** OpenAI-compatible API (`https://api.groq.com/openai/v1/chat/completions`), models defaulting to `llama-3.3-70b-versatile` (overridable via `GROQ_CHAT_MODEL` / `GROQ_PLAN_MODEL`).
2. Else if `OPENAI_API_KEY` is set → **OpenAI** (`https://api.openai.com/v1/chat/completions`), models such as `gpt-4o-mini` for chat streaming.

**Non-streaming path** also had `callAnthropic` for Anthropic’s API in source, but **the main `callLLM` path used only Groq or OpenAI**, not Anthropic.

**Guards** — RevenueCat/API auth, KV-backed rate limits, Unicode normalization, max input sizes, JSON schema validation on chat output, and basic injection checks on selected fields.

### SwiftData models used by AI features (removed)

- `SavedAIPlan` — persisted generated `TrainingPlan` blobs.
- `ChatSession` / `ChatMessage` — coach chat threads and assistant metadata (structured extras, suggestions).

### UI (removed)

- `ChatView`, `ChatContainerView`, `ChatComposerTextView`
- `AIPlanGeneratorView`
- `SavedPlanDetailView` (library detail for saved AI plans)
- Coach tab sections that navigated to chat or AI plan generation

---

*The backend directory, client services, and views above have been deleted from the project; this file remains as documentation.*
