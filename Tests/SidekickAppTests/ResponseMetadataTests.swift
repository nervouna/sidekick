import Foundation
import Testing
@testable import SidekickApp

@Test func responseMetadataUsesRelativeSameDayAndFullDateTimeTiers() {
    let date = Date(timeIntervalSince1970: 1_787_788_800)
    let taipei = TimeZone(secondsFromGMT: 8 * 60 * 60)!
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = taipei

    #expect(ResponseMetadataFormatter.timestamp(
        date,
        now: date.addingTimeInterval(20),
        calendar: calendar,
        timeZone: taipei
    ) == "刚刚")
    #expect(ResponseMetadataFormatter.timestamp(
        date,
        now: date.addingTimeInterval(5 * 60),
        calendar: calendar,
        timeZone: taipei
    ) == "5 分钟前")
    #expect(ResponseMetadataFormatter.timestamp(
        date,
        now: date.addingTimeInterval(2 * 60 * 60),
        calendar: calendar,
        timeZone: taipei
    ) == "08:00")
    #expect(ResponseMetadataFormatter.timestamp(
        date,
        now: date.addingTimeInterval(24 * 60 * 60),
        calendar: calendar,
        timeZone: taipei
    ) == "2026-08-27 08:00")
}

@Test func responseMetadataUsesWholeNumberTokenAbbreviations() {
    #expect(ResponseMetadataFormatter.tokens(999) == "999 tokens")
    #expect(ResponseMetadataFormatter.tokens(1_000) == "1,000 tokens")
    #expect(ResponseMetadataFormatter.tokens(1_223) == "1,223 tokens")
    #expect(ResponseMetadataFormatter.tokens(9_999) == "9,999 tokens")
    #expect(ResponseMetadataFormatter.tokens(10_000) == "10K tokens")
    #expect(ResponseMetadataFormatter.tokens(10_520) == "11K tokens")
    #expect(ResponseMetadataFormatter.tokens(1_000_000) == "1M tokens")
}
