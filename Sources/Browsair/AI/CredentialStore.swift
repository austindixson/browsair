import Foundation
import Security

protocol CredentialStore: Sendable {
    func save(_ value: String, for key: String) throws
    func value(for key: String) throws -> String?
    func delete(_ key: String) throws
}

struct KeychainCredentialStore: CredentialStore {
    private let service = "com.browsair.ai"

    func save(_ value: String, for key: String) throws {
        let data = Data(value.utf8)
        SecItemDelete([kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: key] as CFDictionary)
        let status = SecItemAdd([kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: key, kSecValueData: data] as CFDictionary, nil)
        guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    }

    func value(for key: String) throws -> String? {
        var result: CFTypeRef?
        let status = SecItemCopyMatching([kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: key, kSecReturnData: true, kSecMatchLimit: kSecMatchLimitOne] as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
        return String(data: data, encoding: .utf8)
    }

    func delete(_ key: String) throws {
        let status = SecItemDelete([kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: key] as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    }
}
