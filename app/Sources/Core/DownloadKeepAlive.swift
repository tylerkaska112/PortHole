// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
import AVFoundation
import UIKit

/// Keeps the app running at full speed while a download is going and the app is not on screen.
///
/// Without it iOS lets a left app trickle (a continued-processing card, or the half minute after leaving, is all a download has), and a download that runs on
/// the CPU (unpacking and checking every chunk) crawls. The app declares the audio background mode; while a download is queued it plays silence, which is what
/// keeps a process alive and un-throttled, the same trick the on-device pairing uses. It starts in the foreground (iOS refuses to start audio from the
/// background) and stops when the last download ends, so nothing runs when nothing is downloading.
@MainActor final class DownloadKeepAlive {
    static let shared = DownloadKeepAlive()

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var attached = false
    private var owners = Set<String>()
    private var observing = false
    private(set) var isRunning = false

    /// Someone (Steam's queue, Epic's queue) needs the app to keep running.
    func hold(_ owner: String) {
        owners.insert(owner)
        observe()
        start()
    }

    func release(_ owner: String) {
        owners.remove(owner)
        if owners.isEmpty { stop() }
    }

    private func start() {
        guard !isRunning else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            if !attached { engine.attach(player); attached = true }
            let format = engine.outputNode.inputFormat(forBus: 0)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(max(format.sampleRate, 8000))) else { return }
            buffer.frameLength = buffer.frameCapacity          // zero-filled = silence
            engine.prepare()
            try engine.start()
            player.scheduleBuffer(buffer, at: nil, options: .loops)
            player.play()
            isRunning = true
            SteamLog.event("[bg-download] keep-alive on (\(owners.sorted().joined(separator: ",")))")
        } catch {
            isRunning = false
            SteamLog.event("[bg-download] keep-alive could not start: \((error as NSError).code)")
        }
    }

    private func stop() {
        guard isRunning else { return }
        player.stop(); engine.stop()
        isRunning = false
        // A game running has the audio session now; only release it when nothing else is using it.
        if !AppModel.shared.session.isActive { try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation]) }
        SteamLog.event("[bg-download] keep-alive off")
    }

    /// A phone call, Siri or a route change stops the engine: bring it back while a download still needs it.
    private func restartIfNeeded() {
        guard !owners.isEmpty else { return }
        isRunning = false
        player.stop(); engine.stop()
        start()
    }

    private func observe() {
        guard !observing else { return }
        observing = true
        let center = NotificationCenter.default
        center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            MainActor.assumeIsolated {
                guard let self else { return }
                if raw == AVAudioSession.InterruptionType.began.rawValue { self.isRunning = false }
                else if raw == AVAudioSession.InterruptionType.ended.rawValue { self.restartIfNeeded() }
            }
        }
        center.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.restartIfNeeded() }
        }
        center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.restartIfNeeded() }
        }
        center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if let self, !self.owners.isEmpty, !self.isRunning { self.start() } }
        }
    }
}

/// The words on iOS's download card (the continued-processing card on the lock screen and Dynamic Island): "42% · 1.3 GB of 3.1 GB · 18 MB/s · 7 min left".
enum DownloadCardText {
    static func size(_ bytes: UInt64) -> String { ByteCountFormatter.string(fromByteCount: Int64(clamping: bytes), countStyle: .file) }

    /// The second line of the Live Activity (its percentage sits beside the bar): "1.3 GB of 3.1 GB \u{00B7} 18 MB/s \u{00B7} 7 min left".
    static func detail(_ p: SteamDownloadProgress) -> String {
        switch p.phase {
        case .preparing: return "Preparing\u{2026}"
        case .finishing: return "Finishing\u{2026}"
        case .downloading:
            var parts: [String] = []
            if p.totalBytes > 0 { parts.append("\(size(p.doneBytes)) of \(size(p.totalBytes))") }
            if p.bytesPerSecond > 0 { parts.append("\(size(UInt64(p.bytesPerSecond)))/s") }
            if let s = p.secondsLeft {
                let seconds = Int(s)
                parts.append(seconds < 60 ? "under a minute left" : seconds < 3600 ? "\(seconds / 60) min left" : "\(seconds / 3600) h \((seconds % 3600) / 60) min left")
            }
            return parts.isEmpty ? "Downloading\u{2026}" : parts.joined(separator: " \u{00B7} ")
        }
    }

    static func subtitle(_ p: SteamDownloadProgress, waiting: Int) -> String {
        var parts: [String] = []
        switch p.phase {
        case .preparing: parts.append("Preparing\u{2026}")
        case .finishing: parts.append("Finishing\u{2026}")
        case .downloading:
            parts.append("\(Int(p.fraction * 100))%")
            if p.totalBytes > 0 { parts.append("\(size(p.doneBytes)) of \(size(p.totalBytes))") }
            if p.bytesPerSecond > 0 { parts.append("\(size(UInt64(p.bytesPerSecond)))/s") }
            if let s = p.secondsLeft {
                let seconds = Int(s)
                parts.append(seconds < 60 ? "under a minute left" : seconds < 3600 ? "\(seconds / 60) min left" : "\(seconds / 3600) h \((seconds % 3600) / 60) min left")
            }
        }
        if waiting > 0 { parts.append("+\(waiting) waiting") }
        return parts.joined(separator: " \u{00B7} ")
    }
}
