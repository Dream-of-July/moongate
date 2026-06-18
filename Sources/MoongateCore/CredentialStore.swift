import Foundation

// MARK: - 凭证安全存储（SEC-CRED-001）

/// API Token 不再明文落进 settings.json，改存平台安全存储。
/// 实现由 App 注入（macOS = Keychain）；默认内存实现供 CLI/测试。与 Windows ICredentialStore 同构。
public protocol CredentialStore: Sendable {
    /// 取凭证；不存在返回 nil。
    func get(_ key: String) -> String?
    /// 写入/覆盖凭证；失败抛错（调用方据此保证「迁移失败不丢旧值」）。
    func set(_ key: String, _ value: String) throws
    /// 删除凭证（不存在时静默）。
    func delete(_ key: String)
}

/// 进程内内存实现：默认值 + 单测注入用，不持久化。
public final class InMemoryCredentialStore: CredentialStore, @unchecked Sendable {
    private var items: [String: String] = [:]
    private let lock = NSLock()
    public init() {}
    public func get(_ key: String) -> String? { lock.lock(); defer { lock.unlock() }; return items[key] }
    public func set(_ key: String, _ value: String) throws { lock.lock(); defer { lock.unlock() }; items[key] = value }
    public func delete(_ key: String) { lock.lock(); defer { lock.unlock() }; items[key] = nil }
}

#if canImport(Security)
import Security

/// macOS Keychain 凭证存储：每个 Token 作为通用密码项（kSecClassGenericPassword）存入登录钥匙串。
/// 仅本用户可读；settings.json 不再含明文。
public final class KeychainCredentialStore: CredentialStore, @unchecked Sendable {
    private let service: String
    public init(service: String = "moongate.credentials") { self.service = service }

    private func baseQuery(_ key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
    }

    public func get(_ key: String) -> String? {
        var query = baseQuery(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func set(_ key: String, _ value: String) throws {
        let data = Data(value.utf8)
        // 先尝试更新已存在项，不存在再新增。
        let update: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(baseQuery(key) as CFDictionary, update as CFDictionary)
        if updateStatus == errSecSuccess { return }
        if updateStatus == errSecItemNotFound {
            var add = baseQuery(key)
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(add as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw NSError(domain: NSOSStatusErrorDomain, code: Int(addStatus))
            }
            return
        }
        throw NSError(domain: NSOSStatusErrorDomain, code: Int(updateStatus))
    }

    public func delete(_ key: String) {
        SecItemDelete(baseQuery(key) as CFDictionary)
    }
}
#endif
