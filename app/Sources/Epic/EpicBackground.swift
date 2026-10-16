// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
import UIKit
import BackgroundTasks

/// Keeps an Epic download going after the app is left: DownloadKeepAlive (silent audio) keeps the app running at full speed. If that could not start, the short
/// grace period iOS gives an app that was just left is used, then the download pauses cleanly (finished files are kept) and carries on when the app is active again.
@MainActor final class EpicBackground {
    /// "epic" or "gog": the key of this store's download card and keep-alive, and the end of its background task identifier.
    private let store: String
    private let label: String
    init(store: String = "epic", label: String = "Epic Games") { self.store = store; self.label = label }

    enum Outcome: Equatable { case completed, paused, failed(String), downloaded }   // downloaded: GOG's setup files are in, the installer still has to run

    private var activeDownload: (() -> Bool)?
    private var pauseDownloads: (() -> Void)?
    private var resumeDownloads: (() -> Void)?
    private var grace: UIBackgroundTaskIdentifier = .invalid
    private var observing = false
    /// Set by the installer: is something paused or stopped that a Resume button could continue?
    var anyPaused: (() -> Bool)?
    private var continued: AnyObject?            // BGContinuedProcessingTask (iOS 26+): the download card with its percentage, size and speed
    private var continuedPending = false
    private var registered: String?
    private var currentName = ""
    private var lastCardText = Date.distantPast

    /// "<bundle id>.download.epic", from the permitted "<bundle id>.download.*" entry of Info.plist.
    private var taskIdentifier: String? {
        let permitted = Bundle.main.object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers") as? [String] ?? []
        guard let wildcard = permitted.first(where: { $0.hasSuffix(".download.*") }) else { return nil }
        return String(wildcard.dropLast()) + store
    }

    func attach(active: @escaping () -> Bool, pause: @escaping () -> Void, resume: @escaping () -> Void) {
        activeDownload = active; pauseDownloads = pause; resumeDownloads = resume
        guard !observing else { return }
        observing = true
        NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.beginGrace() }
        }
        NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.endGrace()
                self?.resumeDownloads?()
            }
        }
    }

    func downloadStarted(name: String) {
        currentName = name
        DownloadActivity.shared.begin(store: store, name: name)
        if #available(iOS 26.0, *), !DownloadActivity.shared.hasCard(store) {
            submitContinued()
            if let task = continued as? BGContinuedProcessingTask { task.updateTitle("Downloading \(name)", subtitle: "\(label) \u{00B7} Preparing\u{2026}") }
        }
        UIApplication.shared.isIdleTimerDisabled = true           // a download stops if the device locks
        DownloadKeepAlive.shared.hold(store)                     // keeps the app running (silent audio) after it is left
        LogStore.shared.log("[\(store)-install] downloading \(name)")
    }

    /// The running download's progress, for the card's percentage and its words.
    func progress(_ progress: SteamDownloadProgress, waiting: Int) {
        DownloadActivity.shared.update(store: store, name: currentName, progress: progress, waiting: waiting)
        guard #available(iOS 26.0, *), let task = continued as? BGContinuedProcessingTask else { return }
        let total = Int64(clamping: max(progress.totalBytes, 1))
        if task.progress.totalUnitCount != total { task.progress.totalUnitCount = total }
        task.progress.completedUnitCount = Int64(clamping: min(progress.doneBytes, progress.totalBytes))
        if Date().timeIntervalSince(lastCardText) >= 1 {
            lastCardText = Date()
            task.updateTitle("Downloading \(currentName)", subtitle: DownloadCardText.subtitle(progress, waiting: waiting))
        }
    }

    func downloadEnded(name: String, outcome: Outcome, queueEmpty: Bool) {
        if queueEmpty {
            switch outcome {
            case .completed: DownloadActivity.shared.end(store: store, failed: false, message: "\(name) is ready to play", finished: true)
            case .downloaded: DownloadActivity.shared.end(store: store, failed: false, message: "\(name) is downloaded. Open Porthole to install it", finished: true)
            case .failed(let reason): DownloadActivity.shared.end(store: store, failed: true, message: "\(name) stopped: \(reason)", finished: true)
            case .paused:
                if anyPaused?() == true, !AppModel.shared.session.isActive { DownloadActivity.shared.paused(store: store, name: name) }
                else { DownloadActivity.shared.end(store: store, failed: false, message: nil, finished: false) }
            }
        }
        if queueEmpty { finishContinued(success: outcome == .completed || outcome == .downloaded) }
        if queueEmpty { UIApplication.shared.isIdleTimerDisabled = false; DownloadKeepAlive.shared.release(store); endGrace() }
        LogStore.shared.log("[\(store)-install] \(name): \(outcome == .completed ? "installed" : outcome == .downloaded ? "downloaded" : outcome == .paused ? "paused" : "failed")")
    }

    @available(iOS 26.0, *)
    private func submitContinued() {
        guard continued == nil, !continuedPending, let identifier = taskIdentifier else { return }
        if registered != identifier {
            let ok = BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: .main) { [weak self] task in
                guard let task = task as? BGContinuedProcessingTask else { task.setTaskCompleted(success: false); return }
                MainActor.assumeIsolated { self?.attach(task) }
            }
            guard ok else { return }
            registered = identifier
        }
        let request = BGContinuedProcessingTaskRequest(identifier: identifier, title: "Downloading \(currentName)", subtitle: label)
        request.strategy = .fail
        do { try BGTaskScheduler.shared.submit(request); continuedPending = true } catch {}
    }

    @available(iOS 26.0, *)
    private func attach(_ task: BGContinuedProcessingTask) {
        continuedPending = false
        continued = task
        task.progress.totalUnitCount = 1
        task.expirationHandler = { [weak self] in
            DispatchQueue.main.async {
                self?.pauseDownloads?()
                self?.finishContinued(success: false)
            }
        }
        if activeDownload?() != true { finishContinued(success: true) }
    }

    private func finishContinued(success: Bool) {
        if #available(iOS 26.0, *), let task = continued as? BGContinuedProcessingTask { task.setTaskCompleted(success: success) }
        continued = nil
        continuedPending = false
    }

    private func beginGrace() {
        guard activeDownload?() == true, grace == .invalid, !DownloadKeepAlive.shared.isRunning else { return }
        grace = UIApplication.shared.beginBackgroundTask(withName: "\(label) download") { [weak self] in
            MainActor.assumeIsolated {
                self?.pauseDownloads?()
                self?.endGrace()
            }
        }
    }

    private func endGrace() {
        guard grace != .invalid else { return }
        UIApplication.shared.endBackgroundTask(grace)
        grace = .invalid
    }
}
