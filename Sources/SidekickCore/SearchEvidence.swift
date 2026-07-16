import Foundation

public struct SearchEvidence: Codable, Equatable, Sendable {
    public var title: String
    public var url: String
    public var score: Double
    public var publishedDate: String?
    public var excerpt: String
    public var excerptTruncated: Bool
}

public enum SearchEvidenceBuilder {
    public static func encode(
        _ results: [TavilyResult],
        estimator: ContextEstimator,
        tokenBudget: Int = ContextPolicy.searchEvidenceTokenBudget
    ) throws -> String {
        let sorted = results.enumerated().sorted { lhs, rhs in
            lhs.element.score == rhs.element.score
                ? lhs.offset < rhs.offset
                : lhs.element.score > rhs.element.score
        }.prefix(5)

        var evidence: [SearchEvidence] = []
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        for pair in sorted {
            let result = pair.element
            let characters = Array(result.content)
            var candidate = SearchEvidence(
                title: result.title,
                url: result.url,
                score: result.score,
                publishedDate: result.publishedDate,
                excerpt: result.content,
                excerptTruncated: false
            )

            if try fits(evidence + [candidate], encoder: encoder, estimator: estimator, budget: tokenBudget) {
                evidence.append(candidate)
                continue
            }

            var low = 0
            var high = characters.count
            var best: SearchEvidence?
            while low <= high {
                let middle = (low + high) / 2
                candidate.excerpt = String(characters.prefix(middle))
                candidate.excerptTruncated = middle < characters.count
                if try fits(evidence + [candidate], encoder: encoder, estimator: estimator, budget: tokenBudget) {
                    best = candidate
                    low = middle + 1
                } else {
                    high = middle - 1
                }
            }
            if let best { evidence.append(best) }
        }

        let data = try encoder.encode(evidence)
        guard let string = String(data: data, encoding: .utf8) else {
            throw SidekickError.invalidResponse("搜索证据无法编码为 UTF-8")
        }
        return string
    }

    private static func fits(
        _ evidence: [SearchEvidence],
        encoder: JSONEncoder,
        estimator: ContextEstimator,
        budget: Int
    ) throws -> Bool {
        let data = try encoder.encode(evidence)
        guard let string = String(data: data, encoding: .utf8) else { return false }
        return estimator.textTokens(string) <= budget
    }
}

struct ToolErrorPayload: Codable, Equatable {
    let error: ToolError

    struct ToolError: Codable, Equatable {
        let code: String
        let message: String
    }

    static func encoded(code: String, message: String) -> String {
        let payload = ToolErrorPayload(error: ToolError(code: code, message: message))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try? encoder.encode(payload)
        return data.flatMap { String(data: $0, encoding: .utf8) }
            ?? #"{"error":{"code":"search_budget_exhausted","message":"context budget exhausted"}}"#
    }
}
