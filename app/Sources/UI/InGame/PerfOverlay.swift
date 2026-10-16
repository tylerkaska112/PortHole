// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
import SwiftUI

/// One number the performance overlay can show.
enum PerfMetric: String, CaseIterable, Identifiable {
    case fps, lowFPS, frameTime, cpu, busiestThread, gpuBusy, gpuFrame, memory, freeMemory, gpuMemory, thermal, battery, powerMode, swap

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fps: "FPS"
        case .lowFPS: "1% low"
        case .frameTime: "Frame time"
        case .cpu: "CPU"
        case .busiestThread: "Busiest thread"
        case .gpuBusy: "GPU busy"
        case .gpuFrame: "GPU frame"
        case .memory: "Memory"
        case .freeMemory: "Free memory"
        case .gpuMemory: "GPU memory"
        case .thermal: "Heat"
        case .battery: "Battery"
        case .powerMode: "Power mode"
        case .swap: "Swap file"
        }
    }

    /// These need the engine's slower measurements, which Porthole only takes while something is asking for them.
    var needsDetail: Bool { [.busiestThread, .gpuBusy, .gpuFrame, .swap].contains(self) }
}

enum OverlayCorner: String, CaseIterable, Identifiable {
    case topLeading, topTrailing, bottomLeading, bottomTrailing
    var id: String { rawValue }
    var title: String {
        switch self {
        case .topLeading: "Top left"
        case .topTrailing: "Top right"
        case .bottomLeading: "Bottom left"
        case .bottomTrailing: "Bottom right"
        }
    }
}

extension OverlayCorner {
    var anchor: UnitPoint {
        switch self { case .topLeading: .topLeading; case .topTrailing: .topTrailing; case .bottomLeading: .bottomLeading; case .bottomTrailing: .bottomTrailing }
    }
    var alignment: Alignment {
        switch self { case .topLeading: .topLeading; case .topTrailing: .topTrailing; case .bottomLeading: .bottomLeading; case .bottomTrailing: .bottomTrailing }
    }
}

enum OverlaySize: String, CaseIterable, Identifiable {
    case small, medium, large
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var font: CGFloat { switch self { case .small: 11; case .medium: 13; case .large: 16 } }
}

/// What the performance overlay shows and where. Off until the player turns it on in the in-game menu; kept between games.
@MainActor
final class PerfOverlaySettings: ObservableObject {
    static let shared = PerfOverlaySettings()
    private let defaults = UserDefaults.standard
    private static let prefix = "f4.overlay."

    @Published var enabled: Bool { didSet { save() } }
    @Published var metrics: Set<PerfMetric> { didSet { save() } }
    @Published var corner: OverlayCorner { didSet { save() } }
    @Published var size: OverlaySize { didSet { save() } }
    @Published var opacity: Double { didSet { save() } }
    /// One line of numbers instead of a list.
    @Published var asLine: Bool { didSet { save() } }
    @Published var showGraph: Bool { didSet { save() } }
    /// The full text block the old readout had: input counters, engine memory and swap lines.
    @Published var developerDetails: Bool { didSet { save() } }

    private init() {
        let d = UserDefaults.standard, p = Self.prefix
        enabled = d.bool(forKey: p + "enabled")
        if let raw = d.array(forKey: p + "metrics") as? [String] {
            metrics = Set(raw.compactMap(PerfMetric.init(rawValue:)))
        } else {
            metrics = [.fps, .frameTime, .cpu, .memory, .thermal]
        }
        corner = OverlayCorner(rawValue: d.string(forKey: p + "corner") ?? "") ?? .topTrailing
        size = OverlaySize(rawValue: d.string(forKey: p + "size") ?? "") ?? .medium
        opacity = d.object(forKey: p + "opacity") as? Double ?? 0.75
        asLine = d.bool(forKey: p + "line")
        showGraph = d.bool(forKey: p + "graph")
        developerDetails = d.bool(forKey: p + "dev")
    }

    private func save() {
        let p = Self.prefix
        defaults.set(enabled, forKey: p + "enabled")
        defaults.set(metrics.map(\.rawValue).sorted(), forKey: p + "metrics")
        defaults.set(corner.rawValue, forKey: p + "corner")
        defaults.set(size.rawValue, forKey: p + "size")
        defaults.set(opacity, forKey: p + "opacity")
        defaults.set(asLine, forKey: p + "line")
        defaults.set(showGraph, forKey: p + "graph")
        defaults.set(developerDetails, forKey: p + "dev")
    }

    func toggle(_ metric: PerfMetric) {
        if metrics.contains(metric) { metrics.remove(metric) } else { metrics.insert(metric) }
    }

    /// Whether the engine's slower measurements should run: only while the overlay is on and something shown needs them.
    var wantsDetail: Bool { enabled && (developerDetails || metrics.contains(where: \.needsDetail)) }
}

/// The latest numbers and a short history for the graph.
@MainActor
final class PerfOverlayModel: ObservableObject {
    @Published var sample = TelemetrySample()
    @Published var extra = ""
    /// The most height the list of numbers should take (about half the screen), so on a small screen it spreads into columns and leaves the game visible.
    @Published var tallest: CGFloat = 10_000
    @Published private(set) var fpsHistory: [Double] = []
    static let historyLength = 60

    func push(_ s: TelemetrySample) {
        sample = s
        fpsHistory.append(s.fps)
        if fpsHistory.count > Self.historyLength { fpsHistory.removeFirst(fpsHistory.count - Self.historyLength) }
    }

    func reset() { sample = TelemetrySample(); fpsHistory = [] }

    struct Row: Identifiable {
        let metric: PerfMetric
        let label: String
        let value: String
        let tint: Color?
        var id: String { metric.rawValue }
    }

    /// The rows for the metrics the player picked, always in the same order.
    func rows(for settings: PerfOverlaySettings) -> [Row] {
        let s = sample
        var out: [Row] = []
        for metric in PerfMetric.allCases where settings.metrics.contains(metric) {
            switch metric {
            case .fps:
                out.append(Row(metric: metric, label: "FPS", value: String(format: "%.0f", s.fps), tint: s.fps > 0 && s.fps < 25 ? Theme.bad : (s.fps < 45 && s.fps > 0 ? Theme.warn : nil)))
            case .lowFPS:
                out.append(Row(metric: metric, label: "Low", value: String(format: "%.0f", s.lowFPS), tint: nil))
            case .frameTime:
                out.append(Row(metric: metric, label: "Frame", value: String(format: "%.1f ms", s.frameMs), tint: nil))
            case .cpu:
                out.append(Row(metric: metric, label: "CPU", value: String(format: "%.0f%%", s.cpuPercent), tint: nil))
            case .busiestThread:
                if let t = s.topThreadPercent { out.append(Row(metric: metric, label: "Top thread", value: String(format: "%.0f%%", t), tint: t > 90 ? Theme.warn : nil)) }
            case .gpuBusy:
                if let g = s.gpuBusyPercent { out.append(Row(metric: metric, label: "GPU", value: String(format: "%.0f%%", g), tint: g > 95 ? Theme.warn : nil)) }
            case .gpuFrame:
                if let g = s.gpuFrameMs { out.append(Row(metric: metric, label: "GPU frame", value: String(format: "%.1f ms", g), tint: nil)) }
            case .memory:
                out.append(Row(metric: metric, label: "Mem", value: String(format: "%.2f GB", s.footprintMB / 1024), tint: s.availableMB > 0 && s.availableMB < 500 ? Theme.bad : nil))
            case .freeMemory:
                out.append(Row(metric: metric, label: "Free", value: String(format: "%.2f GB", s.availableMB / 1024), tint: s.availableMB > 0 && s.availableMB < 500 ? Theme.bad : nil))
            case .gpuMemory:
                out.append(Row(metric: metric, label: "GPU mem", value: String(format: "%.2f GB", s.gpuMB / 1024), tint: nil))
            case .thermal:
                out.append(Row(metric: metric, label: "Heat", value: s.thermal, tint: ["serious", "critical"].contains(s.thermal) ? Theme.bad : (s.thermal == "fair" ? Theme.warn : nil)))
            case .battery:
                if let b = s.battery {
                    var v = String(format: "%.0f%%", b * 100)
                    if let d = s.drainPerHour { v += String(format: " (%@%.0f/h)", d > 0 ? "-" : "+", abs(d)) }
                    out.append(Row(metric: metric, label: "Battery", value: v, tint: b < 0.15 ? Theme.bad : nil))
                }
            case .powerMode:
                out.append(Row(metric: metric, label: "Mode", value: s.mode.isEmpty ? "-" : s.mode, tint: nil))
            case .swap:
                if let used = s.engine.swapFileUsedMB, let cap = s.engine.swapFileCapMB, cap > 0 {
                    let pct = Double(used) / Double(cap) * 100
                    out.append(Row(metric: metric, label: "Swap", value: String(format: "%.1f / %.1f GB", Double(used) / 1024, Double(cap) / 1024), tint: pct >= 90 ? Theme.bad : nil))
                }
            }
        }
        return out
    }
}

struct FPSGraph: View {
    let values: [Double]
    var body: some View {
        GeometryReader { geo in
            let top = max(60, (values.max() ?? 60).rounded(.up))
            Path { path in
                guard values.count > 1 else { return }
                let step = geo.size.width / CGFloat(PerfOverlayModel.historyLength - 1)
                let offset = geo.size.width - CGFloat(values.count - 1) * step
                for (i, v) in values.enumerated() {
                    let x = offset + CGFloat(i) * step
                    let y = geo.size.height * (1 - CGFloat(min(v, top) / top))
                    if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
                }
            }
            .stroke(Theme.accent, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
    }
}

/// Puts its children in columns: a new column starts when the next one would not fit in `maxHeight`.
struct OverlayColumns: SwiftUI.Layout {
    var maxHeight: CGFloat
    var spacing: CGFloat = 2
    var columnSpacing: CGFloat = 16

    private struct Arrangement { var columns: [[Int]] = [[]]; var widths: [CGFloat] = [0]; var heights: [CGFloat] = [0] }

    private func arrange(_ subviews: LayoutSubviews) -> Arrangement {
        var a = Arrangement()
        for (i, view) in subviews.enumerated() {
            let s = view.sizeThatFits(.unspecified)
            let last = a.columns.count - 1
            let gap = a.columns[last].isEmpty ? 0 : spacing
            if !a.columns[last].isEmpty, a.heights[last] + gap + s.height > maxHeight {
                a.columns.append([]); a.widths.append(0); a.heights.append(0)
            }
            let c = a.columns.count - 1
            a.heights[c] += (a.columns[c].isEmpty ? 0 : spacing) + s.height
            a.widths[c] = max(a.widths[c], s.width)
            a.columns[c].append(i)
        }
        return a
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout ()) -> CGSize {
        let a = arrange(subviews)
        return CGSize(width: a.widths.reduce(0, +) + columnSpacing * CGFloat(max(0, a.widths.count - 1)), height: a.heights.max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout ()) {
        let a = arrange(subviews)
        var x = bounds.minX
        for (c, column) in a.columns.enumerated() {
            var y = bounds.minY
            for i in column {
                let h = subviews[i].sizeThatFits(.unspecified).height
                subviews[i].place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(width: a.widths[c], height: h))
                y += h + spacing
            }
            x += a.widths[c] + columnSpacing
        }
    }
}

/// Shrinks its content to fit the room, from the corner it sits in. A last resort: columns come first.
private struct OverlayFit<Content: View>: View {
    let available: CGSize
    let corner: OverlayCorner
    @ViewBuilder var content: Content
    @State private var natural = CGSize.zero

    var body: some View {
        let known = natural.width > 0 && natural.height > 0
        let scale = known ? min(1, available.width / natural.width, available.height / natural.height) : 1
        content
            .fixedSize()
            .background(GeometryReader { proxy in
                Color.clear
                    .onAppear { natural = proxy.size }
                    .onChange(of: proxy.size) { _, new in natural = new }
            })
            .scaleEffect(scale, anchor: corner.anchor)
            .frame(width: known ? natural.width * scale : nil, height: known ? natural.height * scale : nil, alignment: corner.alignment)
    }
}

/// The overlay itself. It never takes touches: they go to the game.
struct PerfOverlayView: View {
    @ObservedObject var settings: PerfOverlaySettings
    @ObservedObject var model: PerfOverlayModel

    private let padding: CGFloat = 8

    var body: some View {
        // The room is whatever the host gives: the HUD makes it fill the free part of the screen, and the overlay sits in its corner of that.
        GeometryReader { geo in
            overlay(room: geo.size)
                .frame(width: geo.size.width, height: geo.size.height, alignment: settings.corner.alignment)
        }
    }

    private func overlay(room: CGSize) -> some View {
        let rows = model.rows(for: settings)
        let font = Font.system(size: settings.size.font, weight: .semibold, design: .monospaced)
        let empty = rows.isEmpty && !settings.showGraph && !settings.developerDetails
        return OverlayFit(available: CGSize(width: max(60, room.width), height: max(60, room.height)), corner: settings.corner) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    if settings.asLine {
                        HStack(spacing: 8) { ForEach(rows) { row in Text(row.value).foregroundStyle(row.tint ?? .white) } }
                            .font(font)
                    } else {
                        // Rows in as many columns as the height allows (the graph counts as a row).
                        OverlayColumns(maxHeight: max(40, min(room.height, model.tallest) - padding * 2 - 4)) {
                            ForEach(rows) { row in
                                HStack(spacing: 8) {
                                    Text(row.label).foregroundStyle(.white.opacity(0.6))
                                    Spacer(minLength: 6)
                                    Text(row.value).foregroundStyle(row.tint ?? .white)
                                }
                                .font(font)
                            }
                        }
                    }
                    if settings.showGraph {
                        FPSGraph(values: model.fpsHistory)
                            .frame(width: max(110, settings.size.font * 11), height: settings.size.font * 3)
                    }
                }
                if settings.developerDetails {
                    Text(model.sample.full + (model.extra.isEmpty ? "" : "\n" + model.extra))
                        .font(.system(size: max(9, settings.size.font - 3), design: .monospaced))
                        .foregroundStyle(.white.opacity(0.8))
                        .fixedSize(horizontal: true, vertical: true)
                }
            }
            .padding(.horizontal, 9).padding(.vertical, padding - 2)
            .background(Color.black.opacity(settings.opacity * 0.8), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .opacity(empty ? 0 : 1)
        }
    }
}
