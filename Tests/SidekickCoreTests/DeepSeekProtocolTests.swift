import Foundation
import Testing
@testable import SidekickCore

@Test func requestEncodesBudgetToolChoiceAndUsageStreamOption() throws {
    let request = ModelRequest(
        systemPrompt: "current system",
        conversationMessages: [
            ChatMessage(role: .system, content: "stale"),
            ChatMessage(role: .user, content: "hello")
        ],
        maxTokens: 1_234,
        toolChoice: .none,
        includeUsage: true
    )
    let data = try JSONEncoder().encode(DeepSeekRequestBody(request: request))
    let root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let messages = try #require(root["messages"] as? [[String: Any]])
    let streamOptions = try #require(root["stream_options"] as? [String: Any])
    #expect(root["max_tokens"] as? Int == 1_234)
    #expect(root["tool_choice"] as? String == "none")
    #expect(streamOptions["include_usage"] as? Bool == true)
    #expect(messages.count == 2)
    #expect(messages.filter { $0["role"] as? String == "system" }.count == 1)
    #expect(messages.first?["content"] as? String == "current system")
}

@Test func usageOnlyChunkAndDoneAreParsedWithoutDuplicateCompletion() throws {
    let payload = #"{"choices":[],"usage":{"prompt_tokens":100,"completion_tokens":20,"total_tokens":120,"prompt_cache_hit_tokens":80,"prompt_cache_miss_tokens":20,"completion_tokens_details":{"reasoning_tokens":12}}}"#
    #expect(try DeepSeekClient.events(for: payload) == [
        .usage(TokenUsage(
            promptTokens: 100,
            completionTokens: 20,
            reasoningTokens: 12,
            cacheHitTokens: 80,
            cacheMissTokens: 20,
            totalTokens: 120
        ))
    ])
    #expect(try DeepSeekClient.events(for: "[DONE]").isEmpty)
}

@Test func allFinishReasonsMapExactlyOnce() throws {
    for reason in [
        ModelFinishReason.stop,
        .length,
        .toolCalls,
        .contentFilter,
        .insufficientSystemResource
    ] {
        let payload = #"{"choices":[{"delta":{},"finish_reason":"\#(reason.rawValue)"}]}"#
        #expect(try DeepSeekClient.events(for: payload) == [.finished(reason)])
    }
}

@Test func searchEvidenceIsStableValidAndWithinBudget() throws {
    let results = [
        TavilyResult(
            title: "low",
            url: "https://example.com/complete/path?q=1",
            content: String(repeating: "中文🙂", count: 3_000),
            score: 0.2
        ),
        TavilyResult(
            title: "high",
            url: "https://example.org/full/url",
            content: String(repeating: "evidence ", count: 2_000),
            score: 0.9,
            publishedDate: "2026-07-17"
        )
    ]
    let estimator = ContextEstimator()
    let encoded = try SearchEvidenceBuilder.encode(results, estimator: estimator)
    let decoded = try JSONDecoder().decode([SearchEvidence].self, from: Data(encoded.utf8))
    #expect(estimator.textTokens(encoded) <= ContextPolicy.searchEvidenceTokenBudget)
    #expect(decoded.first?.title == "high")
    #expect(decoded.first?.url == "https://example.org/full/url")
    #expect(decoded.first?.excerptTruncated == true)
}
