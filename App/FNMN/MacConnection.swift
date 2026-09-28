import Foundation
import Security

struct MacConnection {
    let endpoint: URL
    let token: String
    let allowsInsecureLAN: Bool

    init(address: String, token: String, allowsInsecureLAN: Bool) throws {
        let address = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let endpoint = URL(string: address), endpoint.host != nil,
              endpoint.user == nil, endpoint.password == nil,
              endpoint.query == nil, endpoint.fragment == nil,
              CaptureRoute.acceptsService(endpoint, insecureLAN: allowsInsecureLAN) else {
            throw MacConnectionError.invalidAddress
        }
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { throw MacConnectionError.missingToken }
        self.endpoint = endpoint
        self.token = token
        self.allowsInsecureLAN = allowsInsecureLAN
    }
}

enum MacConnectionError: LocalizedError {
    case invalidAddress
    case missingToken
    case notConfigured
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidAddress: "Enter a valid HTTPS address, or enable local HTTP for a LAN address."
        case .missingToken: "Enter the Mac service token."
        case .notConfigured: "Set up the Mac connection first."
        case .keychain: "Couldn't save the Mac service token in Keychain."
        }
    }
}

protocol MacConnectionStorage {
    func load() -> MacConnection?
    func save(_ connection: MacConnection) throws
}

struct KeychainMacConnectionStore: MacConnectionStorage {
    private let addressKey = "macServiceAddress"
    private let localHTTPKey = "macServiceAllowsLocalHTTP"
    private let account = "macServiceToken"

    func load() -> MacConnection? {
        guard let address = UserDefaults.standard.string(forKey: addressKey),
              let token = readToken() else { return nil }
        return try? MacConnection(
            address: address,
            token: token,
            allowsInsecureLAN: UserDefaults.standard.bool(forKey: localHTTPKey)
        )
    }

    func save(_ connection: MacConnection) throws {
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
            guard added == errSecSuccess else { throw MacConnectionError.keychain(added) }
        } else if status != errSecSuccess {
            throw MacConnectionError.keychain(status)
        }
        UserDefaults.standard.set(connection.endpoint.absoluteString, forKey: addressKey)
        UserDefaults.standard.set(connection.allowsInsecureLAN, forKey: localHTTPKey)
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
