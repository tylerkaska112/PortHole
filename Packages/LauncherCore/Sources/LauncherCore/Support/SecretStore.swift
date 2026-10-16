// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
import Foundation
import Security

/// Somewhere to keep secrets (certificates and their passwords). The Keychain on a device; memory in tests.
public protocol SecretStore: Sendable {
    func load(_ key: String) -> Data?
    func save(_ data: Data, for key: String) throws
    func remove(_ key: String)
}

public struct KeychainSecretStore: SecretStore {
    private let service: String

    public init(service: String = BuildIdentity.keychainService) { self.service = service }

    private func query(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: key]
    }

    public func load(_ key: String) -> Data? {
        var q = query(key)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        return SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess ? out as? Data : nil
    }

    public func save(_ data: Data, for key: String) throws {
        SecItemDelete(query(key) as CFDictionary)
        var q = query(key)
        q[kSecValueData as String] = data
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(q as CFDictionary, nil)
        guard status == errSecSuccess else { throw SecretStoreError.keychain(status) }
    }

    public func remove(_ key: String) { SecItemDelete(query(key) as CFDictionary) }
}

public enum SecretStoreError: Error, LocalizedError {
    case keychain(OSStatus)
    case file(String)
    public var errorDescription: String? {
        switch self {
        case .keychain(let status): "The Keychain refused to save (error \(status))."
        case .file(let detail): "Couldn't save the secret (\(detail))."
        }
    }
}

/// A protected file in Application Support: the fallback for a re-signed build that lost its keychain entitlement (the same
/// reason HomeControl and CC2 Slicer have one).
public struct FileSecretStore: SecretStore {
    private let directory: URL

    public init(directory: URL = FileStorage.defaultURL("Secrets")) { self.directory = directory }

    private func url(_ key: String) -> URL { directory.appendingPathComponent(key.replacingOccurrences(of: "/", with: "_") + ".secret") }

    public func load(_ key: String) -> Data? { try? Data(contentsOf: url(key)) }

    public func save(_ data: Data, for key: String) throws {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: url(key), options: [.atomic, .completeFileProtectionUnlessOpen])
            var values = URLResourceValues(); values.isExcludedFromBackup = true
            var target = url(key); try? target.setResourceValues(values)
        } catch { throw SecretStoreError.file(error.localizedDescription) }
    }

    public func remove(_ key: String) { try? FileManager.default.removeItem(at: url(key)) }
}

/// Tries the Keychain first and falls back to a protected file when it refuses.
public struct ResilientSecretStore: SecretStore {
    public let primary: any SecretStore
    public let fallback: any SecretStore

    public init(primary: any SecretStore = KeychainSecretStore(), fallback: any SecretStore = FileSecretStore()) { self.primary = primary; self.fallback = fallback }

    public func load(_ key: String) -> Data? { primary.load(key) ?? fallback.load(key) }

    public func save(_ data: Data, for key: String) throws {
        do { try primary.save(data, for: key); fallback.remove(key) }
        catch { try fallback.save(data, for: key) }
    }

    public func remove(_ key: String) { primary.remove(key); fallback.remove(key) }
}

public final class MemorySecretStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String: Data] = [:]
    public init() {}
    public func load(_ key: String) -> Data? { lock.withLock { items[key] } }
    public func save(_ data: Data, for key: String) throws { lock.withLock { items[key] = data } }
    public func remove(_ key: String) { lock.withLock { _ = items.removeValue(forKey: key) } }
}
