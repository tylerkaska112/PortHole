// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
import Foundation

/// The connection every store's traffic goes through (Epic, GOG, itch.io, Steam's cloud saves).
///
/// iOS's shared connection keeps a cache on disk (Library/Caches/<app>/Cache.db) with the request headers, the address (a token in a query string) and the answer
/// (fresh tokens), and a Windows program running inside Porthole can open that file. This one keeps nothing: no disk cache, no cookies, no stored credentials.
enum StoreNetwork {
    static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = 60
        configuration.httpMaximumConnectionsPerHost = 32   // Epic's chunks come from one CDN host; the default of 4-6 limited a download to that many at once
        return URLSession(configuration: configuration)
    }()

    /// The same, for a download that is handled by a delegate (a game file).
    static func configuration(timeout: TimeInterval = 60) -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = timeout
        return configuration
    }

    /// Versions up to 0.50.284 sent store traffic through the shared connection, so its cache may hold tokens. Emptied once (the game art is fetched again).
    static func purgeOldCache() {
        let key = "f4.networkCachePurged.1"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        URLCache.shared.removeAllCachedResponses()
        if let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            for name in (try? FileManager.default.contentsOfDirectory(atPath: caches.path)) ?? [] {
                // The system's cache database folder is named after the app (and its files are Cache.db*).
                let folder = caches.appendingPathComponent(name, isDirectory: true)
                for file in (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [] where file.hasPrefix("Cache.db") {
                    try? FileManager.default.removeItem(at: folder.appendingPathComponent(file))
                }
                if name.hasPrefix("Cache.db") { try? FileManager.default.removeItem(at: folder) }
            }
        }
        UserDefaults.standard.set(true, forKey: key)
        LogStore.shared.log("[security] the old network cache was emptied")
    }
}
