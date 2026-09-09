import Foundation
import Observation

/// What a row is. The box's `ItemKind`, minus the kinds this app has no business having.
public enum MenuKind: Sendable, Equatable {
    /// Pushes another screen.
    case screen
    /// Cycles a fixed list of values — clicker-safe, because there is no text entry here.
    case choice
    case action
    /// Read-only. Never selectable, never focusable, never a Button.
    case info
    /// The way out. Added by `MenuScreen`, never by a builder.
    case back
}

public struct MenuItem: Identifiable, Sendable {
    public let id: String
    public let label: String
    public let kind: MenuKind
    /// Shown right-aligned. Every item shows its current value, because you cannot hover for
    /// a tooltip on a television — `tuner/menu.py`'s fourth rule.
    public let value: String?
    public let help: String
    /// Pushed when `kind == .screen`.
    public let screen: MenuScreen?
    /// Run on select. Returns a line for the status band, or nil.
    public let act: (@MainActor @Sendable () -> String?)?

    public init(id: String, label: String, kind: MenuKind = .action,
                value: String? = nil, help: String = "",
                screen: MenuScreen? = nil,
                act: (@MainActor @Sendable () -> String?)? = nil) {
        self.id = id
        self.label = label
        self.kind = kind
        self.value = value
        self.help = help
        self.screen = screen
        self.act = act
    }

    public var selectable: Bool { kind != .info }
}

public struct MenuScreen: Sendable {
    public let title: String
    public let items: [MenuItem]
    /// Open on the way-out row rather than on the first selectable one.
    ///
    /// For a screen whose only pressable rows are Back and something that takes the
    /// television away from whoever is watching it. "Start on something you can press"
    /// resolves to the wrong row there, and the box charges the same price for POWER.
    public let guarded: Bool

    /// The way out is appended here and nowhere else.
    ///
    /// "Every screen has a way out" has to be a structural guarantee: a submenu added in six
    /// months cannot forget it if a builder never gets the chance to write it. The box's own
    /// reason does not hold here — no Elan clicker has a BACK button, whereas the Siri
    /// Remote always has one and Apple requires it to work — but the effect is kept anyway,
    /// because nothing should depend on a button whose meaning we do not own.
    public init(title: String, guarded: Bool = false,
                exitLabel: String = "Back", exitHelp: String = "",
                items: [MenuItem]) {
        self.title = title
        self.guarded = guarded
        self.items = items + [MenuItem(id: "back", label: exitLabel, kind: .back,
                                       help: exitHelp)]
    }
}

/// Where the cursor is, and how it got there.
@MainActor
@Observable
public final class MenuModel {
    public private(set) var path: [MenuScreen] = []
    public private(set) var cursor: Int = 0
    /// One line under the rows: what the last action said, or the focused row's help.
    public private(set) var status: String = ""

    public var isOpen: Bool { !path.isEmpty }
    public var screen: MenuScreen? { path.last }
    public var atRoot: Bool { path.count == 1 }

    private let root: () -> MenuScreen
    public init(root: @escaping () -> MenuScreen) { self.root = root }

    /// Always from the top, and always on the way out.
    ///
    /// Reopening three levels deep in TELEVISION because that is where you were twenty
    /// minutes ago reads as a fault on a screen with no title bar to explain itself. And
    /// opening on the exit row means the button that opened the menu closes it: a second
    /// press of SELECT is a no-op whatever was on screen before. `Menu.open()`'s rule.
    public func open() {
        let screen = root()
        path = [screen]
        // The exit row, always — not merely when the root happens to be `guarded`. This is
        // the half of the rule that makes SELECT idempotent.
        cursor = screen.items.firstIndex { $0.kind == .back } ?? restingRow(of: screen)
        status = help()
    }

    public func close() {
        path = []
        cursor = 0
        status = ""
    }

    /// The Menu button and the Back row are the same act, so they cannot diverge.
    /// `Menu._leave` line for line.
    public func leave() {
        guard isOpen else { return }
        if path.count > 1 {
            path.removeLast()
            cursor = restingRow(of: path[path.count - 1])
            status = help()
        } else {
            close()
        }
    }

    public func moveUp() { move(-1) }
    public func moveDown() { move(1) }

    /// The focus engine owns movement on tvOS, so it owns the cursor too.
    ///
    /// Two sources of truth for "which row is current" is how a cursor ends up one row away
    /// from the highlight. The engine moves focus, this follows it, and `select(at:)` acts on
    /// the row that was actually pressed rather than on where the model thought it was.
    public func focus(_ index: Int) {
        guard let screen, screen.items.indices.contains(index),
              screen.items[index].selectable else { return }
        cursor = index
        status = help()
    }

    public func select(at index: Int) {
        focus(index)
        select()
    }

    public func select() {
        guard let screen, screen.items.indices.contains(cursor) else { return }
        let item = screen.items[cursor]
        switch item.kind {
        case .back:
            leave()
        case .screen:
            guard let next = item.screen else { return }
            path.append(next)
            cursor = restingRow(of: next)
            status = help()
        case .action, .choice:
            status = item.act?() ?? item.help
        case .info:
            break   // unreachable: the cursor never rests here
        }
    }

    private func help() -> String {
        guard let screen, screen.items.indices.contains(cursor) else { return "" }
        return screen.items[cursor].help
    }

    /// Skips INFO rows, which is what keeps a screen of pure information navigable: on those
    /// the only stop is the way out, which is exactly what the box guarantees.
    private func move(_ step: Int) {
        guard let screen else { return }
        let rows = screen.items
        guard rows.contains(where: \.selectable) else { return }
        var next = cursor
        for _ in 0 ..< rows.count {
            next = (next + step + rows.count) % rows.count
            if rows[next].selectable { break }
        }
        cursor = next
        status = help()
    }

    private func restingRow(of screen: MenuScreen) -> Int {
        if screen.guarded, let back = screen.items.firstIndex(where: { $0.kind == .back }) {
            return back
        }
        return screen.items.firstIndex(where: \.selectable) ?? 0
    }
}
