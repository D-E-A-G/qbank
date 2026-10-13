import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Sends one HTTP request. The client talks to the server only through this, so tests swap in
/// recorded responses and nothing in a test run reaches the network.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// The real transport. It keeps no cookies: the bearer token is the only session the app sends.
public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    public init(session: URLSession = URLSessionTransport.makeSession()) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, http)
    }

    /// An ephemeral session with no cookie storage and no URL cache, so a response never outlives the request.
    public static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }
}
