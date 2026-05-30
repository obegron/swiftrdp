import Foundation
import Security

enum KeychainPasswordStore {
    private static let service = "SwiftRDP"

    static func password(host: String, port: Int32, user: String) -> String? {
        var query = baseQuery(host: host, port: port, user: user)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    static func save(_ password: String, host: String, port: Int32, user: String) {
        guard let data = password.data(using: .utf8) else {
            return
        }

        let query = baseQuery(host: host, port: port, user: user)
        let update = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecSuccess {
            return
        }

        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    static func delete(host: String, port: Int32, user: String) {
        SecItemDelete(baseQuery(host: host, port: port, user: user) as CFDictionary)
    }

    private static func baseQuery(host: String, port: Int32, user: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "\(host):\(port)|\(user)"
        ]
    }
}
