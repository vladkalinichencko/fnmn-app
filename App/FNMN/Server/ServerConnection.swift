import FNMNCore
import Foundation
import Security

struct ServerConnection {
    let endpoint: URL
    let token: String

    init(address: String, token: String) throws {
        let address = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let endpoint = URL(string: address), endpoint.host != nil,
              endpoint.user == nil, endpoint.password == nil,
              endpoint.query == nil, endpoint.fragment == nil,
              CaptureRoute.acceptsService(endpoint) else {
            throw ServerConnectionError.invalidAddress
        }
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { throw ServerConnectionError.missingToken }
        self.endpoint = endpoint
        self.token = token
    }
}

enum ServerConnectionError: LocalizedError {
    case invalidAddress
    case missingToken
    case notConfigured
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidAddress: "Enter the HTTPS address of the server."
        case .missingToken: "Enter the server token."
        case .notConfigured: "Set up the server connection first."
        case .keychain: "Couldn't save the server token in Keychain."
        }
    }
}

protocol ServerConnectionStorage {
    func load() -> ServerConnection?
    func save(_ connection: ServerConnection) throws
}

struct KeychainServerConnectionStore: ServerConnectionStorage {
    private let addressKey = "macServiceAddress"
    private let account = "macServiceToken"

    func load() -> ServerConnection? {
        guard let address = UserDefaults.standard.string(forKey: addressKey),
              let token = readToken() else { return nil }
        return try? ServerConnection(address: address, token: token)
    }

    func save(_ connection: ServerConnection) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Bundle.main.bundleIdentifier ?? "local.fnmn.reader",
            kSecAttrAccount as String: account
        ]
        let data = Data(connection.token.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let added = SecItemAdd(item as CFDictionary, nil)
            guard added == errSecSuccess else { throw ServerConnectionError.keychain(added) }
        } else if status != errSecSuccess {
            throw ServerConnectionError.keychain(status)
        }
        UserDefaults.standard.set(connection.endpoint.absoluteString, forKey: addressKey)
    }

    private func readToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Bundle.main.bundleIdentifier ?? "local.fnmn.reader",
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var value: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &value) == errSecSuccess,
              let data = value as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
