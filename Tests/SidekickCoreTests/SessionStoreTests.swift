import Foundation
import Testing
@testable import SidekickCore

@Test func sessionExpiresAtThirtyMinuteBoundary() {
    let start = Date(timeIntervalSince1970: 1_000)
    let session = ChatSession(createdAt: start, lastMessageAt: start)
    #expect(!SessionExpiry.isExpired(session, at: start.addingTimeInterval(1_799)))
    #expect(SessionExpiry.isExpired(session, at: start.addingTimeInterval(1_800)))
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
    let expired = try store.load(now: start.addingTimeInterval(1_800))
    #expect(expired.messages.isEmpty)
    #expect(!FileManager.default.fileExists(atPath: url.path))
}

@Test func popoverHeightIsClamped() {
    #expect(PopoverLayout.width == 400)
    #expect(PopoverLayout.height(forContentHeight: -50, chromeHeight: 150) == 400)
    #expect(PopoverLayout.height(forContentHeight: 0, chromeHeight: 150) == 400)
    #expect(PopoverLayout.height(forContentHeight: 348, chromeHeight: 150) == 500)
    #expect(PopoverLayout.height(forContentHeight: 648, chromeHeight: 150) == 800)
    #expect(PopoverLayout.height(forContentHeight: 1_000, chromeHeight: 150) == 800)
    #expect(PopoverLayout.height(forContentHeight: .infinity, chromeHeight: 150) == 400)
}

@Test func legacySessionWithoutCompletionStateStillDecodesAsComplete() throws {
    let json = #"{"createdAt":"2026-07-17T00:00:00Z","id":"00000000-0000-0000-0000-000000000001","messages":[{"content":"answer","createdAt":"2026-07-17T00:00:00Z","id":"00000000-0000-0000-0000-000000000002","role":"assistant"}]}"#
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let session = try decoder.decode(ChatSession.self, from: Data(json.utf8))
    #expect(session.messages.first?.completionState == nil)
}
