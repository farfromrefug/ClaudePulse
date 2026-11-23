import SwiftUI
import AppKit

/// A small filled ring, the way Claude's own context meter reads: a faint track
/// with an arc sweeping clockwise from the top.
struct UsageRing: View {
    let fraction: Double
    var diameter: CGFloat = 11
    var lineWidth: CGFloat = 2
    var color: Color = .white

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, fraction)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: diameter, height: diameter)
    }
}

/// Colour ramp shared by the per-session ring and the global bars: the accent
/// colour until a window is worth worrying about, then amber, then red.
enum UsageTint {
    static func color(for fraction: Double, accent: Color) -> Color {
        switch fraction {
        case ..<0.7: return accent
        case ..<0.9: return .orange
        default: return .red
        }
    }
}

/// The account-wide limits, sized to sit in the panel's button row.
struct GlobalUsageView: View {
    let usage: UsageSnapshot
    private let settings = PanelSettings.shared

    var body: some View {
        let s = settings.textSize.scale
        HStack(spacing: 8) {
            ForEach(windows, id: \.label) { entry in
                HStack(spacing: 3) {
                    UsageRing(
                        fraction: entry.window.fraction,
                        diameter: 9 * s,
                        lineWidth: 1.8,
                        color: UsageTint.color(for: entry.window.fraction, accent: settings.accentColor)
                    )
                    Text(entry.label)
                        .font(.system(size: 9 * s, weight: .medium))
                        .foregroundStyle(.white.opacity(0.35))
                    Text(entry.window.percentText)
                        .font(.system(size: 9 * s, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.55))
                }
                .help(help(for: entry))
            }
        }
    }

    private struct Entry {
        let label: String
        let window: RateLimitWindow
    }

    /// Opus and Sonnet weekly windows only appear once they exist, so the row
    /// stays short on plans that do not have them.
    private var windows: [Entry] {
        let usage = usage.current()
        var entries: [Entry] = []
        if let five = usage.fiveHour { entries.append(Entry(label: "5h", window: five)) }
        if let week = usage.sevenDay { entries.append(Entry(label: "wk", window: week)) }
        if let opus = usage.sevenDayOpus { entries.append(Entry(label: "op", window: opus)) }
        if let sonnet = usage.sevenDaySonnet { entries.append(Entry(label: "so", window: sonnet)) }
        return entries
    }

    private func help(for entry: Entry) -> String {
        let name: String
        switch entry.label {
        case "5h": name = "5-hour session limit"
        case "wk": name = "Weekly limit"
        case "op": name = "Weekly Opus limit"
        default: name = "Weekly Sonnet limit"
        }
        var text = "\(name) — \(entry.window.percentText) used"
        if let reset = entry.window.resetText() { text += "\n\(reset)" }
        // Readings come from samples taken minutes apart, so say how old this
        // one is rather than implying it is live.
        if let age = ageText { text += "\n\(age)" }
        return text
    }

    private var ageText: String? {
        let age = Date().timeIntervalSince(usage.updatedAt)
        guard age > 300 else { return nil }
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        // A time of day says nothing about a reading from days ago.
        formatter.dateStyle = age > 12 * 3600 ? .medium : .none
        return "as of \(formatter.string(from: usage.updatedAt))"
    }
}


/// The limits on the collapsed capsule: a ring and a figure for the 5-hour and
/// the weekly window, which is all the room there is.
struct CompactUsageView: View {
    let usage: UsageSnapshot
    private let settings = PanelSettings.shared

    var body: some View {
        let s = settings.textSize.scale
        let usage = usage.current()
        HStack(spacing: 6) {
            ForEach(entries(usage), id: \.label) { entry in
                HStack(spacing: 2) {
                    UsageRing(
                        fraction: entry.window.fraction,
                        diameter: 8 * s,
                        lineWidth: 1.6,
                        color: UsageTint.color(for: entry.window.fraction, accent: settings.accentColor)
                    )
                    Text(entry.window.percentText)
                        .font(.system(size: 9 * s, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.55))
                }
                .help("\(entry.label) — \(entry.window.percentText) used")
            }
        }
    }

    private func entries(_ usage: UsageSnapshot) -> [(label: String, window: RateLimitWindow)] {
        [("5-hour limit", usage.fiveHour), ("Weekly limit", usage.sevenDay)]
            .compactMap { label, window in window.map { (label, $0) } }
    }
}

/// What a click on the menu bar item shows: every window, with when it resets.
struct UsagePopoverView: View {
    let usage: UsageSnapshot?
    private let settings = PanelSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let usage {
                let shown = usage.current()
                ForEach(rows(shown), id: \.label) { row in
                    HStack(spacing: 8) {
                        UsageRing(
                            fraction: row.window.fraction,
                            diameter: 14,
                            lineWidth: 2.4,
                            color: UsageTint.color(for: row.window.fraction, accent: settings.accentColor)
                        )
                        VStack(alignment: .leading, spacing: 1) {
                            Text(row.label).font(.system(size: 12, weight: .medium))
                            if let reset = row.window.resetText() {
                                Text(reset).font(.system(size: 10)).foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 16)
                        Text(row.window.percentText)
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    }
                }
                Text(age(of: usage))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            } else {
                Text("No usage reading yet")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(minWidth: 220)
    }

    private func rows(_ usage: UsageSnapshot) -> [(label: String, window: RateLimitWindow)] {
        [
            ("5-hour limit", usage.fiveHour), ("Weekly limit", usage.sevenDay),
            ("Weekly Opus", usage.sevenDayOpus), ("Weekly Sonnet", usage.sevenDaySonnet),
        ].compactMap { label, window in window.map { (label, $0) } }
    }

    private func age(of usage: UsageSnapshot) -> String {
        let seconds = Int(Date().timeIntervalSince(usage.updatedAt))
        switch seconds {
        case ..<90: return "Updated just now"
        case ..<5_400: return "Updated \(max(2, seconds / 60)) min ago"
        case ..<172_800: return "Updated \(seconds / 3_600) h ago"
        default: return "Updated \(seconds / 86_400) days ago"
        }
    }
}


/// The limits as the menu bar item draws them: the panel's rings and figures,
/// in the colours of the menu bar rather than the panel's dark glass.
struct MenuBarUsageView: View {
    let usage: UsageSnapshot
    private let settings = PanelSettings.shared

    var body: some View {
        HStack(spacing: 8) {
            ForEach(entries, id: \.label) { entry in
                HStack(spacing: 3) {
                    UsageRing(
                        fraction: entry.window.fraction,
                        diameter: 11,
                        lineWidth: 2,
                        color: UsageTint.color(for: entry.window.fraction, accent: settings.accentColor)
                    )
                    Text(entry.label)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(entry.window.percentText)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.primary)
                }
            }
        }
        .fixedSize()
    }

    private var entries: [(label: String, window: RateLimitWindow)] {
        [("5h", usage.fiveHour), ("wk", usage.sevenDay)]
            .compactMap { label, window in window.map { (label, $0) } }
    }
}

/// A hosting view that lets every click through to the view under it, so the
/// menu bar button it is drawn on still receives them.
final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
