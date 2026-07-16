import Foundation
import Testing
@testable import SidekickCore

private final class MemorySecrets: SecretStoring, @unchecked Sendable {
    var values: [String: String] = [:]
    func read(account: String) throws -> String? { values[account] }
    func save(_ value: String, account: String) throws { values[account] = value }
    func delete(account: String) throws { values.removeValue(forKey: account) }
}

private struct FixedEnvironment: EnvironmentReading {
    let values: [String: String]
    func value(for name: String) -> String? { values[name] }
}

@Test func keychainOverridesEnvironmentAndEmptySaveDeletes() throws {
    let secrets = MemorySecrets()
    secrets.values[APIService.deepSeek.keychainAccount] = "keychain-value"
    let provider = KeyProvider(
        secrets: secrets,
        environment: FixedEnvironment(values: ["DEEPSEEK_API_KEY": "environment-value"])
    )
    #expect(try provider.key(for: .deepSeek) == "keychain-value")
    try provider.save("", for: .deepSeek)
    #expect(try provider.key(for: .deepSeek) == "environment-value")
}
