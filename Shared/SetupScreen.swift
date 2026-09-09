import SwiftUI
import Tub3Core

/// Finding a television, on a television.
///
/// The box's first rule applies here more than anywhere: a picture first, always. There is no
/// spinner — the mark goes up immediately and the screen fills in underneath it, because a
/// blank screen with a wheel on it is what a broken appliance looks like and this is the very
/// first thing a stranger sees.
struct SetupScreen: View {
    /// Called with a box that has already answered.
    let onChosen: (URL) -> Void

    @State private var found: [FoundBox] = []
    @State private var searching = true
    @State private var typing = false
    @State private var typed = ""
    @State private var problem: String?

    /// Where the remote is pointing.
    ///
    /// Set by hand rather than left to the focus engine. tvOS resolves initial focus when a
    /// screen appears, and at that moment this one has no buttons on it at all — the results
    /// arrive a second or two later from the network. So the engine focused nothing, and the
    /// screen sat there with a box on it that the select button could not press.
    private enum Field: Hashable { case box(String), manual, again, address }
    @FocusState private var focus: Field?

    var body: some View {
        ZStack {
            Theme.ink.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                Text("8008TUB3")
                    .font(Theme.furniture(88, .bold))
                    .foregroundStyle(Theme.gold)
                    // Belt and braces over the scale above: the one string on this screen
                    // that must never be clipped is the one that says what the app is.
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                // The mark is 8008TUB3; the name is BoobTube. `brand.py` on the box carries
                // both for this reason — the mark is leetspeak and is unreadable to anyone
                // who does not already know what it spells, which on a first-run screen is
                // everyone. Somebody opening this on a phone saw a logo and no name and
                // could not tell what the app was.
                Text("BoobTube")
                    .font(Theme.furniture(30))
                    .foregroundStyle(Theme.purple)
                    .padding(.top, 2)
                Text(searching ? "Looking for your television…"
                               : found.isEmpty ? "No television found on this network"
                                               : "Found \(found.count == 1 ? "a television" : "\(found.count) televisions")")
                    .font(Theme.furniture(34))
                    .foregroundStyle(Theme.dim)
                    .padding(.top, 8)

                VStack(alignment: .leading, spacing: 14) {
                    ForEach(found) { box in
                        Button { choose(box.url) } label: {
                            HStack(spacing: 18) {
                                Text(box.name)
                                    .font(Theme.furniture(38, .semibold))
                                    .foregroundStyle(Theme.phosphor)
                                Spacer(minLength: 0)
                                Text(box.url.host ?? "")
                                    .font(Theme.furniture(28))
                                    .foregroundStyle(Theme.dim)
                            }
                            .padding(.vertical, 14).padding(.horizontal, 24)
                            .frame(maxWidth: .infinity)
                        }
                        .accessibilityIdentifier("tub3.setup.box")
                        .focused($focus, equals: .box(box.id))
                    }

                    if !searching {
                        Button { typing = true; focus = .address } label: {
                            Text(found.isEmpty ? "Enter the address yourself"
                                               : "It is not one of these")
                                .font(Theme.furniture(30))
                                .foregroundStyle(Theme.dim)
                                .padding(.vertical, 12).padding(.horizontal, 24)
                        }
                        .accessibilityIdentifier("tub3.setup.manual")
                        .focused($focus, equals: .manual)
                        Button { Task { await search() } } label: {
                            Text("Look again")
                                .font(Theme.furniture(30))
                                .foregroundStyle(Theme.dim)
                                .padding(.vertical, 12).padding(.horizontal, 24)
                        }
                        .focused($focus, equals: .again)
                    }
                }
                .padding(.top, 40)

                if typing {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Its address, from the settings page on a computer")
                            .font(Theme.furniture(26))
                            .foregroundStyle(Theme.dim)
                        TextField("10.0.1.116:8008", text: $typed)
                            .font(Theme.furniture(34))
                            .accessibilityIdentifier("tub3.setup.address")
                            .focused($focus, equals: .address)
                            .onSubmit {
                                guard let url = BoxAddress.parse(typed) else {
                                    problem = "That is not an address."
                                    return
                                }
                                choose(url)
                            }
                    }
                    .padding(.top, 30)
                }

                if let problem {
                    Text(problem)
                        .font(Theme.furniture(28))
                        .foregroundStyle(Theme.dim)
                        .padding(.top, 24)
                }

                Spacer(minLength: 0)
                // The one genuinely useful sentence for someone whose network does not carry
                // multicast — a guest VLAN, or two subnets. Nothing else on this screen can
                // tell them that, and the app cannot detect it.
                Text("A television appears here by itself. If yours does not, its address is "
                     + "on the settings page at port 8008.")
                    .font(Theme.furniture(24))
                    .foregroundStyle(Theme.dim)
            }
            .padding(Theme.scale * 80)
        }
        .task { await search() }
    }

    private func search() async {
        Diag.log("setup: looking for a box")
        searching = true
        problem = nil
        found = await BoxDiscovery.find()
        searching = false
        // The first television found, or the way to type one in when there were none. Either
        // way something on this screen is pressable the moment it finishes looking.
        focus = found.first.map { Field.box($0.id) } ?? .manual
    }

    private func choose(_ url: URL) {
        Task {
            problem = nil
            // Ask before committing. A box that advertises and does not answer is a worse
            // outcome than one that was never found, because it is remembered.
            guard await BoxDiscovery.looksLikeABox(url) else {
                Diag.log("setup: \(url.absoluteString) did not answer")
                problem = "Nothing answered at \(url.host ?? url.absoluteString)."
                return
            }
            Diag.log("setup: chose \(url.absoluteString)")
            onChosen(url)
        }
    }
}
