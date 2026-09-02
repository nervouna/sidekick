import Foundation

public protocol TavilySearching: Sendable {
    func search(query: String, apiKey: String) async throws -> [TavilyResult]
}

public struct TavilyClient: TavilySearching, Sendable {
    public static let endpoint = URL(string: "https://api.tavily.com/search")!

    private let session: URLSession
    private let endpoint: URL

    public init(session: URLSession = SidekickHTTP.makeSession(), endpoint: URL = Self.endpoint) {
        self.session = session
        self.endpoint = endpoint
    }

    public func search(query: String, apiKey: String) async throws -> [TavilyResult] {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(SearchRequest(query: query))
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SidekickError.invalidResponse("Tavily 没有返回 HTTP 状态码")
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data.prefix(8_192), encoding: .utf8) ?? "未知错误"
            throw SidekickError.http(status: http.statusCode, message: message)
        }
        do {
            return try JSONDecoder().decode(SearchResponse.self, from: data).results
        } catch {
            throw SidekickError.invalidResponse("无法解析 Tavily 搜索结果")
        }
    }
}

private struct SearchRequest: Encodable {
    let query: String
    let searchDepth = "basic"
    let maxResults = 5
    let includeAnswer = false
    let includeRawContent = false

    enum CodingKeys: String, CodingKey {
        case query
        case searchDepth = "search_depth"
        case maxResults = "max_results"
        case includeAnswer = "include_answer"
        case includeRawContent = "include_raw_content"
    }
}

private struct SearchResponse: Decodable {
    let results: [TavilyResult]
}

extension TavilyResult {
    enum CodingKeys: String, CodingKey {
        case title, url, content, score
        case publishedDate = "published_date"
    }
}
