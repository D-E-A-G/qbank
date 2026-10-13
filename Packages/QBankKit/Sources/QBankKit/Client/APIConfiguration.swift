import Foundation

/// Where the QBank server lives. The production address is the only server fact in this repo.
public struct APIConfiguration: Sendable, Equatable {
    /// The live QBank server.
    public static let production = APIConfiguration(baseURL: URL(string: "https://qbank.dimitrygallego.com")!)

    public let baseURL: URL
    /// How long one request may wait for the server before it counts as no connection.
    public let timeout: TimeInterval

    public init(baseURL: URL, timeout: TimeInterval = 30) {
        self.baseURL = baseURL
        self.timeout = timeout
    }
}
