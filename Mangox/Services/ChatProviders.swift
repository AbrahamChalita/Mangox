import Foundation
import os.log

enum ChatProviderKind: String {
    case mangoxBackend
    case openAICompatible

    var displayName: String {
        switch self {
        case .mangoxBackend:
            "Mangox Cloud"
        case .openAICompatible:
            "OpenAI-Compatible"
        }
    }

    var detail: String {
        switch self {
        case .mangoxBackend:
            "Best for rich coaching responses, tags, suggestions, and inline plan flow."
        case .openAICompatible:
            "Connects to any /v1/chat/completions endpoint — OpenAI, Groq, or a local Ollama server. Leave URL blank to use OpenAI directly with your API key."
        }
    }

    var capabilities: ChatProviderCapabilities {
        switch self {
        case .mangoxBackend:
            ChatProviderCapabilities(
                supportsStreaming: true,
                supportsToolCalls: true,
                supportsRichMetadata: true,
                supportsInlinePlans: true,
                supportsReferences: true
            )
        case .openAICompatible:
            ChatProviderCapabilities(
                supportsStreaming: true,
                supportsToolCalls: true,
                supportsRichMetadata: false,
                supportsInlinePlans: false,
                supportsReferences: false
            )
        }
    }
}

enum ChatProviderDefaultsKey {
    static let providerKind = "AIChatProvider"
    static let baseURL = "AIChatProviderBaseURL"
    static let model = "AIChatProviderModel"
    static let apiKey = "AIChatProviderAPIKey"
}

struct ChatProviderCapabilities: Equatable {
    let supportsStreaming: Bool
    let supportsToolCalls: Bool
    let supportsRichMetadata: Bool
    let supportsInlinePlans: Bool
    let supportsReferences: Bool

    var badges: [String] {
        var items: [String] = []
        if supportsStreaming { items.append("Streaming") }
        if supportsToolCalls { items.append("Tools") }
        if supportsRichMetadata { items.append("Rich metadata") }
        if supportsInlinePlans { items.append("Inline plans") }
        if supportsReferences { items.append("References") }
        return items
    }
}

struct ChatProviderConfiguration: Equatable {
    let kind: ChatProviderKind
    let baseURL: String
    let model: String?
    let apiKey: String?

    var capabilities: ChatProviderCapabilities { kind.capabilities }
    var displayName: String { kind.displayName }
    var detail: String { kind.detail }
    var effectiveModel: String {
        if let model, !model.isEmpty {
            return model
        }
        switch kind {
        case .mangoxBackend:
            return "Managed coach"
        case .openAICompatible:
            return OpenAICompatibleDefaults.model
        }
    }
}

protocol ChatProviderAdapter {
    func streamChat(
        request: ChatRequest,
        configuration: ChatProviderConfiguration,
        userID: String
    ) -> AsyncThrowingStream<ChatRuntimeEvent, Error>
}

struct ChatProviderResolver {
    private enum Keys {
        static let providerKind = ChatProviderDefaultsKey.providerKind
        static let baseURL = ChatProviderDefaultsKey.baseURL
        static let model = ChatProviderDefaultsKey.model
        static let apiKey = ChatProviderDefaultsKey.apiKey
        static let mangoxBaseURL = "MangoxAPIBaseURL"
    }

    func resolve(bundle: Bundle = .main, defaults: UserDefaults = .standard)
        -> ChatProviderConfiguration
    {
        let rawKind = defaults.string(forKey: Keys.providerKind)
        let kind = ChatProviderKind(rawValue: rawKind ?? "") ?? .mangoxBackend

        switch kind {
        case .mangoxBackend:
            let rawBaseURL = defaults.string(forKey: Keys.baseURL)
            let baseURL =
                (rawBaseURL?.isEmpty == false ? rawBaseURL : nil)
                ?? bundle.object(forInfoDictionaryKey: Keys.mangoxBaseURL) as? String
                ?? "https://mangox-backend-production.up.railway.app"

            return ChatProviderConfiguration(
                kind: .mangoxBackend,
                baseURL: baseURL,
                model: nil,
                apiKey: nil
            )

        case .openAICompatible:
            let baseURL =
                defaults.string(forKey: Keys.baseURL)
                ?? bundle.object(forInfoDictionaryKey: Keys.baseURL) as? String
                ?? OpenAICompatibleDefaults.baseURL
            let model =
                defaults.string(forKey: Keys.model)
                ?? bundle.object(forInfoDictionaryKey: Keys.model) as? String
            let apiKey =
                defaults.string(forKey: Keys.apiKey)
                ?? bundle.object(forInfoDictionaryKey: Keys.apiKey) as? String

            return ChatProviderConfiguration(
                kind: .openAICompatible,
                baseURL: baseURL,
                model: model,
                apiKey: apiKey
            )
        }
    }
}

struct ChatProviderFactory {
    static func makeAdapter(for kind: ChatProviderKind) -> ChatProviderAdapter {
        switch kind {
        case .mangoxBackend:
            MangoxBackendChatProvider()
        case .openAICompatible:
            OpenAICompatibleChatProvider()
        }
    }
}

private struct MangoxBackendChatProvider: ChatProviderAdapter {
    private let logger = Logger(
        subsystem: "com.abchalita.Mangox", category: "MangoxBackendChatProvider")

    func streamChat(
        request: ChatRequest,
        configuration: ChatProviderConfiguration,
        userID: String
    ) -> AsyncThrowingStream<ChatRuntimeEvent, Error> {
        AsyncThrowingStream(bufferingPolicy: .unbounded) { continuation in
            let task = Task {
                do {
                    if let url = URL(string: configuration.baseURL + "/api/chat/stream") {
                        var req = URLRequest(url: url)
                        req.httpMethod = "POST"
                        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                        req.setValue(userID, forHTTPHeaderField: "X-User-ID")
                        req.mangox_applyDevTunnelHeadersIfNeeded(
                            mangoxBaseURL: configuration.baseURL)
                        req.timeoutInterval = 300
                        req.httpBody = try JSONEncoder().encode(request)

                        do {
                            let (bytes, response) = try await URLSession.shared.bytes(for: req)
                            if let httpResponse = response as? HTTPURLResponse,
                                httpResponse.statusCode >= 400
                            {
                                throw URLError(.badServerResponse)
                            }

                            for try await line in bytes.lines {
                                if Task.isCancelled { throw CancellationError() }
                                guard line.hasPrefix("data: ") else { continue }
                                let payload = line.dropFirst(6)
                                guard !payload.isEmpty else { continue }
                                let event = try JSONDecoder().decode(
                                    ChatWireEvent.self, from: Data(payload.utf8))

                                switch event.type {
                                case "status":
                                    if let status = event.status {
                                        continuation.yield(.status(status))
                                    }
                                case "delta":
                                    if let delta = event.delta {
                                        continuation.yield(.textDelta(delta))
                                    }
                                case "final":
                                    if let message = event.message {
                                        if !message.toolCalls.isEmpty {
                                            continuation.yield(.toolCalls(message.toolCalls))
                                        }
                                        continuation.yield(.completed(message))
                                    }
                                case "error":
                                    continuation.yield(.failed(event.error ?? "Streaming failed"))
                                case "done":
                                    break
                                default:
                                    continue
                                }
                            }
                            continuation.finish()
                            return
                        } catch {
                            if error is CancellationError {
                                throw error
                            }
                            logger.error("SSE stream failed, falling back to POST: \(error)")
                        }
                    }

                    let response: ChatAPIResponse = try await post(
                        baseURL: configuration.baseURL,
                        path: "/api/chat",
                        body: request,
                        userID: userID,
                        apiKey: nil,
                        logger: logger
                    )
                    if !response.toolCalls.isEmpty {
                        continuation.yield(.toolCalls(response.toolCalls))
                    }
                    continuation.yield(.completed(response))
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}

private enum OpenAICompatibleDefaults {
    /// Default for cloud API key-only mode. Override in Settings → Coach → Model.
    static let model = "gpt-4o-mini"
    static let baseURL = "https://api.openai.com"
}

private func resolvedOpenAICompatibleModel(_ configuration: ChatProviderConfiguration) -> String {
    let t = configuration.model?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return t.isEmpty ? OpenAICompatibleDefaults.model : t
}

private struct OpenAICompatibleChatProvider: ChatProviderAdapter {
    private let logger = Logger(
        subsystem: "com.abchalita.Mangox", category: "OpenAICompatibleChatProvider")

    func streamChat(
        request: ChatRequest,
        configuration: ChatProviderConfiguration,
        userID: String
    ) -> AsyncThrowingStream<ChatRuntimeEvent, Error> {
        AsyncThrowingStream(bufferingPolicy: .unbounded) { continuation in
            let task = Task {
                do {
                    let modelName = resolvedOpenAICompatibleModel(configuration)
                    let wireRequest = OpenAIChatCompletionsRequest(
                        model: modelName,
                        messages: makeMessages(from: request),
                        stream: true,
                        tools: ChatToolRegistry.openAIRequestTools,
                        toolChoice: ChatToolRegistry.openAIRequestTools.isEmpty ? nil : "auto"
                    )

                    if let url = URL(string: configuration.baseURL + "/v1/chat/completions") {
                        var req = URLRequest(url: url)
                        req.httpMethod = "POST"
                        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                        req.setValue(userID, forHTTPHeaderField: "X-User-ID")
                        if let apiKey = configuration.apiKey, !apiKey.isEmpty {
                            req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                        }
                        req.timeoutInterval = 300
                        req.httpBody = try JSONEncoder().encode(wireRequest)

                        continuation.yield(.status("Connecting to \(modelName)"))

                        var assembledContent = ""
                        var latestToolCalls: [ToolCall] = []

                        let (bytes, response) = try await URLSession.shared.bytes(for: req)
                        if let httpResponse = response as? HTTPURLResponse,
                            httpResponse.statusCode >= 400
                        {
                            throw URLError(.badServerResponse)
                        }

                        for try await line in bytes.lines {
                            if Task.isCancelled { throw CancellationError() }
                            guard line.hasPrefix("data: ") else { continue }
                            let payload = String(line.dropFirst(6))
                            if payload == "[DONE]" { break }
                            guard let data = payload.data(using: .utf8) else { continue }

                            let event = try JSONDecoder().decode(
                                OpenAIChatCompletionsChunk.self, from: data)
                            for choice in event.choices {
                                if let content = choice.delta.content, !content.isEmpty {
                                    assembledContent += content
                                    continuation.yield(.textDelta(content))
                                }

                                if let toolCalls = choice.delta.toolCalls, !toolCalls.isEmpty {
                                    latestToolCalls = toolCalls.map {
                                        $0.asToolCall(state: .pending)
                                    }
                                    continuation.yield(.toolCalls(latestToolCalls))
                                }
                            }
                        }

                        let finalResponse = ChatAPIResponse(
                            category: "training_advice",
                            content: assembledContent,
                            suggestedActions: [],
                            followUpQuestion: nil,
                            followUpBlocks: [],
                            confidence: 1.0,
                            thinkingSteps: [],
                            tags: [],
                            references: [],
                            toolCalls: latestToolCalls,
                            usedWebSearch: false
                        )
                        continuation.yield(.completed(finalResponse))
                        continuation.finish()
                    }
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch {
                    do {
                        let fallbackRequest = OpenAIChatCompletionsRequest(
                            model: resolvedOpenAICompatibleModel(configuration),
                            messages: makeMessages(from: request),
                            stream: false,
                            tools: ChatToolRegistry.openAIRequestTools,
                            toolChoice: ChatToolRegistry.openAIRequestTools.isEmpty ? nil : "auto"
                        )
                        let response: OpenAIChatCompletionsResponse = try await post(
                            baseURL: configuration.baseURL,
                            path: "/v1/chat/completions",
                            body: fallbackRequest,
                            userID: userID,
                            apiKey: configuration.apiKey,
                            logger: logger
                        )

                        let firstChoice = response.choices.first
                        let toolCalls =
                            firstChoice?.message.toolCalls?.map { $0.asToolCall(state: .completed) }
                            ?? []
                        if !toolCalls.isEmpty {
                            continuation.yield(.toolCalls(toolCalls))
                        }

                        let finalResponse = ChatAPIResponse(
                            category: "training_advice",
                            content: firstChoice?.message.content ?? "",
                            suggestedActions: [],
                            followUpQuestion: nil,
                            followUpBlocks: [],
                            confidence: 1.0,
                            thinkingSteps: [],
                            tags: [],
                            references: [],
                            toolCalls: toolCalls,
                            usedWebSearch: false
                        )
                        continuation.yield(.completed(finalResponse))
                        continuation.finish()
                    } catch {
                        logger.error("OpenAI-compatible chat failed: \(error)")
                        continuation.finish(throwing: error)
                    }
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private func makeMessages(from request: ChatRequest) -> [OpenAIChatMessage] {
        var messages: [OpenAIChatMessage] = []

        let calendarAnchor = """
            CALENDAR ANCHOR: The user's local calendar date today is \(request.client_local_date). \
            Device time zone (IANA): \(request.client_time_zone). \
            All suggested dates and training weeks must be on or after that local date. \
            For a stated goal or event date, cover the full time from today through that event, not a short arbitrary block in the wrong season.
            """
        messages.append(OpenAIChatMessage(role: "system", content: calendarAnchor))

        if let history = request.history {
            messages.append(
                contentsOf: history.map { OpenAIChatMessage(role: $0.role, content: $0.content) })
        }

        messages.append(OpenAIChatMessage(role: "user", content: request.message))
        return messages
    }
}

private struct OpenAIChatCompletionsRequest: Encodable {
    let model: String
    let messages: [OpenAIChatMessage]
    let stream: Bool
    let tools: [OpenAIRequestTool]?
    let toolChoice: String?

    enum CodingKeys: String, CodingKey {
        case model, messages, stream, tools
        case toolChoice = "tool_choice"
    }
}

private struct OpenAIChatMessage: Codable {
    let role: String
    let content: String
}

private struct OpenAIChatCompletionsChunk: Decodable {
    let choices: [OpenAIChunkChoice]
}

private struct OpenAIChunkChoice: Decodable {
    let delta: OpenAIChunkDelta
}

private struct OpenAIChunkDelta: Decodable {
    let content: String?
    let toolCalls: [OpenAIWireToolCall]?

    enum CodingKeys: String, CodingKey {
        case content
        case toolCalls = "tool_calls"
    }
}

private struct OpenAIChatCompletionsResponse: Decodable {
    let choices: [OpenAIChoice]
}

private struct OpenAIChoice: Decodable {
    let message: OpenAIFinalMessage
}

private struct OpenAIFinalMessage: Decodable {
    let content: String?
    let toolCalls: [OpenAIWireToolCall]?

    enum CodingKeys: String, CodingKey {
        case content
        case toolCalls = "tool_calls"
    }
}

private struct OpenAIWireToolCall: Decodable {
    let function: OpenAIWireToolFunction?
}

private struct OpenAIWireToolFunction: Decodable {
    let name: String?
    let arguments: String?
}

extension OpenAIWireToolCall {
    fileprivate func asToolCall(state: ToolCallState) -> ToolCall {
        ToolCall(
            name: function?.name ?? "tool",
            state: state.rawValue,
            detail: function?.arguments
        )
    }
}

private enum ToolCallState: String {
    case pending
    case completed
    case failed
    case skipped
}

private struct ChatToolDefinition {
    let name: String
    let description: String
    let parameters: [String: OpenAIJSONProperty]
    let required: [String]

    var openAIRequestTool: OpenAIRequestTool {
        OpenAIRequestTool(
            type: "function",
            function: OpenAIRequestToolFunction(
                name: name,
                description: description,
                parameters: OpenAIJSONSchema(
                    type: "object",
                    properties: parameters,
                    required: required
                )
            )
        )
    }
}

private enum ChatToolRegistry {
    static let definitions: [ChatToolDefinition] = [
        ChatToolDefinition(
            name: "generate_plan",
            description:
                "Queue on-device plan generation after intake is complete. Only call when you have event_name and event_date (yyyy-MM-dd) and you are NOT also asking follow-up questions in this same reply. If you are showing chips or followUpBlocks to collect missing fields, omit this tool until a later turn (or until the user explicitly says to generate now). Include route stats when known.",
            parameters: [
                "event_name": OpenAIJSONProperty(type: "string", description: "Event or goal name"),
                "event_date": OpenAIJSONProperty(
                    type: "string",
                    description:
                        "Target race or goal day as yyyy-MM-dd only (e.g. 2026-09-12). Never leave empty when the user stated a date."
                ),
                "weekly_hours": OpenAIJSONProperty(
                    type: "integer", description: "Available training hours per week"),
                "experience": OpenAIJSONProperty(
                    type: "string",
                    description: "Experience level such as beginner, intermediate, or advanced"),
                "route_option": OpenAIJSONProperty(
                    type: "string",
                    description:
                        "If the event has multiple routes: long, medium, short, or similar label"),
                "target_distance_km": OpenAIJSONProperty(
                    type: "number", description: "Official route distance in kilometers when known"),
                "target_elevation_m": OpenAIJSONProperty(
                    type: "number", description: "Total climbing in meters when known"),
                "event_location": OpenAIJSONProperty(
                    type: "string", description: "City, region, or country for the event"),
                "event_notes": OpenAIJSONProperty(
                    type: "string", description: "Short note: mass start, gravel, etc."),
            ],
            required: ["event_name", "event_date"]
        ),
        ChatToolDefinition(
            name: "load_recent_ride",
            description: "Request recent workout context for the current athlete.",
            parameters: [:],
            required: []
        ),
        ChatToolDefinition(
            name: "load_active_plan",
            description: "Request the active training plan context for the current athlete.",
            parameters: [:],
            required: []
        ),
        ChatToolDefinition(
            name: "web_search",
            description:
                "Search the web for current race, training, or product information when fresh data is required.",
            parameters: [
                "query": OpenAIJSONProperty(type: "string", description: "Search query")
            ],
            required: ["query"]
        ),
    ]

    static let openAIRequestTools: [OpenAIRequestTool] = definitions.map(\.openAIRequestTool)
}

private struct OpenAIRequestTool: Encodable {
    let type: String
    let function: OpenAIRequestToolFunction
}

private struct OpenAIRequestToolFunction: Encodable {
    let name: String
    let description: String
    let parameters: OpenAIJSONSchema
}

private struct OpenAIJSONSchema: Encodable {
    let type: String
    let properties: [String: OpenAIJSONProperty]
    let required: [String]
}

private struct OpenAIJSONProperty: Encodable {
    let type: String
    let description: String
}

private func post<Req: Encodable, Res: Decodable>(
    baseURL: String,
    path: String,
    body: Req,
    userID: String,
    apiKey: String?,
    logger: Logger
) async throws -> Res {
    guard let url = URL(string: baseURL + path) else {
        throw URLError(.badURL)
    }

    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.setValue(userID, forHTTPHeaderField: "X-User-ID")
    req.mangox_applyDevTunnelHeadersIfNeeded(mangoxBaseURL: baseURL)
    if let apiKey, !apiKey.isEmpty {
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    }
    req.timeoutInterval = 300
    req.httpBody = try JSONEncoder().encode(body)

    let (data, response) = try await URLSession.shared.data(for: req)

    if let httpResponse = response as? HTTPURLResponse {
        logger.debug("\(path, privacy: .public) -> HTTP \(httpResponse.statusCode)")
        if httpResponse.statusCode >= 400 {
            let body = String(data: data, encoding: .utf8) ?? ""
            if !body.isEmpty {
                logger.error("Error body: \(body.prefix(500), privacy: .private)")
            }
            if body.localizedCaseInsensitiveContains("<!doctype") {
                throw CoachHTTPError.tunnelReturnedHTML(status: httpResponse.statusCode)
            }
            throw URLError(.badServerResponse)
        }
    }

    do {
        return try JSONDecoder().decode(Res.self, from: data)
    } catch {
        logger.error("Decode error for \(path, privacy: .public): \(error)")
        if let body = String(data: data, encoding: .utf8) {
            logger.error("Raw response: \(body.prefix(500), privacy: .private)")
        }
        throw error
    }
}
