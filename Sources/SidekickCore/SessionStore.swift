import Foundation

public protocol DateProviding: Sendable {
    func now() -> Date
}

public struct SystemDateProvider: DateProviding {
    public init() {}
    public func now() -> Date { Date() }
}

public enum SessionExpiry {
    public static let timeout: TimeInterval = ContextPolicy.sessionExpiry

    public static func isExpired(_ session: ChatSession, at now: Date, timeout: TimeInterval = timeout) -> Bool {
        guard let lastMessageAt = session.lastMessageAt else { return false }
        return now.timeIntervalSince(lastMessageAt) >= timeout
    }
}

public enum PopoverLayout {
    public static let width: Double = 400
    public static let minimumHeight: Double = 400
    public static let maximumHeight: Double = 800
    public static let dividerHeight: Double = 1

    public static func height(forContentHeight contentHeight: Double, chromeHeight: Double) -> Double {
        let content = contentHeight.isFinite ? max(0, contentHeight) : 0
        let chrome = chromeHeight.isFinite ? max(0, chromeHeight) : 0
        let desiredHeight = content + chrome + (dividerHeight * 2)
        return min(maximumHeight, max(minimumHeight, desiredHeight))
    }
}

public protocol SessionStoring: Sendable {
    func load(now: Date) throws -> ChatSession
    func save(_ session: ChatSession) throws
    func delete() throws
}

public final class SessionStore: SessionStoring, @unchecked Sendable {
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
