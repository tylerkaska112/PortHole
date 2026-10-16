// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
// A connection to a Steam "connection manager" server over WebSocket: the channel the real Steam client uses to sign in,
// ask which files an app has, and get the keys for the games the account owns. Everything on this class runs on the main queue.
import Foundation

// MARK: - The socket

protocol SteamSocket: AnyObject {
    var onMessage: ((Data) -> Void)? { get set }
    var onClose: ((String) -> Void)? { get set }
    func open(_ url: URL, completion: @escaping (String?) -> Void)
    func send(_ data: Data)
    func close()
}

/// WebSocket over TLS (URLSession). Callbacks arrive on the main queue.
final class URLSessionSteamSocket: NSObject, SteamSocket, URLSessionWebSocketDelegate {
    var onMessage: ((Data) -> Void)?
    var onClose: ((String) -> Void)?
    private var task: URLSessionWebSocketTask?
    private var session: URLSession?
    private var opened: ((String?) -> Void)?
    private var finished = false

    func open(_ url: URL, completion: @escaping (String?) -> Void) {
        opened = completion
        let session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: .main)
        self.session = session
        var request = URLRequest(url: url); request.timeoutInterval = 15
        let task = session.webSocketTask(with: request)
        task.maximumMessageSize = 64 << 20
        self.task = task
        task.resume()
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
            guard let self, let opened = self.opened else { return }
            self.opened = nil; opened("timed out"); self.close()
        }
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        opened?(nil); opened = nil
        listen()
    }
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) { end("closed (\(closeCode.rawValue))") }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) { end(error?.localizedDescription ?? "closed") }

    private func end(_ reason: String) {
        if let opened { self.opened = nil; opened(reason) }
        guard !finished else { return }
        finished = true; onClose?(reason)
    }

    private func listen() {
        task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error): DispatchQueue.main.async { self.end(error.localizedDescription) }
            case .success(let message):
                if case .data(let data) = message { DispatchQueue.main.async { self.onMessage?(data) } }
                self.listen()
            }
        }
    }

    func send(_ data: Data) { task?.send(.data(data)) { _ in } }
    func close() { task?.cancel(with: .normalClosure, reason: nil); session?.invalidateAndCancel(); task = nil }
}

// MARK: - The connection

/// One entry of the account's license list: a package the account owns (a game, a bundle, a free sub).
struct SteamLicense: Equatable {
    var packageID: Int
    var accessToken: UInt64
    var flags: Int
    /// Cancelled or run-out licences do not grant anything.
    var isActive: Bool { flags & (0x08 | 0x10 | 0x20) == 0 }
}

struct SteamLogOn: Equatable {
    /// nil: anonymous (enough for games that are free to everyone, and used by the tests).
    var accountName: String?
    var refreshToken: String?
    var steamID: UInt64
    static let anonymous = SteamLogOn(accountName: nil, refreshToken: nil, steamID: SteamIDs.anonymous())
    static func account(name: String, refreshToken: String, steamID: String) -> SteamLogOn {
        SteamLogOn(accountName: name, refreshToken: refreshToken, steamID: UInt64(steamID).map { SteamIDs.user(account: SteamIDs.account(of: $0)) } ?? 0)
    }
}

final class SteamCM {
    enum ConnectionError: Error, Equatable, CustomStringConvertible {
        case failed(String), logOnRefused(Int), timedOut, closed(String)
        var description: String {
            switch self {
            case .failed(let text): return text
            case .closed(let text): return "The connection to Steam closed (\(text))."
            case .timedOut: return "Steam did not answer in time."
            case .logOnRefused(let code):
                switch code {
                case 5: return "Steam did not accept the saved sign-in for downloads. Sign in for downloads again."
                case 15: return "Steam refused the sign-in for downloads. Sign in for downloads again."
                case 65: return "Steam wants a Steam Guard code for downloads."
                case 84: return "Steam is limiting sign-ins right now. Wait a few minutes and try again."
                case 27, 8, 21: return "The sign-in for downloads has expired. Sign in for downloads again."
                default: return "Steam refused the sign-in for downloads (error \(code))."
                }
            }
        }
    }

    private let socketFactory: () -> SteamSocket
    private var socket: SteamSocket?
    private var steamID: UInt64 = 0
    private var sessionID: Int32 = 0
    private var nextJob: UInt64 = 1
    private var jobWaiters: [UInt64: (Result<SteamPacket, ConnectionError>) -> Void] = [:]
    private var waiters: [(id: Int, emsg: Int, match: (SteamPacket) -> Bool, done: (Result<SteamPacket, ConnectionError>) -> Void)] = []
    private var nextWaiter = 0
    private var heartbeat: Timer?
    private(set) var isLoggedOn = false
    /// Sent by Steam right after a log-on; may arrive in more than one message.
    private(set) var licenses: [SteamLicense] = []
    private(set) var licenseListComplete = false
    var onLicenses: (() -> Void)?
    private(set) var cellID = 0
    var onClose: ((ConnectionError) -> Void)?

    init(socketFactory: @escaping () -> SteamSocket = { URLSessionSteamSocket() }) { self.socketFactory = socketFactory }

    // MARK: Connect and log on

    /// Open a socket to one of Steam's servers (`endpoint` skips the directory lookup, for tests).
    func connect(endpoint: String? = nil, completion: @escaping (Result<Void, ConnectionError>) -> Void) {
        func open(_ endpoints: [String]) {
            guard let first = endpoints.first, let url = URL(string: "wss://\(first)/cmsocket/") else { completion(.failure(.failed("No Steam server could be reached."))); return }
            let socket = socketFactory()
            self.socket = socket
            socket.onMessage = { [weak self] data in self?.received(data) }
            socket.onClose = { [weak self, weak socket] reason in
                guard let self, self.socket === socket else { return }
                self.closed(.closed(reason))
            }
            socket.open(url) { [weak self] error in
                guard let self else { return }
                if error == nil { completion(.success(())); return }
                SteamLog.event("Steam: could not open a connection to a Steam server (\(error ?? "")).")
                self.socket = nil
                open(Array(endpoints.dropFirst()))
            }
        }
        if let endpoint { open([endpoint]); return }
        var request = URLRequest(url: URL(string: "\(SteamAPI.host)/ISteamDirectory/GetCMListForConnect/v1/?cellid=0&cmtype=websockets&format=json")!)
        request.timeoutInterval = 15
        URLSession.shared.dataTask(with: request) { data, _, error in
            DispatchQueue.main.async {
                guard let data, let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                      let list = (json["response"] as? [String: Any])?["serverlist"] as? [[String: Any]] else {
                    completion(.failure(.failed("Steam's server list could not be loaded" + (error.map { " (\($0.localizedDescription))" } ?? "") + "."))); return
                }
                let servers = list.filter { ($0["type"] as? String) == "websockets" }
                    .sorted { (SteamJSON.double($0["wtd_load"]) ?? 99) < (SteamJSON.double($1["wtd_load"]) ?? 99) }
                    .compactMap { $0["endpoint"] as? String }
                open(Array(servers.prefix(6)))
            }
        }.resume()
    }

    func logOn(_ details: SteamLogOn, completion: @escaping (Result<Void, ConnectionError>) -> Void) {
        var body = PBWriter()
        body.varint(1, 65580)                              // protocol version
        body.varint(3, 0)                                  // cell id: let Steam pick
        body.string(6, "english")
        body.varint(7, 16)                                 // client OS type: Windows 10
        body.bool(8, false)
        if let name = details.accountName, let token = details.refreshToken {
            body.string(50, name)
            body.string(108, token)                        // the refresh token goes in the access_token field
        }
        var packet = SteamPacket(emsg: EMsg.logOn)
        packet.steamID = details.steamID; packet.sessionID = 0; packet.body = body.data
        steamID = details.steamID
        licenses = []; licenseListComplete = false
        wait(for: EMsg.logOnResponse, timeout: 20, match: { _ in true }) { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error): completion(.failure(error))
            case .success(let reply):
                let fields = PBFields(reply.body)
                let code = reply.eresult ?? fields?.int(1) ?? 2
                let bodyCode = fields?.int(1) ?? code
                guard bodyCode == 1 else { completion(.failure(.logOnRefused(bodyCode))); self.disconnect(); return }
                self.sessionID = reply.sessionID
                if reply.steamID != 0 { self.steamID = reply.steamID }
                self.cellID = fields?.int(7) ?? 0
                self.isLoggedOn = true
                let seconds = max(5, min(60, fields?.int(3) ?? fields?.int(2) ?? 9))
                self.heartbeat?.invalidate()
                self.heartbeat = Timer.scheduledTimer(withTimeInterval: TimeInterval(seconds), repeats: true) { [weak self] _ in self?.send(EMsg.heartBeat, body: Data()) }
                completion(.success(()))
            }
        }
        socket?.send(packet.encoded())
    }

    func disconnect() {
        heartbeat?.invalidate(); heartbeat = nil
        let socket = self.socket
        self.socket = nil; isLoggedOn = false
        socket?.close()
        failAll(.closed("disconnected"))
    }

    private func closed(_ error: ConnectionError) {
        heartbeat?.invalidate(); heartbeat = nil; socket = nil; isLoggedOn = false
        failAll(error)
        onClose?(error)
    }

    private func failAll(_ error: ConnectionError) {
        let pendingJobs = jobWaiters, pendingWaiters = waiters
        jobWaiters = [:]; waiters = []
        for (_, done) in pendingJobs { done(.failure(error)) }
        for waiter in pendingWaiters { waiter.done(.failure(error)) }
    }

    // MARK: Sending and receiving

    func send(_ emsg: Int, body: Data, jobSource: UInt64 = UInt64.max, jobName: String? = nil) {
        var packet = SteamPacket(emsg: emsg)
        packet.steamID = steamID; packet.sessionID = sessionID; packet.body = body
        packet.jobSource = jobSource; packet.targetJobName = jobName
        socket?.send(packet.encoded())
    }

    /// Wait for the next message with this EMsg that `match` accepts.
    @discardableResult
    func wait(for emsg: Int, timeout: TimeInterval, match: @escaping (SteamPacket) -> Bool, completion: @escaping (Result<SteamPacket, ConnectionError>) -> Void) -> Int {
        nextWaiter += 1
        let id = nextWaiter
        waiters.append((id, emsg, match, completion))
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
            guard let self, let index = self.waiters.firstIndex(where: { $0.id == id }) else { return }
            let waiter = self.waiters.remove(at: index)
            waiter.done(.failure(.timedOut))
        }
        return id
    }

    /// A call to one of Steam's "service methods" (for example `ContentServerDirectory.GetManifestRequestCode#1`). Answers with the reply's body.
    func call(_ name: String, body: Data, timeout: TimeInterval = 20, completion: @escaping (Result<Data, ConnectionError>) -> Void) {
        let job = nextJob; nextJob += 1
        jobWaiters[job] = { result in
            switch result {
            case .failure(let error): completion(.failure(error))
            case .success(let reply):
                if let code = reply.eresult, code != 1 { completion(.failure(.failed("Steam answered \(name) with error \(code)."))) } else { completion(.success(reply.body)) }
            }
        }
        send(EMsg.serviceMethodCall, body: body, jobSource: job, jobName: name)
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
            guard let self, let done = self.jobWaiters.removeValue(forKey: job) else { return }
            done(.failure(.timedOut))
        }
    }

    /// CMsgClientLicenseList: eresult=1, repeated License=2 {package_id=1, flags=7, access_token=17}.
    private func collectLicenses(_ packet: SteamPacket) {
        guard let fields = PBFields(packet.body) else { return }
        for entry in fields.messages(2) {
            guard let id = entry.uint(1) else { continue }
            licenses.append(SteamLicense(packageID: Int(id), accessToken: entry.uint(17) ?? 0, flags: entry.int(7) ?? 0))
        }
        licenseListComplete = true
        onLicenses?()
    }

    private func received(_ data: Data) {
        guard let packet = SteamPacket.decode(data) else { return }
        dispatch(packet)
    }

    private func dispatch(_ packet: SteamPacket) {
        if packet.emsg == EMsg.multi {
            for inner in SteamPacket.unpackMulti(packet.body) ?? [] { dispatch(inner) }
            return
        }
        if packet.emsg == EMsg.licenseList { collectLicenses(packet) }
        if packet.jobTarget != UInt64.max, let done = jobWaiters.removeValue(forKey: packet.jobTarget) { done(.success(packet)); return }
        if let index = waiters.firstIndex(where: { $0.emsg == packet.emsg && $0.match(packet) }) {
            let waiter = waiters.remove(at: index)
            waiter.done(.success(packet))
        }
    }
}
