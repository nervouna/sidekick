import Foundation
import Testing
@testable import SidekickCore

@Test func sessionExpiresAtSixtyMinuteBoundary() {
    let start = Date(timeIntervalSince1970: 1_000)
    let session = ChatSession(createdAt: start, lastMessageAt: start)
    #expect(!SessionExpiry.isExpired(session, at: start.addingTimeInterval(3_599)))
    #expect(SessionExpiry.isExpired(session, at: start.addingTimeInterval(3_600)))
}

@Test func sessionStoreRestoresAndDeletesExpiredSession() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let url = directory.appendingPathComponent("current-session.json")
    let store = SessionStore(fileURL: url)
    let start = Date(timeIntervalSince1970: 10_000)
    var session = ChatSession(createdAt: start)
    session.append(ChatMessage(role: .user, content: "hello", createdAt: start), now: start)
    try store.save(session)

    #expect(try store.load(now: start.addingTimeInterval(60)).messages.count == 1)
    let expired = try store.load(now: start.addingTimeInterval(3_600))
    #expect(expired.messages.isEmpty)
    #expect(!FileManager.default.fileExists(atPath: url.path))
}

@Test func popoverHeightIsClamped() {
    #expect(PopoverLayout.height(forContentHeight: 0) == 400)
    #expect(PopoverLayout.height(forContentHeight: 310) == 500)
    #expect(PopoverLayout.height(forContentHeight: 1_000) == 800)
}
