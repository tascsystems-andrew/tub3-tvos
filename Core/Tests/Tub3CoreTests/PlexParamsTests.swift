import Foundation
import Testing
@testable import Tub3Core

private func query(_ url: URL) -> [String: String] {
    let c = URLComponents(url: url, resolvingAgainstBaseURL: false)!
    return Dictionary(uniqueKeysWithValues: (c.queryItems ?? []).map { ($0.name, $0.value ?? "") })
}

@Test func theWireCarriesTheIdentityInTheQueryNotTheHeaders() {
    let p = PlexParams(ratingKey: "1131", mediaIndex: 1, partIndex: 0, offset: 773.36,
                       session: "tub3-abc", clientID: "client-1")
    let q = query(p.startURL(base: URL(string: "http://10.0.1.12:32400")!))
    #expect(q["X-Plex-Platform"] == "tvOS")
    #expect(q["X-Plex-Client-Identifier"] == "client-1")
    #expect(q["session"] == "tub3-abc")
    #expect(q["path"] == "/library/metadata/1131")
    // The two that silently play the wrong thing when wrong.
    #expect(q["mediaIndex"] == "1")
    #expect(q["partIndex"] == "0")
    // Plex wants whole seconds; a fractional offset is rejected as malformed.
    #expect(q["offset"] == "773")
}

@Test func decisionAndStartAgreeOnEverything() {
    let p = PlexParams(ratingKey: "9", mediaIndex: 0, partIndex: 0, offset: 0,
                       session: "s", clientID: "c")
    let base = URL(string: "http://10.0.1.12:32400")!
    #expect(query(p.decisionURL(base: base)) == query(p.startURL(base: base)))
    #expect(p.decisionURL(base: base).path.hasSuffix("/decision"))
    #expect(p.startURL(base: base).path.hasSuffix("/start.m3u8"))
}

@Test func everySessionIsDistinct() {
    #expect(PlexParams.newSession() != PlexParams.newSession())
    #expect(PlexParams.newSession().hasPrefix("tub3-"))
}
