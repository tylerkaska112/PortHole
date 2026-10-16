// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
import SwiftUI

// The Reports section and its pages, on the kit's rows so a controller can use them.

/// The Reports tab: every game people have reported, newest or most-reported first; press one to read its reports.
struct ReportsScreen: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.focusScope) private var scope
    @State private var query = ""
    @State private var sort = "reports"
    @State private var games: [CompatGameSummary] = []
    @State private var loading = false
    @State private var loadedAll = false
    @State private var error: String?
    @State private var open: CompatGameSummary?
    private let device = CompatDeviceInfo.current

    var body: some View {
        Group {
            if let open {
                VStack(alignment: .leading, spacing: 0) {
                    PillButton(id: "rs-back", title: "Reports", symbol: "chevron.left") { self.open = nil }.padding(.horizontal, 24).padding(.top, 8)
                    CompatGameView(gameID: open.id, fallbackTitle: open.title, libraryGame: libraryGame(for: open))
                }
            } else { list }
        }
        .onNavBack { if open != nil { open = nil; return true }; return false }
    }

    private var list: some View {
        FocusScroll {
            PageScaffold(title: "Reports", symbol: "checkmark.seal.fill") {
                FlowLayout(spacing: 10) {
                    SegmentedPills(options: [.init(id: "reports", title: "Most reports"), .init(id: "name", title: "A to Z")], selection: sort) { sort = $0 }
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass").foregroundStyle(Theme.textDim)
                        TextField("Search games", text: $query).textInputAutocapitalization(.never).autocorrectionDisabled().foregroundStyle(Theme.text)
                    }
                    .padding(.horizontal, 14).frame(minHeight: 40).background(Theme.panel, in: Capsule()).overlay(Capsule().strokeBorder(Theme.line, lineWidth: 1))
                    .focusTarget("rs-search", radius: 20, scale: 1.02, action: {})
                }
                LazyVStack(spacing: 8) {
                    ForEach(games) { game in
                        RowBase(id: "rs-\(game.id)", title: game.title ?? "Untitled game",
                                subtitle: "\(game.reportCount) report\(game.reportCount == 1 ? "" : "s") \u{00B7} latest \(CompatDeviceInfo.date(game.lastReport))", action: { open = game }) {
                            if let verdict = game.badge.verdict { CompatBadgePill(verdict: verdict, compact: true) }
                            else if let past = game.badge.past { CompatPastPill(past: past, compact: true) }
                        }
                        .onAppear { if game.id == games.last?.id { Task { await loadMore() } } }
                    }
                    if loading { ProgressView().tint(Theme.accent).frame(maxWidth: .infinity).padding() }
                }
                if let error {
                    SettingsGroup {
                        if NetworkStatus.shared.isOnline { Text(error).font(.footnote).foregroundStyle(Theme.bad).padding(.horizontal, 6) }
                        else { OfflineChip(detail: "this list needs a connection").padding(.horizontal, 6) }
                        Text("The reports are stored on a home server, so they can be unavailable while it is off.").font(.footnote).foregroundStyle(Theme.textDim).padding(.horizontal, 6)
                        ActionRow(id: "rs-retry", symbol: "arrow.clockwise", title: "Try again", chevron: false) { Task { await reload() } }
                    }
                } else if !loading && games.isEmpty {
                    Text(query.isEmpty ? "No reports have been sent yet." : "No game matches \u{201C}\(query)\u{201D}.").foregroundStyle(Theme.textDim).padding(.horizontal, 6)
                }
            }
            .frame(maxWidth: 900).frame(maxWidth: .infinity)
        }
        .task(id: "\(query)|\(sort)") {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await reload()
        }
    }

    private func libraryGame(for summary: CompatGameSummary) -> Game? { model.games.first { CompatStore.shared.candidateIDs(for: $0).contains(summary.id) } }

    private func reload() async {
        loading = true; error = nil; loadedAll = false
        do {
            games = try await CompatClient.standard().games(query: query.trimmingCharacters(in: .whitespaces), sort: sort, limit: 30, offset: 0, device: device?.id)
            loadedAll = games.count < 30
        } catch { self.error = error.localizedDescription; games = [] }
        loading = false
    }

    private func loadMore() async {
        guard !loading, !loadedAll else { return }
        loading = true
        do {
            let more = try await CompatClient.standard().games(query: query.trimmingCharacters(in: .whitespaces), sort: sort, limit: 30, offset: games.count, device: device?.id)
            games += more
            loadedAll = more.count < 30
        } catch { self.error = error.localizedDescription }
        loading = false
    }
}

/// Everything the server knows about one game: the badge, how it does on each phone, and the individual reports.
struct CompatGameView: View {
    let gameID: String
    var fallbackTitle: String?
    var libraryGame: Game?
    @EnvironmentObject private var model: AppModel
    @State private var detail: CompatGameDetail?
    @State private var reports: [CompatPublicReport] = []
    @State private var loading = true
    @State private var loadedAll = false
    @State private var missing = false
    @State private var error: String?
    @State private var myDeviceOnly = false
    @State private var writing: Game?
    @State private var flagging: CompatPublicReport?
    @State private var notice: String?
    @State private var showDetail = false
    private let device = CompatDeviceInfo.current

    var body: some View {
        FocusScroll {
            PageScaffold(title: detail?.title ?? fallbackTitle ?? "Game", symbol: "checkmark.seal.fill") {
                header
                if showDetail, let summary = detail?.settingsSummary {
                    SettingsGroup(title: "When it works great, people use") {
                        ForEach(summary.items.filter { ["launch", "power", "desktopDisplay", "swapMB", "vramMB", "preciseMath"].contains($0.key) }) { item in
                            ValueRow(id: "cg-s-\(item.key)", title: CompatSettings.describe(item.key, item.value), value: "\(item.count) of \(summary.reports)")
                        }
                    }
                }
                if showDetail, let detail, !detail.devices.isEmpty {
                    SettingsGroup(title: "By device") {
                        ForEach(detail.devices) { d in
                            RowBase(id: "cg-d-\(d.deviceId)", symbol: "iphone", title: d.device, subtitle: d.deviceId == device?.id ? "yours" : nil, action: {}) {
                                HStack(spacing: 8) { CompatBadgePill(verdict: d.verdict, compact: true); Text("\(d.reports)").font(.footnote.monospacedDigit()).foregroundStyle(Theme.textDim) }
                            }
                        }
                    }
                }
                SettingsGroup(title: "Reports") {
                    if let game = libraryGame { ActionRow(id: "cg-write", symbol: "square.and.pencil", title: "Write a report", chevron: false) { writing = game } }
                    if device != nil { ToggleRow(id: "cg-mine", symbol: "iphone", title: "Only reports from my device", isOn: $myDeviceOnly) }
                    ToggleRow(id: "cg-detail", symbol: "list.bullet.below.rectangle", title: "Show the details",
                              info: "Adds the settings that worked, how it runs on each device, and the iOS version, app version, files source and tags of every report.", isOn: $showDetail)
                    ForEach(reports) { report in reportRow(report) }
                    if loading { ProgressView().tint(Theme.accent).frame(maxWidth: .infinity).padding() }
                    else if !loadedAll && !reports.isEmpty { ActionRow(id: "cg-more", symbol: "ellipsis.circle", title: "Show more", chevron: false) { Task { await loadMore() } } }
                    if !loading && reports.isEmpty && !missing { Text(myDeviceOnly ? "No reports from your device yet." : "No reports yet.").foregroundStyle(Theme.textDim).padding(.horizontal, 6) }
                }
                if let error {
                    SettingsGroup {
                        if NetworkStatus.shared.isOnline { Text(error).font(.footnote).foregroundStyle(Theme.bad).padding(.horizontal, 6) }
                        else { OfflineChip(detail: "this list needs a connection").padding(.horizontal, 6) }
                        ActionRow(id: "cg-retry", symbol: "arrow.clockwise", title: "Try again", chevron: false) { Task { await reload() } }
                    }
                }
                if let notice { Text(notice).font(.footnote).foregroundStyle(Theme.good).padding(.horizontal, 6) }
            }
            .frame(maxWidth: 820).frame(maxWidth: .infinity)
        }
        .task(id: gameID) { await reload() }
        .onChange(of: myDeviceOnly) { _, _ in Task { await reload(keepDetail: true) } }
        .sheet(item: $writing, onDismiss: { Task { await reload() } }) { ReportSheet(game: $0).environmentObject(model).preferredColorScheme(Theme.scheme) }
        .confirm("Flag this report?", message: "If other people flag it too, it's hidden until it has been looked at.", confirmTitle: "Flag it",
                 isPresented: Binding(get: { flagging != nil }, set: { if !$0 { flagging = nil } })) { if let r = flagging { Task { await flag(r) } } }
    }

    @ViewBuilder private var header: some View {
        SettingsGroup {
            if let detail {
                if detail.titlePending { Text("Title waiting for review").font(.footnote).foregroundStyle(Theme.textDim).padding(.horizontal, 6) }
                if let overall = detail.badge.overall {
                    ValueRow(id: "cg-overall", symbol: overall.verdict.symbol, title: overall.verdict.title,
                             value: "\(overall.reports) report\(overall.reports == 1 ? "" : "s")" + (overall.confidence == "low" ? " \u{00B7} not many yet" : ""), statusColor: overall.verdict.color)
                    if let mine = detail.badge.forDevice, let device { ValueRow(id: "cg-mine-badge", symbol: "iphone", title: "On \(device.name)", value: mine.verdict.title, statusColor: mine.verdict.color) }
                } else if let past = detail.badge.past, let earlier = detail.badge.earlier?.reports {
                    ValueRow(id: "cg-overall", symbol: past.symbol, title: past.text, value: "\(earlier) earlier report\(earlier == 1 ? "" : "s")", statusColor: past.color)
                    Text(past.explanation).font(.footnote).foregroundStyle(Theme.textDim).padding(.horizontal, 6)
                } else if let earlier = detail.badge.earlier?.reports, earlier > 0 {
                    ValueRow(id: "cg-overall", symbol: "questionmark.circle.fill", title: "Not yet tested", value: "Engine changed")
                    Text("The game engine has changed since \(earlier == 1 ? "the report below was" : "the \(earlier) reports below were") sent, so how this game runs may be different now. They are kept for reference.")
                        .font(.footnote).foregroundStyle(Theme.textDim).padding(.horizontal, 6)
                } else {
                    ValueRow(id: "cg-overall", symbol: "questionmark.circle.fill", title: "Not yet tested", value: "No reports")
                }
            } else if missing {
                ValueRow(id: "cg-overall", symbol: "questionmark.circle.fill", title: "Not yet tested", value: "No reports")
                Text("Play it for a few minutes and send the first report.").font(.footnote).foregroundStyle(Theme.textDim).padding(.horizontal, 6)
            } else if loading { ProgressView().tint(Theme.accent).frame(maxWidth: .infinity).padding() }
        }
    }

    private func reportRow(_ r: CompatPublicReport) -> some View {
        var lines = [showDetail ? "iOS \(r.ios) \u{00B7} app \(r.appVersion) \u{00B7} \(r.stability.title) \u{00B7} files from \(r.source.title.components(separatedBy: " (").first ?? r.source.title)" : r.stability.title]
        if r.onThisEngine == false { lines.append("Earlier engine (\(CompatEngine.describe(r.engine))): not counted") }
        if let p = r.perf, p.fpsAvg != nil || p.minutes != nil {
            lines.append([p.fpsAvg.map { String(format: "%.0f fps avg", $0) }, p.fpsLow.map { String(format: "%.0f low", $0) }, p.minutes.map { "\($0) min" }].compactMap { $0 }.joined(separator: " \u{00B7} "))
        }
        if showDetail, let s = r.settings { lines.append(s.summary) }
        if showDetail, !r.tags.isEmpty { lines.append(r.tags.map(\.title).joined(separator: " \u{00B7} ")) }
        if let c = r.comment, !c.isEmpty { lines.append("\u{201C}\(c)\u{201D}") }
        return RowBase(id: "cg-r-\(r.id)", symbol: r.rating.symbol, tint: r.rating.color, title: "\(r.device) \u{00B7} \(CompatDeviceInfo.date(r.date))", subtitle: lines.joined(separator: "\n"),
                       info: "Press to flag this report if it breaks the rules. If other people flag it too, it is hidden until it has been looked at.", action: { flagging = r }) {
            CompatBadgePill(verdict: r.rating, compact: true)
        }
    }

    private func reload(keepDetail: Bool = false) async {
        loading = true; error = nil; loadedAll = false; missing = false
        if !keepDetail { detail = nil }
        reports = []
        let client = CompatClient.standard()
        do {
            if !keepDetail { detail = try await client.game(id: gameID, device: device?.id) }
            reports = try await client.reports(gameID: gameID, device: myDeviceOnly ? device?.id : nil, limit: 20, offset: 0)
            loadedAll = reports.count < 20
        } catch let CompatError.server(404, _) { missing = true; detail = nil }
        catch { self.error = error.localizedDescription }
        loading = false
    }

    private func loadMore() async {
        loading = true
        do {
            let more = try await CompatClient.standard().reports(gameID: gameID, device: myDeviceOnly ? device?.id : nil, limit: 20, offset: reports.count)
            reports += more
            loadedAll = more.count < 20
        } catch { self.error = error.localizedDescription }
        loading = false
    }

    private func flag(_ r: CompatPublicReport) async {
        do { try await CompatClient.standard().flag(reportID: r.id); notice = "Thanks. If other people flag it too, it's hidden until it has been looked at." }
        catch { notice = error.localizedDescription }
    }
}

/// A game's reports in a sheet (from a game's own page).
struct CompatGameSheet: View {
    let gameID: String
    let title: String
    let game: Game?
    let scope: FocusScope
    let done: () -> Void

    var body: some View {
        ZStack {
            AmbientBackdrop(animated: false)
            VStack(alignment: .leading, spacing: 0) {
                HStack { Spacer(); PillButton(id: "cgs-close", title: "Close", symbol: "xmark", action: done) }.padding(.horizontal, 24).padding(.top, 16)
                CompatGameView(gameID: gameID, fallbackTitle: title, libraryGame: game)
            }
        }
        .navScope(scope)
        .onAppear { scope.onBack = done; scope.defaultFocus = "cgs-close"; scope.focused = "cgs-close" }
        .presentationBackground(Theme.background)
        .preferredColorScheme(Theme.scheme)
    }
}

// MARK: - Write a report

struct ReportSheet: View {
    let game: Game
    var crashed = false
    /// The running session's numbers so far (when the form is opened from inside a game); otherwise the last finished session's.
    var liveStats: CompatSessionStats?
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var compat = CompatStore.shared
    @State private var scope = FocusScope()
    @State private var rating: CompatVerdict?
    @State private var stability: CompatStability
    @State private var tags: Set<CompatTag> = []
    @State private var source: CompatSource?
    @State private var includeMeasured = true
    @State private var shareSettings = true
    @State private var comment = ""
    @State private var sending = false
    @State private var error: String?
    @State private var outcome: CompatStore.SubmitResult?

    init(game: Game, crashed: Bool = false, liveStats: CompatSessionStats? = nil) {
        self.game = game; self.crashed = crashed; self.liveStats = liveStats
        _stability = State(initialValue: crashed ? .sometimes : .never)
    }

    private var stats: CompatSessionStats? { liveStats ?? compat.lastStats(for: game) }
    private var minutes: Int { stats?.minutes ?? Int((game.playSeconds ?? 0) / 60) }
    private var fromSteam: Bool { game.dockAppID != nil }
    private var enoughPlay: Bool { minutes >= CompatRules.minMinutesForWorking }
    private var problem: String? {
        guard let rating else { return "Choose how it ran." }
        if !fromSteam && source == nil { return "Say where the game's files came from." }
        if stability == .wont_launch && rating != .broken { return "A game that won't start can only be reported as \"Doesn't work\"." }
        if stability == .constantly && rating == .great { return "A game that crashes all the time can't be \"Works great\"." }
        if rating != .broken && !enoughPlay { return "Play for at least \(CompatRules.minMinutesForWorking) minutes before reporting that it works." }
        return nil
    }

    var body: some View {
        ZStack {
            AmbientBackdrop(animated: false)
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Report").font(.system(size: 26, weight: .heavy, design: .rounded)).foregroundStyle(Theme.text)
                    Spacer()
                    PillButton(id: "rp-close", title: outcome == nil ? "Cancel" : "Done", symbol: "xmark") { dismiss() }
                }
                .padding(.horizontal, 24).padding(.top, 18).padding(.bottom, 8)
                FocusScroll {
                    Group { if let outcome { done(outcome) } else { form } }
                        .frame(maxWidth: 680).frame(maxWidth: .infinity)
                }
            }
        }
        .navScope(scope)
        .onAppear { scope.onBack = { dismiss() }; scope.defaultFocus = "rp-v-\(CompatVerdict.allCases.first?.rawValue ?? "")"; scope.focused = scope.defaultFocus }
        .presentationBackground(Theme.background)
        .preferredColorScheme(Theme.scheme)
        .interactiveDismissDisabled(sending)
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsGroup(title: "How did \(game.name) run?") {
                ForEach(CompatVerdict.allCases) { verdict in
                    let blocked = verdict != .broken && !enoughPlay
                    RowBase(id: "rp-v-\(verdict.rawValue)", symbol: verdict.symbol, tint: verdict.color, title: verdict.title, subtitle: verdict.detail, action: { if !blocked { rating = verdict } }) {
                        if rating == verdict { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent) }
                    }
                    .opacity(blocked ? 0.45 : 1)
                }
                if !enoughPlay { Text("You've played \(minutes) min. Play for at least \(CompatRules.minMinutesForWorking) minutes to report that it works; a game that won't start can be reported at any time.").font(.footnote).foregroundStyle(Theme.textDim).padding(.horizontal, 6) }
            }
            SettingsGroup(title: "Did it crash?") {
                ChoiceRow(id: "rp-crash", symbol: "bolt.trianglebadge.exclamationmark.fill", title: "Crashes",
                          info: crashed ? "The app closed on its own while you were playing, so this starts on \"Crashes sometimes\". Change it if that's wrong." : nil,
                          options: CompatStability.allCases.map { ($0, $0.title) }, selection: $stability)
            }
            SettingsGroup(title: "Anything else?") {
                AdaptiveGrid(minWidth: 150, spacing: 8) {
                    ForEach(CompatTag.allCases) { tag in
                        let on = tags.contains(tag)
                        Button { if on { tags.remove(tag) } else { tags.insert(tag) } } label: {
                            Text(tag.title).font(.system(size: 13, weight: .semibold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.8)
                                .frame(maxWidth: .infinity, minHeight: 40).foregroundStyle(on ? Theme.onAccent : Theme.text)
                                .background { if on { Capsule().fill(Theme.accentGradient) } else { Capsule().fill(Theme.panelHigh) } }
                        }
                        .buttonStyle(.plain)
                        .focusTarget("rp-tag-\(tag.rawValue)", radius: 20, scale: 1.05) { if on { tags.remove(tag) } else { tags.insert(tag) } }
                    }
                }
            }
            SettingsGroup(title: "Where did the game come from?") {
                if fromSteam { ValueRow(id: "rp-src", symbol: "shippingbox.fill", title: "Files from", value: "Steam") }
                else {
                    ChoiceRow(id: "rp-src", symbol: "shippingbox.fill", title: "Files from",
                              info: "Different stores can ship different builds of the same game, so this matters. Pick from the list.",
                              options: [(CompatSource?.none, "Choose\u{2026}")] + CompatSource.allCases.map { (Optional($0), $0.title) }, selection: $source)
                }
            }
            SettingsGroup(title: "What to include") {
                ToggleRow(id: "rp-measured", symbol: "chart.bar.fill", title: "Include what the app measured",
                          subtitle: stats.map { "\(liveStats != nil ? "This session" : "Last session"): \($0.summary)" } ?? "No measurements from a recent session. The report will only say how long you've played.",
                          isOn: Binding(get: { includeMeasured && stats != nil }, set: { includeMeasured = $0 }))
                ToggleRow(id: "rp-settings", symbol: "slider.horizontal.3", title: "Share my settings for this game", subtitle: compat.currentSettings(for: game).summary,
                          info: "How the game was started and the performance settings it used. This helps people get the same result. Launch options you typed are never shared.", isOn: $shareSettings)
            }
            SettingsGroup(title: "Your note") {
                TextFieldRow(id: "rp-note", symbol: "text.bubble.fill", title: "Optional note", placeholder: "settings that helped, glitches\u{2026}",
                             info: "A person checks notes before they appear, so yours won't show straight away. Please don't mention where to get game files.", text: Binding(get: { comment }, set: { comment = String($0.prefix(400)) }))
            }
            SettingsGroup {
                if let error { if NetworkStatus.shared.isOnline { Text(error).font(.footnote).foregroundStyle(Theme.bad).padding(.horizontal, 6) }
                        else { OfflineChip(detail: "this list needs a connection").padding(.horizontal, 6) } }
                if let problem { Text(problem).font(.footnote).foregroundStyle(Theme.textDim).padding(.horizontal, 6) }
                PillButton(id: "rp-send", title: sending ? "Sending\u{2026}" : "Send report", symbol: "paperplane.fill", style: .primary, enabled: problem == nil && !sending) { Task { await send() } }
                Text("Sent: your device model, iOS and app version, the version of the game engine (\(CompatEngine.label)), and the answers above. Not sent: your name, any account, or anything that identifies you.")
                    .font(.footnote).foregroundStyle(Theme.textDim).padding(.horizontal, 6)
            }
        }
        .padding(.horizontal, 24).padding(.vertical, 12)
    }

    private func done(_ outcome: CompatStore.SubmitResult) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 54)).foregroundStyle(Theme.good).shadow(color: Theme.good.opacity(0.6), radius: 14)
            Text("Thank you").font(.system(size: 24, weight: .heavy, design: .rounded)).foregroundStyle(Theme.text)
            switch outcome {
            case .sent(let pending): Text(pending ? "Your report is in. Your note will appear once it has been checked." : "Your report is in and counts toward the badge.")
            case .queued: Text("The compatibility server couldn't be reached, so your report is saved and will be sent when it can.")
            }
            PillButton(id: "rp-done", title: "Done", style: .primary) { dismiss() }
        }
        .font(.subheadline).foregroundStyle(Theme.textDim).multilineTextAlignment(.center).padding(30).frame(maxWidth: .infinity)
        .onAppear { scope.focused = "rp-done" }
    }

    private func send() async {
        guard let rating else { return }
        sending = true; error = nil
        defer { sending = false }
        do {
            outcome = try await compat.submit(game: game, rating: rating, stability: stability, tags: tags.sorted { $0.rawValue < $1.rawValue },
                                              source: fromSteam ? .steam : (source ?? .other), stats: stats, shareNumbers: includeMeasured, shareSettings: shareSettings, comment: comment)
        } catch { self.error = error.localizedDescription }
    }
}
