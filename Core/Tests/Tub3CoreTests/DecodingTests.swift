import Foundation
import Testing
@testable import Tub3Core

/// Decoding is tested against payloads captured from the running box, not hand-written ones.
/// A fixture that drifts from reality is worse than no fixture, so `scripts/refresh-fixtures.sh`
/// re-captures these from a running box.
private func fixture(_ name: String) throws -> Data {
    let url = Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: nil)
    return try Data(contentsOf: #require(url))
}

@Test func decodesAScheduledChannel() throws {
    let now = try JSONDecoder().decode(NowPlaying.self, from: fixture("now-ch6.json"))
    #expect(now.channel == 6)
    #expect(now.isGuide == false)
    #expect(now.now != nil)

    let entry = try #require(now.now)
    #expect(entry.remainingSeconds > 0)

    // The field this app cannot afford to lose. A missing media_index answers HTTP 200 and
    // plays a different cut of the film.
    let plex = try #require(entry.plex)
    #expect(plex.ratingKey.isEmpty == false)
    #expect(plex.mediaIndex >= 0)
    #expect(plex.mediaID.isEmpty == false)
}

@Test func decodesTheGuideChannel() throws {
    let now = try JSONDecoder().decode(NowPlaying.self, from: fixture("now-ch2.json"))
    #expect(now.isGuide)
    // The guide is a channel, not a menu: it carries no media and nothing to resolve.
    #expect(now.now == nil)
}

@Test func decodesTheAmbianceChannel() throws {
    let now = try JSONDecoder().decode(NowPlaying.self, from: fixture("now-ch13.json"))
    #expect(now.channel == 13)
    #expect(now.now != nil)
}

@Test func decodesTheDial() throws {
    let list = try JSONDecoder().decode(ChannelList.self, from: fixture("channels.json"))
    #expect(list.channels.count >= 10)
    #expect(list.channels.contains { $0.isGuide })
    #expect(list.channels.contains { $0.isAmbiance })
}

@Test func titlesLoseThePoolPrefix() {
    // The fallback path: a box old enough to send only the pool stem.
    let entry = NowEntry(contentType: "feature", duration: 100, offsetSeconds: 0,
                         remainingSeconds: 100,
                         title: "movies__Star Wars (1977) WEBDL-1080p",
                         show: nil, episode: nil, plex: nil)
    #expect(entry.displayTitle == "Star Wars (1977) WEBDL-1080p")
}

@Test func theBoxsOwnTitleWinsOverTheFilename() {
    // What the box sends now. The filename is still there and must lose to it — this is the
    // divergence that had the television saying "This Old House" and the app saying
    // "thisoldhouse__This Old House - S08E08 - The Reading House - 8 WEBDL-1080p".
    let entry = NowEntry(contentType: "feature", duration: 100, offsetSeconds: 0,
                         remainingSeconds: 100,
                         title: "thisoldhouse__This Old House - S08E08 - The Reading House - 8 WEBDL-1080p",
                         show: "This Old House", episode: "The Reading House - 8", plex: nil)
    #expect(entry.displayTitle == "This Old House — The Reading House - 8")
}

@Test func aShowWithNoEpisodeTitleDoesNotTrailASeparator() {
    let entry = NowEntry(contentType: "feature", duration: 100, offsetSeconds: 0,
                         remainingSeconds: 100, title: "films__Jaws",
                         show: "Jaws", episode: nil, plex: nil)
    #expect(entry.displayTitle == "Jaws")
}

@Test func aFourFieldPlexRefStillDecodes() throws {
    // A box running an older map writes four fields. Degrade, do not throw.
    let json = #"{"rating_key":"1","kind":"movie","seconds":10}"#.data(using: .utf8)!
    let ref = try JSONDecoder().decode(PlexRef.self, from: json)
    #expect(ref.mediaIndex == 0)
    #expect(ref.partIndex == 0)
    #expect(ref.mediaID == "")
}

/// The box's per-channel error answer, captured from a request for a channel that is not on
/// the dial. It carries `error` and `channel` and nothing else — no station name, because the
/// failure *is* that there is no such channel to name.
///
/// This used to be a decoding failure, which the tuner turned into `.broken`, which nothing
/// retried out of. A fault the box could explain in one sentence therefore bricked the app
/// until it was relaunched, and the slate-and-retry written for exactly this case never ran.
@Test func decodesTheBoxsErrorAnswer() throws {
    let now = try JSONDecoder().decode(NowPlaying.self, from: fixture("now-error.json"))
    #expect(now.channel == 99)
    #expect(now.error?.isEmpty == false)
    // Absent, not required. These defaults are what let the answer through at all.
    #expect(now.station == "")
    #expect(now.serverTime == 0)
    #expect(now.now == nil)
}
