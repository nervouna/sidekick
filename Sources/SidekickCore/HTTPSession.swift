import Foundation

public enum SidekickHTTP {
    public static let requestTimeout: TimeInterval = 30
    public static let resourceTimeout: TimeInterval = 120

    public static func configuration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = requestTimeout
        configuration.timeoutIntervalForResource = resourceTimeout
        return configuration
    }

    public static func makeSession() -> URLSession {
        URLSession(configuration: configuration())
    }
}
