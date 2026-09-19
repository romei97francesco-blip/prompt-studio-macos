import Foundation
import Security

enum KeychainStore {
    static let service = "it.promptstudio.mac.openrouter"
    static let account = "openrouter-api-key"

    static func load(service: String = service, account: String = account) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ value: String, service: String = service, account: String = account) throws {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            try delete(service: service, account: account)
            return
        }
        let lookup: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let data = Data(value.utf8)
        let updateStatus = SecItemUpdate(lookup as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var item = lookup
            item[kSecValueData as String] = data
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw failure(addStatus) }
        } else if updateStatus != errSecSuccess {
            throw failure(updateStatus)
        }
    }

    static func delete(service: String = service, account: String = account) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw failure(status) }
    }

    private static func failure(_ status: OSStatus) -> NSError {
        let message = SecCopyErrorMessageString(status, nil) as String? ?? "errore sconosciuto"
        return NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Portachiavi: \(message)"])
    }
}
