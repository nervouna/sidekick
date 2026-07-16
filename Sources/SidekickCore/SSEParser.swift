import Foundation

public struct SSEBuffer: Sendable {
    private var buffer = Data()

    public init() {}

    public mutating func feed(_ data: Data) -> [String] {
        buffer.append(data)
        var events: [String] = []

        while let boundary = Self.eventBoundary(in: buffer) {
            let eventData = buffer.subdata(in: 0..<boundary.range.lowerBound)
            buffer.removeSubrange(0..<boundary.range.upperBound)
            guard let text = String(data: eventData, encoding: .utf8) else { continue }
            let payload = text
                .split(whereSeparator: \Character.isNewline)
                .filter { $0.hasPrefix("data:") }
                .map { line -> String in
                    var value = String(line.dropFirst(5))
                    if value.first == " " { value.removeFirst() }
                    return value
                }
                .joined(separator: "\n")
            if !payload.isEmpty { events.append(payload) }
        }
        return events
    }

    public mutating func finish() -> [String] {
        guard !buffer.isEmpty else { return [] }
        let suffix = Data("\n\n".utf8)
        return feed(suffix)
    }

    private static func eventBoundary(in data: Data) -> (range: Range<Data.Index>, length: Int)? {
        if let range = data.range(of: Data("\r\n\r\n".utf8)) { return (range, 4) }
        if let range = data.range(of: Data("\n\n".utf8)) { return (range, 2) }
        return nil
    }
}
