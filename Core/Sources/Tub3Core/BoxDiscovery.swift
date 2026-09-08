import Foundation
import Network

/// A box someone could tune to.
public struct FoundBox: Identifiable, Equatable, Sendable {
    /// What the box calls itself — "8008TUB3 on boobtube". Shown in a picker.
    public let name: String
    public let url: URL
    public var id: String { url.absoluteString }
}

/// Finding a television on the network, so nobody has to type an address into one.
///
/// The box advertises `_tub3._tcp` from avahi (`packaging/tub3-avahi.service`). A private
/// service type rather than `_http._tcp`, because every printer and NAS on a home network
/// advertises that one.
///
/// Two things about this fail silently and are worth stating where someone will read them:
///
///  - Browsing returns nothing at all unless `NSBonjourServices` in Info.plist lists the
///    service type. No error, no callback, no permission prompt — an empty network.
///  - The resolved endpoint is an IP address, and App Transport Security blocks plain HTTP to
///    an address literal. `NSAllowsLocalNetworking` is the key that permits it, and is
///    narrower than the blanket arbitrary-loads exception: local names and private ranges
///    only.
public enum BoxDiscovery {
    public static let serviceType = "_tub3._tcp"

    /// Browse for boxes, and stop when the network goes quiet or the clock runs out.
    ///
    /// Bonjour has no "that's all of them" — a browse is open-ended by design, because a box
    /// can be switched on a minute from now. So this collects for a short window and returns
    /// what it heard, which is the right shape for a setup screen and the wrong shape for a
    /// long-lived subscription.
    public static func find(timeout: Duration = .seconds(4)) async -> [FoundBox] {
        let browser = NWBrowser(
            for: .bonjour(type: serviceType, domain: nil),
            using: {
                let p = NWParameters.tcp
                p.includePeerToPeer = false
                return p
            }())

        let found = Collected()
        browser.browseResultsChangedHandler = { results, _ in
            Task { await found.note(results) }
        }
        browser.start(queue: .global(qos: .userInitiated))
        try? await Task.sleep(for: timeout)
        browser.cancel()

        var boxes: [FoundBox] = []
        for endpoint in await found.endpoints() {
            if let box = await resolve(endpoint) { boxes.append(box) }
        }
        return boxes.sorted { $0.name < $1.name }
    }

    /// Turn a service endpoint into something URLSession can be handed.
    ///
    /// A browse result names a service; it does not carry an address. Opening a connection is
    /// what resolves it, and `currentPath.remoteEndpoint` is where the answer arrives.
    /// Does something at this address actually behave like a box?
    ///
    /// `/api/tv/channels` is the cheapest endpoint that proves tub3-ness, and its own client
    /// method already exists. Deliberately not `/api/status`, which calls the NAS with a
    /// ten-second timeout and walks the commercials folder.
    ///
    /// Its own short-timeout session, because `.shared` waits a full minute on a dead address
    /// — which on a television is indistinguishable from a frozen app.
    public static func looksLikeABox(_ url: URL, timeout: TimeInterval = 3) async -> Bool {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        let client = BoxClient(base: url, session: URLSession(configuration: config))
        return ((try? await client.channels()) ?? []).isEmpty == false
    }

    static func resolve(_ endpoint: NWEndpoint, timeout: Duration = .seconds(3)) async -> FoundBox? {
        guard case let .service(name, _, _, _) = endpoint else { return nil }
        let connection = NWConnection(to: endpoint, using: .tcp)
        let ready = Ready()
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready, .failed, .cancelled: Task { await ready.signal() }
            default: break
            }
        }
        connection.start(queue: .global(qos: .userInitiated))
        await ready.wait(upTo: timeout)
        defer { connection.cancel() }

        guard case let .hostPort(host, port)? = connection.currentPath?.remoteEndpoint else {
            return nil
        }
        let text = BoxAddress.stripZone("\(host)")
        let bracketed = text.contains(":") ? "[\(text)]" : text
        guard let url = URL(string: "http://\(bracketed):\(port.rawValue)") else { return nil }
        return FoundBox(name: name, url: url)
    }
}

/// Browse results arrive on a queue; this is the one place they are collected.
private actor Collected {
    private var seen: [NWEndpoint] = []
    func note(_ results: Set<NWBrowser.Result>) {
        for result in results where !seen.contains(result.endpoint) {
            seen.append(result.endpoint)
        }
    }
    func endpoints() -> [NWEndpoint] { seen }
}

private actor Ready {
    private var done = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func signal() {
        guard !done else { return }
        done = true
        for w in waiters { w.resume() }
        waiters = []
    }
    func wait(upTo timeout: Duration) async {
        if done { return }
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.park() }
            group.addTask { try? await Task.sleep(for: timeout) }
            await group.next()
            group.cancelAll()
        }
    }
    private func park() async {
        if done { return }
        await withCheckedContinuation { waiters.append($0) }
    }
}
