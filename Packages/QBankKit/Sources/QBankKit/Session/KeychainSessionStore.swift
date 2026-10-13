#if canImport(Security)
import Foundation
import Security

/// Keeps the session in the Keychain as one generic password item under `<bundle id>.session`,
/// readable after the first unlock and never synced or moved to another device.
public struct KeychainSessionStore: SessionStore {
    public let service: String
    public let account: String

    /// - Parameters:
    ///   - service: The Keychain service. Defaults to `<bundle id>.session`.
    ///   - account: The item's account name inside that service.
    public init(service: String = KeychainSessionStore.defaultService(), account: String = "session") {
        self.service = service
        self.account = account
    }

    public static func defaultService(bundle: Bundle = .main) -> String {
        "\(bundle.bundleIdentifier ?? "QBank").session"
    }

    public func load() throws(StorageError) -> StoredSession? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw StorageError(operation: "read session", reason: Self.message(status), status: status)
        }
        do {
            return try QBankJSON.decoder.decode(StoredSession.self, from: data)
        } catch {
            throw StorageError(operation: "read session", reason: "the saved session cannot be read")
        }
    }

    public func save(_ session: StoredSession) throws(StorageError) {
        let data: Data
        do {
            data = try QBankJSON.encoder.encode(session)
        } catch {
            throw StorageError(operation: "save session", reason: "the session cannot be encoded")
        }
        let update: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        var status = SecItemUpdate(baseQuery() as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var add = baseQuery()
            add.merge(update) { _, new in new }
            status = SecItemAdd(add as CFDictionary, nil)
        }
        guard status == errSecSuccess else {
            throw StorageError(operation: "save session", reason: Self.message(status), status: status)
        }
    }

    public func clear() throws(StorageError) {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw StorageError(operation: "clear session", reason: Self.message(status), status: status)
        }
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false,
        ]
    }

    private static func message(_ status: OSStatus) -> String {
        (SecCopyErrorMessageString(status, nil) as String?) ?? "Keychain error"
    }
}
#endif
