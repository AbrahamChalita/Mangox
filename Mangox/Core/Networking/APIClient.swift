// Core/Networking/APIClient.swift
import Foundation

/// Testable networking contract used by Data layer DataSources.
/// Abstracts URLSession so DataSources can be unit-tested with a mock.
protocol APIClient: Sendable {
    /// Performs a one-shot request and returns the full response body.
    func data(for request: URLRequest) async throws -> (Data, URLResponse)

    /// Performs a streaming request and returns an async byte sequence.
    /// Used for SSE / chunked-transfer endpoints (e.g. coach streaming).
    func bytes(for request: URLRequest) async throws -> (URLSession.AsyncBytes, URLResponse)
}

// MARK: - Default URLSession implementation

extension URLSession: APIClient {
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await data(for: request, delegate: nil)
    }

    func bytes(for request: URLRequest) async throws -> (URLSession.AsyncBytes, URLResponse) {
        try await bytes(for: request, delegate: nil)
    }
}

// MARK: - Shared production client

extension APIClient where Self == URLSession {
    /// The shared URLSession configured for Mangox API calls.
    static var mangox: URLSession {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 120
        return URLSession(configuration: config)
    }
}

// MARK: - Common response validation

enum APIError: LocalizedError {
    case httpError(statusCode: Int, body: Data)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .httpError(let code, _): return "HTTP \(code)"
        case .invalidResponse: return "Invalid server response"
        }
    }
}

extension APIClient {
    /// Performs a request and throws `APIError.httpError` for non-2xx status codes.
    func validatedData(for request: URLRequest) async throws -> Data {
        let (data, response) = try await self.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.httpError(statusCode: http.statusCode, body: data)
        }
        return data
    }
}
