import Foundation
import Testing
@testable import SidekickCore

@Test func parsesFragmentedUnicodeSSE() {
    let source = "data: {\"text\":\"你好\"}\n\ndata: [DONE]\n\n"
    let bytes = Array(source.utf8)
    var parser = SSEBuffer()
    var events: [String] = []
    for byte in bytes {
        events.append(contentsOf: parser.feed(Data([byte])))
    }
    #expect(events == ["{\"text\":\"你好\"}", "[DONE]"])
}

@Test func parsesCRLFAndMultipleDataLines() {
    var parser = SSEBuffer()
    let events = parser.feed(Data("data: first\r\ndata: second\r\n\r\n".utf8))
    #expect(events == ["first\nsecond"])
}
