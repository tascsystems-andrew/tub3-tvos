import SwiftUI
import Tub3Core

/// The on-screen menu: a 90s BIOS, drawn over the picture.
///
/// Geometry is `tuner/menu.py`'s `render_ass`, verbatim. That transfers because tvOS lays out
/// in a 1920×1080 point space on every Apple TV — the 4K renders the same points at 2× — so
/// the two heads can be the same size on the same television rather than merely similar.
struct MenuOverlay: View {
    @Bindable var menu: MenuModel
    /// What is on behind the panel, for the strip underneath.
    let nowLine: String?

    @FocusState private var focused: Int?

    private let panelW: CGFloat = 1620
    private let panelH: CGFloat = 840
    private let headerH: CGFloat = 78

    var body: some View {
        ZStack {
            // Not black: the box draws its menu over live video and so does this. What is on
            // stays on, which is the whole reason the now-strip below does not fade either.
            Color.black.opacity(0.35).ignoresSafeArea()

            VStack(spacing: 0) {
                header
                rows
                Spacer(minLength: 0)
                footer
            }
            .frame(width: panelW, height: panelH)
            .background(Theme.ink.opacity(0.92))

            if let nowLine {
                VStack {
                    Spacer()
                    Text(nowLine)
                        .font(.system(size: 30, design: .monospaced))
                        .foregroundStyle(Theme.phosphor)
                        .hardShadow()
                        .accessibilityIdentifier("tub3.menu.now")
                        .padding(.bottom, 70)
                }
            }
        }
        // Without this the panel is centred in the safe rect rather than at (960, 540), and
        // the two heads sit an inset apart that nobody will ever think to measure.
        .ignoresSafeArea()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tub3.menu")
        #if os(tvOS)
        // One method for the Menu button and the Back row, so the two cannot diverge.
        .onExitCommand { menu.leave() }
        #endif
        .onAppear { focused = menu.cursor }
        // On every path change, not only on appear. The rows are rebuilt when a screen is
        // pushed or popped, and a focus state left pointing at the old row's index is how a
        // screen ends up swallowing the first press after it opens.
        .onChange(of: menu.path.count) { _, _ in focused = menu.cursor }
        .onChange(of: focused) { _, new in if let new { menu.focus(new) } }
    }

    private var header: some View {
        // Solid, against what menu.py's constants literally say. In ASS, alpha 00 is opaque
        // and FF transparent, so `&HCC&` reads as 20% — but the text on this band is
        // ink-coloured, and ink text only makes sense on a bright band. The intent is
        // unmistakable and the constant is inverted.
        HStack {
            Text("8008TUB3   \(menu.screen?.title ?? "")")
                .font(.system(size: 44, weight: .bold, design: .monospaced))
            Spacer()
            Text(MenuTree.appVersion)
                .font(.system(size: 32, design: .monospaced))
        }
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 32)
        .frame(height: headerH)
        .frame(maxWidth: .infinity)
        .background(Theme.phosphor)
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array((menu.screen?.items ?? []).enumerated()), id: \.element.id) { i, item in
                if item.kind == .info {
                    // Never a Button, never focusable. A screen of pure information leaves
                    // the way out as its only stop, which is what the box guarantees.
                    row(item, selected: false)
                } else {
                    Button { menu.select(at: i) } label: { row(item, selected: focused == i) }
                        // A style of our own, because neither `.plain` nor
                        // `.focusEffectDisabled()` removes what tvOS draws around a focused
                        // button: a white rounded card that also *scales* the row, which
                        // drew the exit row straight over the one above it. `PlainButtonStyle`
                        // paints that itself, so it has to be replaced rather than switched
                        // off. The cursor bar is the focus indicator here, the way a
                        // character generator did it.
                        .buttonStyle(BareStyle())
                        .focused($focused, equals: i)
                        .accessibilityIdentifier("tub3.menu.row.\(item.id)")
                }
            }
        }
        .padding(.top, 34)
        // tvOS glides focus; this cursor snaps, the way a character generator did.
        .animation(nil, value: focused)
    }

    private func row(_ item: MenuItem, selected: Bool) -> some View {
        HStack(spacing: 0) {
            Text(item.label)
                .font(.system(size: 38, weight: selected ? .bold : .regular,
                              design: .monospaced))
            Spacer(minLength: 24)
            if let value = item.value {
                Text(value).font(.system(size: 38, design: .monospaced))
            }
            if item.kind == .screen {
                Text(" ›").font(.system(size: 38, design: .monospaced))
            }
        }
        .foregroundStyle(selected ? Theme.ink
                                  : (item.kind == .info ? Theme.dim : Theme.phosphor))
        .padding(.horizontal, 40)
        .frame(height: 52)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selected ? Theme.phosphor : Color.clear)
        .padding(.horizontal, 18)
        .padding(.top, item.kind == .back ? 18 : 0)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Rectangle().fill(Theme.phosphor).frame(height: 4)
            Text(menu.status)
                .font(.system(size: 28, design: .monospaced))
                .foregroundStyle(Theme.dim)
                .lineLimit(2)
            Text("▲▼ MOVE      ● SELECT      ‹ BACK")
                .font(.system(size: 30, design: .monospaced))
                .foregroundStyle(Theme.phosphor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 32)
        .padding(.bottom, 36)
    }
}

/// Just the label. No focus card, no scale, no press dimming — the row draws its own state.
private struct BareStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label }
}

private extension View {
    /// `\shad3` is an offset copy, not a Gaussian. `.shadow(radius:)` blurs, which is the
    /// single detail here most likely to be got wrong and the one that would make this read
    /// as a modern overlay rather than as a character generator.
    func hardShadow() -> some View {
        shadow(color: .black, radius: 0, x: 3, y: 3)
    }
}
