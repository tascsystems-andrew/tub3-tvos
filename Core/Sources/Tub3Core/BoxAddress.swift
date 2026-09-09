import Foundation

/// Turning what somebody typed into something that can be fetched.
///
/// Never `URL(string:)` on its own. The most likely thing a person types into a setup screen
/// is an address and a port — `10.0.1.116:8008` — and `URL(string:)` accepts that, parses the
/// host as `10.0.1.116` and the *scheme* as nothing, so the fetch fails later and somewhere
/// else. The next most likely thing is a bare hostname, which is not a URL at all.
///
/// Lives in Core so `swift test` covers it, which is what Core building for macOS is for.
public enum BoxAddress {
    public static let defaultPort = 8008

    /// - Returns: an http URL, or nil when there is nothing usable in the string.
    public static func parse(_ typed: String) -> URL? {
        var text = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        // A scheme is what makes it a URL rather than a hostname, and nobody types one.
        if !text.contains("://") { text = "http://" + text }
        guard var parts = URLComponents(string: text) else { return nil }
        guard let host = parts.host, !host.isEmpty else { return nil }
        // Only http. The box serves plain HTTP on a home network, and accepting https here
        // would produce a URL that fails at connect time with a certificate error nobody
        // could act on.
        guard parts.scheme?.lowercased() == "http" else { return nil }
        parts.scheme = "http"
        if parts.port == nil { parts.port = defaultPort }
        parts.path = ""
        parts.query = nil
        parts.fragment = nil
        return parts.url
    }

    /// Strip an interface zone from a resolved address so it can go in a URL.
    ///
    /// Bonjour resolves to `10.0.1.116%en0`, and `URL(string:)` returns **nil** for that —
    /// `%en` is an invalid percent-escape. The zone is meaningful to the kernel and
    /// meaningless to URLSession. IPv6 is worse: the bracketed form parses and then silently
    /// becomes `%25en0`.
    /// An address as it should be read off a screen and typed into another device.
    ///
    /// Without the scheme, without a trailing slash. Nobody types `http://`, and it is the
    /// noisiest part of the one line somebody has to copy by hand. Lifted out of
    /// `StandbyCard`, which had it privately — two screens showing the same address in two
    /// shapes is the kind of difference that makes people doubt both.
    public static func forDisplay(_ address: String) -> String {
        var s = address
        for prefix in ["http://", "https://"] where s.hasPrefix(prefix) {
            s.removeFirst(prefix.count)
        }
        if s.hasSuffix("/") { s.removeLast() }
        return s
    }

    public static func stripZone(_ host: String) -> String {
        guard let percent = host.firstIndex(of: "%") else { return host }
        return String(host[..<percent])
    }
}
