import Foundation
import Tub3Core

/// The menu's content, built fresh each time it opens.
///
/// Fresh rather than held, because every value on it is a fact about right now — what is on,
/// what the box thinks of itself, how many channels have been seen. A tree built once at
/// launch would be quietly wrong by the evening.
@MainActor
enum MenuTree {

    static func root(tuner: Tuner,
                     health: BoxHealth?,
                     onChangeBox: (() -> Void)?,
                     onStartOn: @escaping (Int?) -> Void) -> MenuScreen {
        MenuScreen(
            title: "SETUP",
            exitLabel: "EXIT TO TV",
            exitHelp: "Close the menu and go back to what's on",
            items: [
                MenuItem(id: "signal", label: "Signal", kind: .screen,
                         value: signalValue(tuner: tuner, health: health),
                         help: "What your television thinks of itself, and where to fix it.",
                         screen: signal(tuner: tuner, health: health)),
                MenuItem(id: "retry", label: "Try again now",
                         help: "Ask the television again, without changing channel.",
                         act: {
                             Task { await tuner.retryNow() }
                             return "Asking again…"
                         }),
                MenuItem(id: "starton", label: "Start on", kind: .screen,
                         value: startOnValue(tuner: tuner),
                         help: "Which channel this Apple TV opens on.",
                         screen: startOn(tuner: tuner, onPick: onStartOn)),
                MenuItem(id: "television", label: "Television", kind: .screen,
                         value: BoxAddress.forDisplay(tuner.address),
                         help: "Which box this Apple TV is watching.",
                         screen: television(tuner: tuner, onChangeBox: onChangeBox)),
            ])
    }

    /// This app's own reachability first, the box's verdict second.
    ///
    /// If this Apple TV cannot reach the box then that is the answer, and nothing the box
    /// might have said about itself matters. Never an empty value column: with no answer yet
    /// it reads `checking…`, and a failed fetch reads `cannot ask it`.
    private static func signalValue(tuner: Tuner, health: BoxHealth?) -> String {
        switch tuner.state {
        case .broken: return "not answering"
        case .standby: return "almost there"
        case .idle: return "checking…"
        default: return health?.shortVerdict ?? "checking…"
        }
    }

    private static func signal(tuner: Tuner, health: BoxHealth?) -> MenuScreen {
        MenuScreen(
            title: "SIGNAL",
            exitHelp: "Open that address on a computer or a phone. "
                    + "Nothing here needs typing.",
            items: [
                MenuItem(id: "app", label: "This app", kind: .info, value: thisApp(tuner)),
                MenuItem(id: "box", label: "Television", kind: .info,
                         value: health?.householdSummary ?? "Cannot ask it"),
                MenuItem(id: "onnow", label: "On now", kind: .info, value: onNow(tuner)),
                // "Seen", not "on the dial": `keepDialFresh` is deliberately additive, so
                // this number never goes down for the life of a session.
                MenuItem(id: "channels", label: "Channels", kind: .info,
                         value: "\(tuner.channels.count) seen"),
                MenuItem(id: "fix", label: "If it needs fixing", kind: .info,
                         value: BoxAddress.forDisplay(tuner.address)),
            ])
    }

    private static func thisApp(_ tuner: Tuner) -> String {
        switch tuner.state {
        case .idle: return "Starting up"
        case .standby: return "Not finished setting up"
        // Not a countdown: the backoff lives in a local inside a detached task and there is
        // no stored next-attempt time. "Still trying" is the honest sentence.
        case .broken: return "Not answering — still trying"
        default: return "Connected"
        }
    }

    private static func onNow(_ tuner: Tuner) -> String {
        guard let channel = tuner.current,
              let station = tuner.channels.first(where: { $0.channel == channel })?.station
        else { return "Nothing yet" }
        let title = tuner.nowEntry?.displayTitle ?? ""
        let show = title.components(separatedBy: " — ").first ?? ""
        return show.isEmpty ? String(format: "CH %02d %@", channel, station)
                            : String(format: "CH %02d %@ — %@", channel, station, show)
    }

    private static func startOnValue(tuner: Tuner) -> String {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: Tuner.startOnKey) != nil else { return "Last watched" }
        let wanted = defaults.integer(forKey: Tuner.startOnKey)
        guard let ch = tuner.channels.first(where: { $0.channel == wanted }) else {
            return "Last watched"
        }
        return String(format: "%02d %@", ch.channel, ch.station)
    }

    private static func startOn(tuner: Tuner,
                                onPick: @escaping (Int?) -> Void) -> MenuScreen {
        let defaults = UserDefaults.standard
        let chosen: Int? = defaults.object(forKey: Tuner.startOnKey) != nil
            ? defaults.integer(forKey: Tuner.startOnKey) : nil
        var rows: [MenuItem] = [
            MenuItem(id: "last", label: "Last watched",
                     value: chosen == nil ? "selected" : nil,
                     help: "Open on whatever was on when you last switched off.",
                     act: { onPick(nil); return "Will open on the last channel watched." }),
        ]
        // From the dial as it is now. The box's own hardcoded "Channel 1 / Channel 3" cannot
        // port to a set whose lineup is whatever the television says it is today.
        rows += tuner.channels.map { channel in
            MenuItem(id: "ch\(channel.channel)",
                     label: String(format: "%02d  %@", channel.channel, channel.station),
                     value: chosen == channel.channel ? "selected" : nil,
                     help: "Open on this channel every time.",
                     act: {
                         onPick(channel.channel)
                         return "Will open on \(channel.station)."
                     })
        }
        return MenuScreen(title: "START ON", items: rows)
    }

    private static func television(tuner: Tuner,
                                   onChangeBox: (() -> Void)?) -> MenuScreen {
        var rows: [MenuItem] = [
            MenuItem(id: "address", label: "Address", kind: .info,
                     value: BoxAddress.forDisplay(tuner.address)),
            MenuItem(id: "version", label: "This app", kind: .info, value: appVersion),
        ]
        if let onChangeBox {
            rows.append(MenuItem(id: "change", label: "Change television",
                                 help: "Point this Apple TV at a different box. Nothing "
                                     + "changes until another one answers, and the set "
                                     + "downstairs keeps playing.",
                                 act: { onChangeBox(); return nil }))
        }
        // Guarded: its only pressable rows are Back and one that takes this television away
        // from whoever is holding the remote. The box charges the same price for POWER.
        return MenuScreen(title: "TELEVISION", guarded: true, items: rows)
    }

    static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }
}
