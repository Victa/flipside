//
//  KeychainService.swift
//  FlipSide
//
//  Secure storage wrapper for API keys and OAuth tokens using iOS Keychain.
//

import Foundation
import Security

/// Service for securely storing and retrieving sensitive data using iOS Keychain
final class KeychainService {
    
    // MARK: - Keychain Keys
    
    /// Predefined keys for common stored values
    enum KeychainKey: String {
        case openAIAPIKey = "com.flipside.openai.apikey"
        case discogsPersonalToken = "com.flipside.discogs.personaltoken"
        case discogsOAuthToken = "com.flipside.discogs.oauth.token"
        case discogsOAuthTokenSecret = "com.flipside.discogs.oauth.tokensecret"
        case discogsUsername = "com.flipside.discogs.username"
    }
    
    // MARK: - Error Types
    
    enum KeychainError: LocalizedError {
        case itemNotFound
        case duplicateItem
        case invalidData
        case unexpectedStatus(OSStatus)
        
        var errorDescription: String? {
            switch self {
            case .itemNotFound:
                return "The requested item was not found in the keychain"
            case .duplicateItem:
                return "An item with this key already exists in the keychain"
            case .invalidData:
                return "The data retrieved from the keychain is invalid"
            case .unexpectedStatus(let status):
                return "Keychain operation failed with status: \(status)"
            }
        }
    }
    
    // MARK: - Singleton
    
    static let shared = KeychainService()
    
    private init() {}
    
    // MARK: - Public API
    
    /// Save a string value to the keychain
    /// - Parameters:
    ///   - value: The string value to store
    ///   - key: The keychain key (use KeychainKey enum or custom string)
    /// - Throws: KeychainError if the operation fails
    func set(_ value: String, for key: KeychainKey) throws {
        try set(value, for: key.rawValue)
    }
    
    /// Save a string value to the keychain with a custom key
    /// - Parameters:
    ///   - value: The string value to store
    ///   - key: Custom string key
    /// - Throws: KeychainError if the operation fails
    func set(_ value: String, for key: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.invalidData
        }
        
        // Check if item already exists
        if (try? get(key)) != nil {
            // Update existing item
            try update(data, for: key)
        } else {
            // Add new item
            try add(data, for: key)
        }
    }
    
    /// Retrieve a string value from the keychain
    /// - Parameter key: The keychain key (use KeychainKey enum or custom string)
    /// - Returns: The stored string value, or nil if not found
    /// - Throws: KeychainError if the operation fails (excluding itemNotFound)
    func get(_ key: KeychainKey) throws -> String? {
        try get(key.rawValue)
    }
    
    /// Retrieve a string value from the keychain with a custom key
    /// - Parameter key: Custom string key
    /// - Returns: The stored string value, or nil if not found
    /// - Throws: KeychainError if the operation fails (excluding itemNotFound)
    func get(_ key: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let string = String(data: data, encoding: .utf8) else {
                throw KeychainError.invalidData
            }
            return string
            
        case errSecItemNotFound:
            return nil
            
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }
    
    /// Delete a value from the keychain
    /// - Parameter key: The keychain key (use KeychainKey enum or custom string)
    /// - Throws: KeychainError if the operation fails
    func delete(_ key: KeychainKey) throws {
        try delete(key.rawValue)
    }
    
    /// Delete a value from the keychain with a custom key
    /// - Parameter key: Custom string key
    /// - Throws: KeychainError if the operation fails
    func delete(_ key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        switch status {
        case errSecSuccess, errSecItemNotFound:
            // Success or item didn't exist (both are acceptable)
            return
            
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }
    
    /// Check if a value exists in the keychain
    /// - Parameter key: The keychain key to check
    /// - Returns: true if the key exists, false otherwise
    func exists(_ key: KeychainKey) -> Bool {
        exists(key.rawValue)
    }
    
    /// Check if a value exists in the keychain with a custom key
    /// - Parameter key: Custom string key to check
    /// - Returns: true if the key exists, false otherwise
    func exists(_ key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: false
        ]
        
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess
    }
    
    /// Delete all keychain items managed by this service
    /// - Warning: This will delete all stored API keys and tokens
    func deleteAll() throws {
        for key in KeychainKey.allCases {
            try? delete(key)
        }
    }
    
    // MARK: - Private Helpers
    
    private func add(_ data: Data, for key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        guard status == errSecSuccess else {
            if status == errSecDuplicateItem {
                throw KeychainError.duplicateItem
            }
            throw KeychainError.unexpectedStatus(status)
        }
    }
    
    private func update(_ data: Data, for key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        
        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]
        
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}

// MARK: - KeychainKey CaseIterable

extension KeychainService.KeychainKey: CaseIterable {}

// MARK: - Convenience Methods for Specific Keys

extension KeychainService {
    
    /// Get the OpenAI API key
    var openAIAPIKey: String? {
        try? get(.openAIAPIKey)
    }
    
    /// Set the OpenAI API key
    func setOpenAIAPIKey(_ key: String) throws {
        try set(key, for: .openAIAPIKey)
    }
    
    /// Get the Discogs personal access token
    var discogsPersonalToken: String? {
        try? get(.discogsPersonalToken)
    }
    
    /// Set the Discogs personal access token
    func setDiscogsPersonalToken(_ token: String) throws {
        try set(token, for: .discogsPersonalToken)
    }
    
    /// Get the Discogs OAuth token
    var discogsOAuthToken: String? {
        try? get(.discogsOAuthToken)
    }
    
    /// Set the Discogs OAuth token
    func setDiscogsOAuthToken(_ token: String) throws {
        try set(token, for: .discogsOAuthToken)
    }
    
    /// Get the Discogs OAuth token secret
    var discogsOAuthTokenSecret: String? {
        try? get(.discogsOAuthTokenSecret)
    }
    
    /// Set the Discogs OAuth token secret
    func setDiscogsOAuthTokenSecret(_ secret: String) throws {
        try set(secret, for: .discogsOAuthTokenSecret)
    }
    
    /// Get the Discogs username
    var discogsUsername: String? {
        try? get(.discogsUsername)
    }
    
    /// Set the Discogs username
    func setDiscogsUsername(_ username: String) throws {
        try set(username, for: .discogsUsername)
    }
    
    /// Check if API keys are configured (OpenAI required at minimum)
    var hasRequiredAPIKeys: Bool {
        openAIAPIKey != nil
    }
}
