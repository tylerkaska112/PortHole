// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
// Downloads a game from Steam into the Wine prefix: asks Steam for the app's Windows depots, their keys and manifests, fetches
// every chunk from Steam's content servers, decrypts, unpacks and verifies it, writes the files, and finally records the game
// the way Steam does (steamapps/appmanifest_<id>.acf) so it shows up as installed. Resumes where it stopped.
import Foundation

struct SteamDownloadProgress: Equatable {
    enum Phase: Equatable { case preparing, downloading, finishing }
    var phase = Phase.preparing
    var doneBytes: UInt64 = 0
    var totalBytes: UInt64 = 0
    var bytesPerSecond: Double = 0
    var fraction: Double { totalBytes == 0 ? 0 : min(1, Double(doneBytes) / Double(totalBytes)) }
    var secondsLeft: Double? { bytesPerSecond > 1 ? Double(totalBytes - min(doneBytes, totalBytes)) / bytesPerSecond : nil }

    init() {}
    init(doneBytes: UInt64, totalBytes: UInt64, bytesPerSecond: Double) {
        phase = .downloading; self.doneBytes = doneBytes; self.totalBytes = totalBytes; self.bytesPerSecond = bytesPerSecond
    }
}

final class SteamInstaller {
    enum State: Equatable {
        case idle
        case preparing(String)
        case downloading(SteamDownloadProgress)
        case finished
        case failed(String)
        case cancelled

        var isFinal: Bool { switch self { case .finished, .failed, .cancelled: return true; default: return false } }
    }

    let appid: Int
    let name: String
    private(set) var state: State = .idle { didSet { if oldValue != state { onState?(state) } } }
    var onState: ((State) -> Void)?
    /// Tests can shrink these.
    var parallelChunks = 24
    /// Tests turn this off to keep the number in flight fixed.
    var adaptive = true
    var retriesPerChunk = 4
    var freeSpaceOverride: (() -> Int64?)?

    /// The `steamapps` folder the game goes into (its `common` folder holds the files, `appmanifest_<id>.acf` records the install).
    private let steamApps: URL
    private let backend: SteamContentBackend
    private let fm: FileManager
    private var token = 0

    // Everything below is guarded by `lock` once downloading starts.
    private let lock = NSLock()
    private var cancelled = false
    private var failure: String?
    private var written: UInt64 = 0
    private var networkBytes: UInt64 = 0
    private var rejected = 0
    private var currentTarget = 0
    private var lastPerfLog = Date.distantPast
    private var samples: [(time: Date, bytes: UInt64)] = []
    private var pendingDone: [UInt32] = []
    private var descriptors: [Int: Int32] = [:]
    private var remaining: [Int: Int] = [:]
    private var progressTimer: Timer?
    private var total: UInt64 = 0

    private struct Item { var depot: Int; var file: Int; var chunk: Int; var global: UInt32 }
    private var manifests: [SteamManifest] = []
    private var keys: [Data] = []
    private var servers: [SteamCDNServer] = []
    private var hostBook = SteamHostBook(hosts: [])
    private var statChunks = 0, statNet = 0.0, statDecode = 0.0, statWrite = 0.0      // per-chunk time, summed between two log lines
    private(set) var gameFolder = URL(fileURLWithPath: "/")
    private var progressFolder = URL(fileURLWithPath: "/")
    private(set) var installInfo: SteamAppInfo?
    /// The account that owns the game, written into the install record the way Steam does.
    var ownerSteamID: String?

    init(appid: Int, name: String, steamApps: URL, backend: SteamContentBackend, fileManager: FileManager = .default) {
        self.appid = appid; self.name = name; self.steamApps = steamApps; self.backend = backend; fm = fileManager
    }

    /// Where a download keeps what it has finished, so it can continue later.
    static func progressFolder(appID: Int, steamApps: URL) -> URL { steamApps.appendingPathComponent("downloading/\(appID)") }
    static func hasPartialDownload(appID: Int, steamApps: URL) -> Bool {
        let done = progressFolder(appID: appID, steamApps: steamApps).appendingPathComponent("done.bin")
        return ((try? done.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0) > 0
    }

    // MARK: Start and stop

    func start() {
        guard state == .idle || state.isFinal else { return }
        token += 1
        lock.lock(); cancelled = false; failure = nil; written = 0; networkBytes = 0; rejected = 0; lastPerfLog = Date(); samples = []; pendingDone = []; descriptors = [:]; remaining = [:]; lock.unlock()
        state = .preparing("Asking Steam about \(name)…")
        SteamLog.event("Steam download: starting app \(appid).")
        prepare(token)
    }

    func cancel() {
        guard !state.isFinal else { return }
        lock.lock(); cancelled = true; lock.unlock()
        token += 1
        progressTimer?.invalidate(); progressTimer = nil
        closeAll(); flushProgress()
        backend.close()
        state = .cancelled
        SteamLog.event("Steam download: cancelled (what was downloaded is kept, so it can resume).")
    }

    private func fail(_ message: String, _ id: Int) {
        guard id == token, !state.isFinal else { return }
        progressTimer?.invalidate(); progressTimer = nil
        lock.lock(); cancelled = true; lock.unlock()
        closeAll(); flushProgress()
        backend.close()
        SteamLog.event("Steam download failed: \(message)")
        state = .failed(message)
    }

    // MARK: Preparing: app info, keys, manifests

    private func prepare(_ id: Int) {
        backend.appInfo(appid) { [weak self] result in
            guard let self, id == self.token else { return }
            switch result {
            case .failure(let error): self.fail(error.notOwned ? "Steam does not list \(self.name) for this account." : error.message, id)
            case .success(let info):
                self.installInfo = info
                let depots = SteamDepotPlanner.windowsDepots(app: info)
                guard !depots.isEmpty else { self.fail("\(self.name) has no Windows version on Steam.", id); return }
                self.resolveManifests(depots, info: info, id)
            }
        }
    }

    private func resolveManifests(_ depots: [SteamDepot], info: SteamAppInfo, _ id: Int) {
        var jobs: [SteamDepotJob] = []
        var borrowed: [Int: SteamAppInfo] = [:]
        func next(_ index: Int) {
            guard id == token else { return }
            if index >= depots.count { fetchManifests(jobs, id); return }
            let depot = depots[index]
            if let manifest = depot.manifest { jobs.append(SteamDepotJob(depot: depot, manifest: manifest, keyApp: depot.fromApp ?? appid)); next(index + 1); return }
            guard let source = depot.fromApp else { next(index + 1); return }
            func use(_ other: SteamAppInfo) {
                if let manifest = other.depots.first(where: { $0.id == depot.id })?.manifest {
                    var resolved = depot; resolved.manifest = manifest
                    jobs.append(SteamDepotJob(depot: resolved, manifest: manifest, keyApp: source))
                }
                next(index + 1)
            }
            if let other = borrowed[source] { use(other); return }
            backend.appInfo(source) { [weak self] result in
                guard let self, id == self.token else { return }
                if case .success(let other) = result { borrowed[source] = other; use(other) } else { next(index + 1) }
            }
        }
        state = .preparing("Reading the list of files…")
        next(0)
    }

    private func fetchManifests(_ jobs: [SteamDepotJob], _ id: Int) {
        guard !jobs.isEmpty else { fail("Steam gave no files to download for \(name).", id); return }
        backend.servers { [weak self] found in
            guard let self, id == self.token else { return }
            guard !found.isEmpty else { self.fail("Steam's content servers could not be reached. Check the internet connection.", id); return }
            self.servers = found
            self.hostBook = SteamHostBook(hosts: found)
            SteamLog.event("[steam-perf] \(found.count) content servers: " + found.prefix(6).map { "\($0.host.replacingOccurrences(of: ".steamcontent.com", with: "")) load \($0.load)" }.joined(separator: ", "))
            var loaded: [SteamManifest] = [], loadedKeys: [Data] = []
            var skipped: [String] = []
            func next(_ index: Int) {
                guard id == self.token else { return }
                if index >= jobs.count {
                    guard !loaded.isEmpty else { self.fail(skipped.first ?? "No depot of \(self.name) could be downloaded.", id); return }
                    self.manifests = loaded; self.keys = loadedKeys
                    self.beginTransfer(id); return
                }
                let job = jobs[index]
                self.state = .preparing("Getting the file list (\(index + 1) of \(jobs.count))…")
                self.backend.depotKey(app: job.keyApp, depot: job.depot.id) { key in
                    guard id == self.token else { return }
                    switch key {
                    case .failure(let error):
                        if error.notOwned { skipped.append(error.message); SteamLog.event("Steam download: skipping depot \(job.depot.id): \(error.message)"); next(index + 1) }
                        else { self.fail(error.message, id) }
                    case .success(let depotKey):
                        self.backend.manifestCode(app: job.keyApp, depot: job.depot.id, manifest: job.manifest) { code in
                            guard id == self.token else { return }
                            switch code {
                            case .failure(let error): self.fail(error.message, id)
                            case .success(let requestCode):
                                self.downloadManifest(job, code: requestCode, key: depotKey, attempt: 0, id) { result in
                                    switch result {
                                    case .failure(let message): self.fail(message.description, id)
                                    case .success(let manifest): loaded.append(manifest); loadedKeys.append(depotKey); next(index + 1)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            next(0)
        }
    }

    private func downloadManifest(_ job: SteamDepotJob, code: UInt64, key: Data, attempt: Int, _ id: Int, completion: @escaping (Result<SteamManifest, ManifestFailure>) -> Void) {
        guard attempt < min(servers.count, 4), let url = SteamCDN.manifestURL(servers[attempt % servers.count], depot: job.depot.id, manifest: job.manifest, code: code) else {
            completion(.failure(ManifestFailure("The file list for \(name) could not be downloaded from Steam's servers."))); return
        }
        backend.fetch(url) { [weak self] result in
            guard let self, id == self.token else { return }
            DispatchQueue.main.async {
                switch result {
                case .success(let data):
                    if let manifest = try? SteamManifest.parse(zipped: data, depotKey: key) { completion(.success(manifest)) }
                    else { completion(.failure(ManifestFailure("Steam's file list for \(self.name) could not be read."))) }
                case .failure: self.downloadManifest(job, code: code, key: key, attempt: attempt + 1, id, completion: completion)
                }
            }
        }
    }
    struct ManifestFailure: Error, ExpressibleByStringLiteral, CustomStringConvertible {
        var description: String
        init(_ text: String) { description = text }
        init(stringLiteral value: String) { description = value }
    }

    // MARK: Transfer

    private func beginTransfer(_ id: Int) {
        guard let info = installInfo else { return }
        let installDirectory = SteamDepotPlanner.safeInstallDirectory(info)
        gameFolder = steamApps.appendingPathComponent("common/" + installDirectory)
        progressFolder = Self.progressFolder(appID: appid, steamApps: steamApps)
        // What will actually be written: no folders, no links, and not Steam's redistributable installers.
        total = manifests.reduce(0) { sum, manifest in sum + manifest.files.reduce(0) { $0 + (Self.isWanted($1) ? $1.size : 0) } }

        // Room for it? Keep half a gigabyte free for the system.
        let need = Int64(total) + 512 << 20
        if let free = freeSpaceOverride?() ?? Self.freeSpace(at: steamApps), free < need {
            fail("There is not enough space on this device: \(name) needs \(Self.size(Int64(total))) and \(Self.size(max(0, free))) is free.", id); return
        }
        do {
            try fm.createDirectory(at: gameFolder, withIntermediateDirectories: true)
            try fm.createDirectory(at: progressFolder, withIntermediateDirectories: true)
        } catch { fail("The game's folder could not be created (\(error.localizedDescription)).", id); return }

        // Resume only when the same manifests are being fetched.
        let plan = manifests.map { "\($0.depotID):\($0.manifestID)" }.joined(separator: ",")
        let planFile = progressFolder.appendingPathComponent("plan.txt"), doneFile = progressFolder.appendingPathComponent("done.bin")
        var done = Set<UInt32>()
        if (try? String(contentsOf: planFile, encoding: .utf8)) == plan, let data = try? Data(contentsOf: doneFile) {
            let bytes = Array(data)
            var at = 0
            while at + 4 <= bytes.count { done.insert(UInt32(bytes[at]) | UInt32(bytes[at + 1]) << 8 | UInt32(bytes[at + 2]) << 16 | UInt32(bytes[at + 3]) << 24); at += 4 }
            SteamLog.event("Steam download: resuming, \(done.count) chunk(s) already on disk.")
        } else {
            try? fm.removeItem(at: doneFile)
            try? plan.write(to: planFile, atomically: true, encoding: .utf8)
        }

        // Lay out the folders and empty files, and the list of chunks still to fetch.
        var items: [Item] = []
        var global: UInt32 = 0
        var doneBytes: UInt64 = 0
        remaining = [:]
        for (depotIndex, manifest) in manifests.enumerated() {
            for (fileIndex, file) in manifest.files.enumerated() {
                if Self.isRedistributable(file.path) { global += UInt32(file.chunks.count); continue }
                let target = gameFolder.appendingPathComponent(file.path)
                if file.isDirectory { try? fm.createDirectory(at: target, withIntermediateDirectories: true); continue }
                if file.isSymlink { global += UInt32(file.chunks.count); continue }
                try? fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                if file.chunks.isEmpty || file.size == 0 {
                    if !fm.fileExists(atPath: target.path) { fm.createFile(atPath: target.path, contents: nil) }
                    continue
                }
                var left = 0
                for (chunkIndex, chunk) in file.chunks.enumerated() {
                    if done.contains(global) { doneBytes += UInt64(chunk.originalSize) }
                    else { items.append(Item(depot: depotIndex, file: fileIndex, chunk: chunkIndex, global: global)); left += 1 }
                    global += 1
                }
                if left > 0 { remaining[fileKey(depotIndex, fileIndex)] = left }
            }
        }
        lock.lock(); written = doneBytes; lock.unlock()
        SteamLog.event("Steam download: \(items.count) chunk(s) to fetch, \(Self.size(Int64(total))) in total.")
        state = .downloading(SteamDownloadProgress(doneBytes: doneBytes, totalBytes: total, bytesPerSecond: 0))
        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.tick() }

        // How many chunks are in flight adapts to what the connection can carry (see ConcurrencyController).
        let fixed = parallelChunks
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            var controller = ConcurrencyController(start: max(1, fixed), floor: max(1, min(fixed, 8)), ceiling: self.adaptive ? 64 : max(1, fixed))
            let gate = NSCondition()
            var inFlight = 0
            for item in items {
                gate.lock()
                var stopped = false
                while true {
                    self.lock.lock(); stopped = self.cancelled || self.failure != nil; let bytes = self.networkBytes; self.lock.unlock()
                    if stopped { break }
                    if self.adaptive { controller.observe(totalBytes: bytes, now: Date()) }
                    self.lock.lock(); self.currentTarget = controller.target; self.lock.unlock()
                    if inFlight < controller.target { break }
                    gate.wait(until: Date().addingTimeInterval(0.5))
                }
                if stopped { gate.unlock(); break }
                inFlight += 1
                gate.unlock()
                self.fetchChunk(item, attempt: 0) { gate.lock(); inFlight -= 1; gate.signal(); gate.unlock() }
            }
            gate.lock()
            while inFlight > 0 { gate.wait(until: Date().addingTimeInterval(0.5)) }
            gate.unlock()
            DispatchQueue.main.async { [weak self] in self?.transferEnded(id) }
        }
    }

    /// Steam's own runtime installers (DirectX, Visual C++, .NET ...) sit in `_CommonRedist`. They are big, and they are for Windows itself, not for Wine.
    static func isRedistributable(_ path: String) -> Bool {
        path.split(separator: "/").contains { $0.caseInsensitiveCompare("_CommonRedist") == .orderedSame }
    }
    private static func isWanted(_ file: SteamManifestFile) -> Bool { !file.isDirectory && !file.isSymlink && !isRedistributable(file.path) }

    private func fileKey(_ depot: Int, _ file: Int) -> Int { depot << 32 | file }

    private func fetchChunk(_ item: Item, attempt: Int, finished: @escaping () -> Void) {
        lock.lock(); let stop = cancelled || failure != nil; lock.unlock()
        if stop { finished(); return }
        let manifest = manifests[item.depot]
        let chunk = manifest.files[item.file].chunks[item.chunk]
        let book = hostBook
        guard let server = book.choose(), let url = SteamCDN.chunkURL(server, depot: manifest.depotID, sha: chunk.sha) else {
            setFailure("Steam's content servers could not be reached."); finished(); return
        }
        let began = Date()
        backend.fetch(url) { [weak self] result in
            let netSeconds = Date().timeIntervalSince(began)
            guard let self else { finished(); return }
            DispatchQueue.global(qos: .userInitiated).async {
                switch result {
                case .success(let data):
                    book.finished(host: server.host, bytes: data.count, seconds: netSeconds, ok: true)
                    self.lock.lock(); self.networkBytes += UInt64(data.count); self.lock.unlock()
                    let decodeStart = Date()
                    let plain = SteamCipher.unpackChunk(data, key: self.keys[item.depot], originalSize: chunk.originalSize)
                    let verified = plain != nil && plain!.count == chunk.originalSize && SteamCipher.sha1(plain!) == chunk.sha
                    let writeStart = Date()
                    if let plain, verified, self.write(plain, item: item, network: UInt64(data.count)) {
                        self.lock.lock()
                        self.statChunks += 1; self.statNet += netSeconds; self.statDecode += writeStart.timeIntervalSince(decodeStart); self.statWrite += Date().timeIntervalSince(writeStart)
                        self.lock.unlock()
                        finished(); return
                    }
                    // Say which check failed (no content of the game is logged, only sizes and the first bytes of the packed chunk).
                    let why = plain == nil ? "could not be unpacked" : plain!.count != chunk.originalSize ? "unpacked to \(plain!.count) bytes, expected \(chunk.originalSize)" : plain == nil || SteamCipher.sha1(plain!) != chunk.sha ? "its hash differs" : "could not be written"
                    SteamLog.event("[steam-depot] chunk rejected: depot=\(manifest.depotID) packed=\(data.count) \(why)")
                    self.lock.lock(); self.rejected += 1; self.lock.unlock()
                    self.retry(item, attempt: attempt, reason: "a chunk did not check out", finished: finished)
                case .failure(let error):
                    book.finished(host: server.host, bytes: 0, seconds: netSeconds, ok: false)
                    if error.notOwned { self.setFailure("Steam refused the download (\(error.message)). Try signing in for downloads again."); finished(); return }
                    self.retry(item, attempt: attempt, reason: error.message, finished: finished)
                }
            }
        }
    }

    private func retry(_ item: Item, attempt: Int, reason: String, finished: @escaping () -> Void) {
        if attempt + 1 >= retriesPerChunk {
            setFailure("Downloading \(name) stopped: \(reason) (after \(retriesPerChunk) tries). The download can be resumed."); finished(); return
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.4 * Double(attempt + 1)) { [weak self] in self?.fetchChunk(item, attempt: attempt + 1, finished: finished) ?? finished() }
    }

    private func setFailure(_ message: String) { lock.lock(); if failure == nil { failure = message }; lock.unlock() }

    /// Put a chunk at its place in its file. Returns false if the disk write failed.
    private func write(_ plain: Data, item: Item, network: UInt64) -> Bool {
        let manifest = manifests[item.depot]
        let file = manifest.files[item.file]
        let chunk = file.chunks[item.chunk]
        let key = fileKey(item.depot, item.file)
        lock.lock()
        var descriptor = descriptors[key]
        if descriptor == nil {
            let path = gameFolder.appendingPathComponent(file.path).path
            let opened = open(path, O_RDWR | O_CREAT, 0o644)
            if opened >= 0 {
                if fstat_size(opened) != Int64(file.size) { _ = ftruncate(opened, off_t(file.size)) }
                descriptors[key] = opened; descriptor = opened
            }
        }
        lock.unlock()
        guard let fd = descriptor else { setFailure("A file of the game could not be written."); return false }
        let count = plain.withUnsafeBytes { pwrite(fd, $0.baseAddress, plain.count, off_t(chunk.offset)) }
        guard count == plain.count else { setFailure("The disk write failed. The device may be out of space."); return false }
        lock.lock()
        written += UInt64(plain.count)
        pendingDone.append(item.global)
        let left = (remaining[key] ?? 1) - 1
        remaining[key] = left
        if left <= 0, let fd = descriptors.removeValue(forKey: key) { close(fd) }
        lock.unlock()
        return true
    }

    private func fstat_size(_ fd: Int32) -> Int64 { var info = stat(); return fstat(fd, &info) == 0 ? Int64(info.st_size) : -1 }

    private func closeAll() {
        lock.lock(); let all = descriptors.values; descriptors = [:]; lock.unlock()
        for fd in all { close(fd) }
    }

    /// Chunks that are done are remembered on disk, so an interrupted download continues instead of starting over.
    private func flushProgress() {
        lock.lock(); let batch = pendingDone; pendingDone = []; lock.unlock()
        guard !batch.isEmpty else { return }
        var data = Data(capacity: batch.count * 4)
        for value in batch { for i in 0..<4 { data.append(UInt8((value >> (8 * UInt32(i))) & 0xFF)) } }
        let file = progressFolder.appendingPathComponent("done.bin")
        if let handle = try? FileHandle(forWritingTo: file) { handle.seekToEndOfFile(); handle.write(data); try? handle.close() } else { try? data.write(to: file) }
    }

    private func tick() {
        guard case .downloading = state else { return }
        flushProgress()
        lock.lock()
        let now = Date()
        samples.append((now, networkBytes)); samples.removeAll { now.timeIntervalSince($0.time) > 4 }
        let speed: Double = samples.count >= 2 ? Double(networkBytes - samples[0].bytes) / max(0.5, now.timeIntervalSince(samples[0].time)) : 0
        let done = written
        let target = currentTarget, refused = rejected
        let logNow = now.timeIntervalSince(lastPerfLog) >= 10
        var times = (chunks: 0, net: 0.0, decode: 0.0, write: 0.0)
        if logNow { lastPerfLog = now; times = (statChunks, statNet, statDecode, statWrite); statChunks = 0; statNet = 0; statDecode = 0; statWrite = 0 }
        lock.unlock()
        if logNow {
            let n = Double(max(times.chunks, 1))
            SteamLog.event(String(format: "[steam-perf] network %.1f MB/s, written %.0f of %.0f MB, in flight %d, rejected chunks %d | per chunk: fetch %.0f ms, unpack %.0f ms, write %.0f ms (n=%d) | %@",
                                  speed / 1_048_576, Double(done) / 1_048_576, Double(total) / 1_048_576, target, refused,
                                  times.net / n * 1000, times.decode / n * 1000, times.write / n * 1000, times.chunks, hostBook.summary()))
        }
        state = .downloading(SteamDownloadProgress(doneBytes: done, totalBytes: total, bytesPerSecond: speed))
    }

    private func transferEnded(_ id: Int) {
        guard id == token, !state.isFinal else { return }
        progressTimer?.invalidate(); progressTimer = nil
        closeAll(); flushProgress()
        lock.lock(); let problem = failure; let stopped = cancelled; lock.unlock()
        if stopped && problem == nil { return }
        if let problem { fail(problem, id); return }
        guard let info = installInfo else { return }
        writeAppManifest(info)
        try? fm.removeItem(at: progressFolder)
        backend.close()
        SteamLog.event("Steam download: \(name) is installed.")
        state = .finished
    }

    // MARK: Recording the install

    private func writeAppManifest(_ info: SteamAppInfo) {
        func quoted(_ text: String) -> String { "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\"" }
        let steamapps = gameFolder.deletingLastPathComponent().deletingLastPathComponent()
        var lines = ["\"AppState\"", "{", "\t\"appid\"\t\t\(quoted(String(appid)))", "\t\"Universe\"\t\t\"1\"", "\t\"name\"\t\t\(quoted(info.name))",
                     "\t\"StateFlags\"\t\t\"4\"", "\t\"LastOwner\"\t\t\(quoted(ownerSteamID ?? "0"))", "\t\"installdir\"\t\t\(quoted(gameFolder.lastPathComponent))",
                     "\t\"LastUpdated\"\t\t\(quoted(String(Int(Date().timeIntervalSince1970))))", "\t\"SizeOnDisk\"\t\t\(quoted(String(total)))",
                     "\t\"buildid\"\t\t\(quoted(info.buildID ?? "0"))", "\t\"InstalledDepots\"", "\t{"]
        for manifest in manifests {
            lines += ["\t\t\(quoted(String(manifest.depotID)))", "\t\t{", "\t\t\t\"manifest\"\t\t\(quoted(String(manifest.manifestID)))", "\t\t\t\"size\"\t\t\(quoted(String(manifest.totalOriginal)))", "\t\t}"]
        }
        lines += ["\t}"] + SteamManifestLanguage.blockLines() + ["}", ""]
        try? lines.joined(separator: "\n").write(to: steamapps.appendingPathComponent("appmanifest_\(appid).acf"), atomically: true, encoding: .utf8)
    }

    // MARK: Helpers

    static func freeSpace(at url: URL) -> Int64? {
        var folder = url
        while !FileManager.default.fileExists(atPath: folder.path), folder.pathComponents.count > 1 { folder.deleteLastPathComponent() }
        return (try? folder.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?.volumeAvailableCapacityForImportantUsage
    }
    static func size(_ bytes: Int64) -> String {
        let value = Double(bytes)
        if value >= Double(1 << 30) { return String(format: "%.1f GB", value / Double(1 << 30)) }
        return String(format: "%.0f MB", value / Double(1 << 20))
    }
}
