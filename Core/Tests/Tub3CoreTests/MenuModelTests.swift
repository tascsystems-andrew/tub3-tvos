import Testing
@testable import Tub3Core

/// The four structural guarantees, each of which the box enforces and each of which is the
/// kind of thing that quietly stops being true when a screen is added later.
@MainActor
struct MenuModelTests {

    private func tree() -> MenuScreen {
        MenuScreen(title: "SETUP", exitLabel: "EXIT TO TV", items: [
            MenuItem(id: "signal", label: "Signal", kind: .screen, value: "all well",
                     screen: MenuScreen(title: "SIGNAL", items: [
                        MenuItem(id: "app", label: "This app", kind: .info, value: "Connected"),
                        MenuItem(id: "tv", label: "Television", kind: .info, value: "All well"),
                     ])),
            MenuItem(id: "retry", label: "Try again now", act: { "Asking again…" }),
            MenuItem(id: "tv", label: "Television", kind: .screen, value: "10.0.1.116:8008",
                     screen: MenuScreen(title: "TELEVISION", guarded: true, items: [
                        MenuItem(id: "addr", label: "Address", kind: .info, value: "10.0.1.116"),
                        MenuItem(id: "change", label: "Change television"),
                     ])),
        ])
    }

    @Test func everyScreenHasExactlyOneWayOut() {
        func check(_ s: MenuScreen) {
            #expect(s.items.filter { $0.kind == .back }.count == 1)
            for item in s.items { if let child = item.screen { check(child) } }
        }
        check(tree())
    }

    @Test func openingRestsOnTheWayOut() {
        let m = MenuModel(root: tree)
        m.open()
        // So the button that opened the menu closes it, and a second SELECT is a no-op
        // whatever was on screen before.
        #expect(m.screen?.items[m.cursor].kind == .back)
        m.select()
        #expect(!m.isOpen)
    }

    @Test func aGuardedScreenOpensOnItsBackRow() {
        let m = MenuModel(root: tree)
        m.open()
        m.moveDown()                       // wraps to the first selectable row: Signal
        while m.screen?.items[m.cursor].id != "tv" { m.moveDown() }
        m.select()
        #expect(m.screen?.title == "TELEVISION")
        // Not "Change television", which is one press from taking the television away.
        #expect(m.screen?.items[m.cursor].kind == .back)
    }

    @Test func theCursorNeverRestsOnAnInfoRow() {
        let m = MenuModel(root: tree)
        m.open()
        while m.screen?.items[m.cursor].id != "signal" { m.moveDown() }
        m.select()
        #expect(m.screen?.title == "SIGNAL")
        // Every row on that screen is INFO, so the only stop is the way out.
        for _ in 0 ..< 8 {
            #expect(m.screen?.items[m.cursor].kind != .info)
            m.moveDown()
        }
    }

    @Test func leavingPopsAndThenCloses() {
        let m = MenuModel(root: tree)
        m.open()
        while m.screen?.items[m.cursor].id != "signal" { m.moveDown() }
        m.select()
        #expect(m.path.count == 2)
        m.leave()                          // pops
        #expect(m.path.count == 1)
        #expect(m.isOpen)
        m.leave()                          // closes
        #expect(!m.isOpen)
    }

    @Test func theMenuButtonAndTheBackRowAreTheSameAct() {
        let byButton = MenuModel(root: tree)
        byButton.open()
        while byButton.screen?.items[byButton.cursor].id != "signal" { byButton.moveDown() }
        byButton.select()
        byButton.leave()

        let byRow = MenuModel(root: tree)
        byRow.open()
        while byRow.screen?.items[byRow.cursor].id != "signal" { byRow.moveDown() }
        byRow.select()
        while byRow.screen?.items[byRow.cursor].kind != .back { byRow.moveDown() }
        byRow.select()

        #expect(byButton.path.count == byRow.path.count)
        #expect(byButton.screen?.title == byRow.screen?.title)
    }
}
