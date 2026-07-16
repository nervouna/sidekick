import Foundation
import Security

public enum APIService: String, CaseIterable, Sendable {
    case deepSeek = "DeepSeek"
    case tavily = "Tavily"

    public var environmentName: String {
        switch self {
        case .deepSeek: "DEEPSEEK_API_KEY"
        case .tavily: "TAVILY_API_KEY"
        }
    }

    public var keychainAccount: String { rawValue.lowercased() }
}

public protocol SecretStoring: Sendable {
    func read(account: String) throws -> String?
    func save(_ value: String, account: String) throws
    func delete(account: String) throws
}

public protocol EnvironmentReading: Sendable {
    func value(for name: String) -> String?
}

public struct ProcessEnvironment: EnvironmentReading {
    public init() {}
    public func value(for name: String) -> String? { ProcessInfo.processInfo.environment[name] }
}

public enum KeychainError: LocalizedError, Sendable {
    case status(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .status(let status):
            return SecCopyErrorMessageString(status, nil) as String? ?? "Keychain error \(status)"
        }
    }
}

public struct KeychainStore: SecretStoring {
    public let serviceName: String

    public init(serviceName: String = "io.damao.sidekick") {
        self.serviceName = serviceName
    }

    public func read(account: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError.status(status) }
        guard let data = item as? Data, let value = String(data: data, encoding: .utf8) else { return nil }
        return value
    }

    public func save(_ value: String, account: String) throws {
        let key: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [kSecValueData as String: Data(value.utf8)]
        let updateStatus = SecItemUpdate(key as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var item = key
            item[kSecValueData as String] = Data(value.utf8)
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError.status(addStatus) }
        } else if updateStatus != errSecSuccess {
            throw KeychainError.status(updateStatus)
        }
    }

    public func delete(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError.status(status) }
    }
}

public struct KeyProvider: Sendable {
    private let secrets: any SecretStoring
    private let environment: any EnvironmentReading

    public init(secrets: any SecretStoring = KeychainStore(), environment: any EnvironmentReading = ProcessEnvironment()) {
        self.secrets = secrets
        self.environment = environment
    }

    public func key(for service: APIService) throws -> String? {
        if let value = try secrets.read(account: service.keychainAccount), !value.isEmpty { return value }
        if let value = environment.value(for: service.environmentName), !value.isEmpty { return value }
        return nil
    }

    public func keychainValue(for service: APIService) throws -> String? {
        try secrets.read(account: service.keychainAccount)
    }

    public func save(_ value: String, for service: APIService) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            try secrets.delete(account: service.keychainAccount)
        } else {
            try secrets.save(trimmed, account: service.keychainAccount)
        }
    }

    public func delete(_ service: APIService) throws {
        try secrets.delete(account: service.keychainAccount)
    }
}
