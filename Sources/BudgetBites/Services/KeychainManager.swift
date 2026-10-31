import Foundation
import Security

public final class KeychainManager {
    public static let shared = KeychainManager()
    
    private let service = "com.budgetbites.app.kroger"
    
    public enum Key: String {
        case accessToken = "kroger_access_token"
        case refreshToken = "kroger_refresh_token"
        case tokenExpiration = "kroger_token_expiration"
        case chosenStore = "kroger_chosen_store"
    }
    
    private init() {}
    
    // MARK: - Save Item
    @discardableResult
    public func save(_ data: Data, forKey key: Key) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue
        ]
        
        // Remove existing item before saving
        SecItemDelete(query as CFDictionary)
        
        var newQuery = query
        newQuery[kSecValueData as String] = data
        newQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        
        let status = SecItemAdd(newQuery as CFDictionary, nil)
        return status == errSecSuccess
    }
    
    @discardableResult
    public func saveString(_ string: String, forKey key: Key) -> Bool {
        guard let data = string.data(using: .utf8) else { return false }
        return save(data, forKey: key)
    }
    
    // MARK: - Retrieve Item
    public func getData(forKey key: Key) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: kCFBooleanTrue as Any,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        
        if status == errSecSuccess, let data = dataTypeRef as? Data {
            return data
        }
        return nil
    }
    
    public func getString(forKey key: Key) -> String? {
        guard let data = getData(forKey: key) else { return nil }
        return String(data: data, encoding: .utf8)
    }
    
    // MARK: - Delete Item
    @discardableResult
    public func delete(forKey key: Key) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
    
    public func clearAllTokens() {
        delete(forKey: .accessToken)
        delete(forKey: .refreshToken)
        delete(forKey: .tokenExpiration)
    }
}
