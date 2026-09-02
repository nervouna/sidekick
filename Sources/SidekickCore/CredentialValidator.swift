import Foundation

public struct CredentialValidator: Sendable {
    private let session: URLSession

    public init(session: URLSession = SidekickHTTP.makeSession()) {
        self.session = session
    }

    public func validate(_ key: String, for service: APIService) async throws {
        let url: URL
        switch service {
        case .deepSeek: url = URL(string: "https://api.deepseek.com/models")!
        case .tavily: url = URL(string: "https://api.tavily.com/usage")!
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SidekickError.invalidResponse("没有 HTTP 状态码")
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data.prefix(2_048), encoding: .utf8) ?? "未知错误"
            throw SidekickError.http(status: http.statusCode, message: message)
        }
    }
}
