import Foundation
import os.log

enum ChatProviderKind: String {
    case mangoxBackend

    var displayName: String {
        "Mangox Cloud"
    }

    var detail: String {
        "Managed cloud coach with rich responses, suggestions, and inline plan flow."
    }

    var capabilities: ChatProviderCapabilities {
        ChatProviderCapabilities(
            supportsStreaming: true,
            supportsToolCalls: true,
            supportsRichMetadata: true,
            supportsInlinePlans: true,
            supportsReferences: true
        )
    }
}

enum ChatProviderDefaultsKey {
    static let providerKind = "AIChatProvider"
    static let baseURL = "AIChatProviderBaseURL"
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

    var capabilities: ChatProviderCapabilities { kind.capabilities }
    var displayName: String { kind.displayName }
    var detail: String { kind.detail }
    var effectiveModel: String { "Managed coach" }
}

protocol ChatProviderAdapter {
    func streamChat(
        request: ChatRequest,
        configuration: ChatProviderConfiguration,
        userID: String
    ) -> AsyncThrowingStream<ChatRuntimeEvent, Error>
}

enum MangoxBackendBaseURLFormatting {
    static func normalizedRoot(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") {
            s.removeLast()
        }
        if s.lowercased().hasSuffix("/api") {
            s = String(s.dropLast(4))
            while s.hasSuffix("/") {
                s.removeLast()
            }
        }
        return s
    }
}

struct ChatProviderResolver {
    private enum Keys {
        static let baseURL = ChatProviderDefaultsKey.baseURL
        static let mangoxBaseURL = "MangoxAPIBaseURL"
    }

    func resolve(bundle: Bundle = .main, defaults: UserDefaults = .standard)
        -> ChatProviderConfiguration
    {
        let rawBaseURL = defaults.string(forKey: Keys.baseURL)
        let chosen =
            (rawBaseURL?.isEmpty == false ? rawBaseURL : nil)
            ?? bundle.object(forInfoDictionaryKey: Keys.mangoxBaseURL) as? String
            ?? "https://mangox-backend-production.up.railway.app"
        let baseURL = MangoxBackendBaseURLFormatting.normalizedRoot(chosen)

        return ChatProviderConfiguration(
            kind: .mangoxBackend,
            baseURL: baseURL
        )
    }
}

struct ChatProviderFactory {
    static func makeAdapter(for kind: ChatProviderKind) -> ChatProviderAdapter {
        switch kind {
        case .mangoxBackend:
            MangoxBackendChatProvider()
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
                                case "done", "meta":
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

private func post<Req: Encodable, Res: Decodable>(
    baseURL: String,
    path: String,
    body: Req,
    userID: String,
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
