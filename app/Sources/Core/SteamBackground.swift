// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
// Portions adapted from Madeira's SteamDownloadBackground.swift (GPL-3.0-or-later, Copyright 2026 125hz) for this app's SteamStore.
import UIKit
import BackgroundTasks
import UserNotifications

/// Keeps Steam downloads going when the app leaves the screen.
///
/// iOS 26 and later: a BGContinuedProcessingTask, submitted when a download starts, lets the app keep running for the whole queue; iOS shows its own
/// progress card (title, percentage, a stop control). Its identifier is "<bundle id>.download.queue", permitted by the
/// `$(PRODUCT_BUNDLE_IDENTIFIER).download.*` entry of BGTaskSchedulerPermittedIdentifiers in Info.plist.
/// Without it (iOS refused, or an older iOS): the usual short background grace period, then the download pauses cleanly (every finished chunk is
/// journaled) and carries on when the app is opened again. A notification says so, and reports a download that finished or failed while away.
@MainActor final class SteamBackground {
    static let shared = SteamBackground()

    private weak var store: SteamStore?
    private var graceTask: UIBackgroundTaskIdentifier = .invalid
    private var continued: AnyObject?            // BGContinuedProcessingTask (iOS 26+)
    private var continuedPending = false
    private var registered: String?
    private var observing = false
    private var askedNotifications = false
    private var logged = 0
    private var currentName = ""
    private var lastCardText = Date.distantPast

    private func log(_ line: String) {
        guard logged < 60 else { return }
        logged += 1
        SteamLog.event("[bg-download] " + line)
    }

    private var isBackground: Bool { UIApplication.shared.applicationState != .active }

    /// The permitted "<bundle id>.download.*" identifier from Info.plist, made concrete.
    private var taskIdentifier: String? {
        let permitted = Bundle.main.object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers") as? [String] ?? []
        guard let wildcard = permitted.first(where: { $0.hasSuffix(".download.*") }) else { return nil }
        return String(wildcard.dropLast()) + "queue"
    }

    func attach(_ store: SteamStore) {
        self.store = store
        guard !observing else { return }
        observing = true
        // The task handler must be registered before the app finishes launching is NOT required for continued-processing tasks; register lazily on first use.
        NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                if self?.store?.hasActiveDownload == true { self?.log("left the screen keep-alive=\(DownloadKeepAlive.shared.isRunning ? 1 : 0) continued=\(self?.continued == nil ? 0 : 1)") }
                self?.beginGrace()
            }
        }
        NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.endGrace()
                self?.store?.resumeAfterBackground()
            }
        }
    }

    /// A download became active.
    func downloadStarted(name: String) {
        currentName = name
        DownloadKeepAlive.shared.hold("steam")           // the app keeps running, un-throttled, while the queue has something in it
        requestNotificationPermission()
        DownloadActivity.shared.begin(store: "steam", name: name)
        // With the Live Activity there is one card; without it (not in this install, or turned off) iOS's own download card does the job.
        if #available(iOS 26.0, *), !DownloadActivity.shared.hasCard("steam") { submitContinued() }
        if #available(iOS 26.0, *), let task = continued as? BGContinuedProcessingTask {
            task.updateTitle("Downloading \(name)", subtitle: "Steam \u{00B7} Preparing\u{2026}")
            lastCardText = Date()
        }
        if isBackground { beginGrace() }
    }

    func progress(_ progress: SteamDownloadProgress) {
        DownloadActivity.shared.update(store: "steam", name: currentName, progress: progress, waiting: store?.queueOrder.count ?? 0)
        if #available(iOS 26.0, *), let task = continued as? BGContinuedProcessingTask {
            let total = Int64(clamping: max(progress.totalBytes, 1))
            if task.progress.totalUnitCount != total { task.progress.totalUnitCount = total }
            task.progress.completedUnitCount = Int64(clamping: min(progress.doneBytes, progress.totalBytes))
            // The card's words: percent, how much of how much, the speed and the time left (once a second is plenty).
            if Date().timeIntervalSince(lastCardText) >= 1 {
                lastCardText = Date()
                task.updateTitle("Downloading \(currentName)", subtitle: DownloadCardText.subtitle(progress, waiting: store?.queueOrder.count ?? 0))
            }
        }
    }

    enum Outcome { case completed, failed(String), paused }

    /// One download ended. `queueEmpty`: nothing else is waiting.
    func downloadEnded(name: String, outcome: Outcome, queueEmpty: Bool) {
        if isBackground {
            switch outcome {
            case .completed: notify("\(name) is ready to play", body: "The Steam download finished.")
            case .failed(let reason): notify("\(name) download stopped", body: reason)
            case .paused: break
            }
        }
        if queueEmpty {
            switch outcome {
            case .completed: DownloadActivity.shared.end(store: "steam", failed: false, message: "\(name) is ready to play", finished: true)
            case .failed(let reason): DownloadActivity.shared.end(store: "steam", failed: true, message: "\(name) stopped: \(reason)", finished: true)
            case .paused:
                let waitingToResume = store?.downloads.values.contains { $0.state == .paused } == true
                if waitingToResume, !AppModel.shared.session.isActive { DownloadActivity.shared.paused(store: "steam", name: name) }
                else { DownloadActivity.shared.end(store: "steam", failed: false, message: nil, finished: false) }
            }
        }
        guard queueEmpty else { return }
        DownloadKeepAlive.shared.release("steam")
        finishContinued(success: { if case .completed = outcome { return true }; return false }())
        endGrace()
    }

    // MARK: iOS 26 continued processing

    @available(iOS 26.0, *)
    private func submitContinued() {
        guard continued == nil, !continuedPending, let identifier = taskIdentifier else { return }
        if registered != identifier {
            let ok = BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: .main) { [weak self] task in
                guard let task = task as? BGContinuedProcessingTask else { task.setTaskCompleted(success: false); return }
                MainActor.assumeIsolated { self?.attach(task) }
            }
            guard ok else { log("register refused"); return }
            registered = identifier
        }
        let request = BGContinuedProcessingTaskRequest(identifier: identifier, title: "Downloading \(currentName)", subtitle: "Steam download")
        request.strategy = .fail
        do {
            try BGTaskScheduler.shared.submit(request)
            continuedPending = true
            log("continued-processing submitted")
        } catch {
            log("continued-processing refused: \((error as NSError).code)")
        }
    }

    @available(iOS 26.0, *)
    private func attach(_ task: BGContinuedProcessingTask) {
        continuedPending = false
        continued = task
        task.progress.totalUnitCount = 1
        task.expirationHandler = { [weak self] in
            DispatchQueue.main.async {
                self?.log("continued-processing expired; pausing downloads")
                self?.store?.pauseForBackground()
                self?.notify("Download paused", body: "Open the app to continue downloading.")
                self?.finishContinued(success: false)
            }
        }
        log("continued-processing running")
        if store?.hasActiveDownload != true { finishContinued(success: true) }
    }

    private func finishContinued(success: Bool) {
        if #available(iOS 26.0, *), let task = continued as? BGContinuedProcessingTask {
            task.setTaskCompleted(success: success)
            log("continued-processing completed success=\(success ? 1 : 0)")
        }
        continued = nil
    }

    // MARK: Short grace period (all iOS versions)

    private func beginGrace() {
        guard graceTask == .invalid, continued == nil, !DownloadKeepAlive.shared.isRunning, store?.hasActiveDownload == true else { return }
        graceTask = UIApplication.shared.beginBackgroundTask(withName: "Steam download") { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.continued == nil {          // continued processing keeps the app running; only pause without it
                    self.log("background time over; pausing downloads")
                    self.store?.pauseForBackground()
                    self.notify("Download paused", body: "Open the app to continue downloading.")
                }
                self.endGrace()
            }
        }
        log("background grace begun continued=\(continued == nil ? 0 : 1)")
    }

    private func endGrace() {
        guard graceTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(graceTask)
        graceTask = .invalid
    }

    // MARK: Notifications

    private func requestNotificationPermission() {
        guard !askedNotifications else { return }
        askedNotifications = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            DispatchQueue.main.async { SteamBackground.shared.log("notifications granted=\(granted ? 1 : 0)") }
        }
    }

    private func notify(_ title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title; content.body = body; content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "f4.download.\(UUID().uuidString)", content: content, trigger: nil))
    }
}
