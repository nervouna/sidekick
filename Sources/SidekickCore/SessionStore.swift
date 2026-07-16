import Foundation

public protocol DateProviding: Sendable {
    func now() -> Date
}

public struct SystemDateProvider: DateProviding {
    public init() {}
    public func now() -> Date { Date() }
}

public enum SessionExpiry {
    public static let timeout: TimeInterval = 60 * 60

    public static func isExpired(_ session: ChatSession, at now: Date, timeout: TimeInterval = timeout) -> Bool {
        guard let lastMessageAt = session.lastMessageAt else { return false }
        return now.timeIntervalSince(lastMessageAt) >= timeout
    }
}

public enum PopoverLayout {
    public static func height(forContentHeight contentHeight: Double) -> Double {
        min(800, max(400, contentHeight + 190))
    }
}

public final class SessionStore: @unchecked Sendable {
    public let fileURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(fileURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.fileURL = base.appendingPathComponent("Sidekick/current-session.json")
        }
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    public func load(now: Date = Date()) throws -> ChatSession {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return ChatSession(createdAt: now)
        }
        let data = try Data(contentsOf: fileURL)
        let session = try decoder.decode(ChatSession.self, from: data)
        if SessionExpiry.isExpired(session, at: now) {
            try delete()
            return ChatSession(createdAt: now)
        }
        return session
    }

    public func save(_ session: ChatSession) throws {
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encoder.encode(session)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }

    public func delete() throws {
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        try fileManager.removeItem(at: fileURL)
    }
}
