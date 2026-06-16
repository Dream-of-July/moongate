import Foundation
import Security
import MoongateMobileCore

public struct IOSKeychainCredentialStore: SecureCredentialStore {
    public enum StoreError: Error, Equatable {
        case unexpectedStatus(OSStatus)
    }

    public init() {}

    public func saveCredential(
        _ secret: String,
        for reference: SecureCredentialReference
    ) async throws -> SecureCredentialReference {
        let data = Data(secret.utf8)
        let query = baseQuery(for: reference)
        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw StoreError.unexpectedStatus(status)
        }
        return reference
    }

    public func deleteCredential(_ reference: SecureCredentialReference) async throws {
        let status = SecItemDelete(baseQuery(for: reference) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw StoreError.unexpectedStatus(status)
        }
    }

    public func hasCredential(_ reference: SecureCredentialReference) async throws -> Bool {
        var query = baseQuery(for: reference)
        query[kSecReturnData as String] = kCFBooleanFalse
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        let status = SecItemCopyMatching(query as CFDictionary, nil)
        if status == errSecSuccess {
            return true
        }
        if status == errSecItemNotFound {
            return false
        }
        throw StoreError.unexpectedStatus(status)
    }

    public func credential(for reference: SecureCredentialReference) async throws -> String? {
        var query = baseQuery(for: reference)
        query[kSecReturnData as String] = kCFBooleanTrue
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw StoreError.unexpectedStatus(status)
        }
        guard let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private func baseQuery(for reference: SecureCredentialReference) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: reference.service,
            kSecAttrAccount as String: reference.account
        ]
    }
}
