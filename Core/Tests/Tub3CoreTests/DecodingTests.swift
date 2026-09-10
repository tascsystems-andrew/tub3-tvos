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

@Test func aMidBreakChannelStillNamesTheProgramme() throws {
    // Captured from channel 3 during an actual ad break. `now` is the advert — and the
    // advert's own "show" is the caption the viewer complained about, verbatim.
    let now = try JSONDecoder().decode(NowPlaying.self, from: fixture("now-break-ch3.json"))
    let entry = try #require(now.now)
    #expect(entry.contentType == "commercial")
    #expect(entry.displayTitle.hasPrefix("60+_MINUTES_OF_VINTAGE"))

    let feature = try #require(now.feature)
    #expect(feature.inBreak)
    #expect(feature.displayTitle == "The Office (US) — The Office S06E01 Gossip")
    // The programme's remainder, not the advert's 25 seconds: the breaks still to come
    // inside it are counted, so the number falls steadily instead of jumping at each cut.
    #expect(feature.remainingSeconds > entry.remainingSeconds)
    #expect(feature.remainingSeconds == 385.95)
}

@Test func aProgrammesOwnPayloadCarriesAFeatureThatMerelyAgrees() throws {
    // Not in a break: `feature` restates `now`, and nothing downstream should diverge.
    let now = try JSONDecoder().decode(NowPlaying.self, from: fixture("now-ch6.json"))
    if let feature = now.feature {
        #expect(feature.inBreak == false)
    }
}

@Test func anOlderBoxSendsNoFeatureAtAll() throws {
    // The field is new. A box that predates it must decode, not throw — that failure mode
    // is the one that turns into `.broken`, which nothing retries out of.
    let json = #"{"channel":6,"station":"X","server_time":1.0,"now":null}"#.data(using: .utf8)!
    let now = try JSONDecoder().decode(NowPlaying.self, from: json)
    #expect(now.feature == nil)
}

@Test func aFeatureTheBoxCouldNotNameDoesNotDrawABlankCaption() throws {
    // Empty, not " — ": the caller reads emptiness as its cue to fall back to the entry.
    let json = #"{"show":null,"episode":null,"content_type":"feature","remaining_seconds":12.0,"in_break":true}"#
        .data(using: .utf8)!
    let feature = try JSONDecoder().decode(Feature.self, from: json)
    #expect(feature.displayTitle.isEmpty)
    #expect(feature.inBreak)
}

@Test func theCaptionKeepsTheProgrammeThroughTheBreak() throws {
    // The defect, end to end, on the payload that produced it: the bug used to draw
    // `now.displayTitle`, so a viewer mid-break read the name of the ad reel.
    let now = try JSONDecoder().decode(NowPlaying.self, from: fixture("now-break-ch3.json"))
    #expect(Feature.caption(now.feature, playing: now.now) == "The Office (US) — The Office S06E01 Gossip")
    #expect(Feature.remaining(now.feature, playing: now.now) == 385.95)
}

@Test func withNoFeatureTheCaptionIsStillTheEntry() {
    // An older box, and the state after a local step past a broken file. Neither may go
    // blank: a caption is the only thing on screen that says what is on.
    let entry = NowEntry(contentType: "feature", duration: 100, offsetSeconds: 0,
                         remainingSeconds: 60, title: "films__Jaws",
                         show: "Jaws", episode: nil, plex: nil)
    #expect(Feature.caption(nil, playing: entry) == "Jaws")
    #expect(Feature.remaining(nil, playing: entry) == 60)
    #expect(Feature.caption(nil, playing: nil).isEmpty)
    #expect(Feature.remaining(nil, playing: nil) == 0)
}

@Test func anUnnamedFeatureDoesNotBlankTheCaption() {
    // `feature` present but nameless — the box knows a programme is running and cannot say
    // which. Falling back beats drawing an empty bug.
    let entry = NowEntry(contentType: "commercial", duration: 30, offsetSeconds: 0,
                         remainingSeconds: 25, title: "kids__ADS", show: "ADS",
                         episode: nil, plex: nil)
    let blank = Feature(show: nil, episode: nil, contentType: "feature",
                        remainingSeconds: 400, inBreak: true)
    #expect(Feature.caption(blank, playing: entry) == "ADS")
    // The clock is a separate question from the name, and this half the box does know.
    #expect(Feature.remaining(blank, playing: entry) == 400)
}

@Test func outsideABreakTheEntrysOwnClockWins() {
    // `feature` merely restates `now` here, but the entry's remainder is re-read at every
    // boundary and the feature's was computed once. Prefer the fresher of two equals.
    let entry = NowEntry(contentType: "feature", duration: 100, offsetSeconds: 40,
                         remainingSeconds: 60, title: "x", show: "Grand Designs",
                         episode: "Oxford, 1999", plex: nil)
    let agreeing = Feature(show: "Grand Designs", episode: "Oxford, 1999",
                           contentType: "feature", remainingSeconds: 99, inBreak: false)
    #expect(Feature.caption(agreeing, playing: entry) == "Grand Designs — Oxford, 1999")
    #expect(Feature.remaining(agreeing, playing: entry) == 60)
}

@Test func steppingBetweenAdvertsKeepsTheProgramme() throws {
    // Channel 15 did exactly this on 2026-09-09: an .mkv AVFoundation would not open
    // (-11828, though an HTTP probe of the same URL returned 206), so the app stepped to the
    // next entry — a Cadbury's advert. Mid-break that step changes nothing about what the
    // viewer sat down to watch, and dropping the box's answer would have put the advert's
    // name back on the bug for the rest of the break.
    let broken = NowEntry(contentType: "commercial", duration: 30, offsetSeconds: 0,
                          remainingSeconds: 30, title: "kids__ADS", show: "ADS",
                          episode: nil, plex: nil)
    let next = NowEntry(contentType: "commercial", duration: 30, offsetSeconds: 0,
                        remainingSeconds: 30, title: "kids__Cadbury_s_Gorilla",
                        show: "Cadbury_s_Gorilla", episode: nil, plex: nil)
    let programme = Feature(show: "Grand Designs", episode: "Oxford, 1999",
                            contentType: "feature", remainingSeconds: 400, inBreak: true)

    let carried = programme.skipping(broken.remainingSeconds)
    #expect(Feature.caption(carried, playing: next) == "Grand Designs — Oxford, 1999")
    // The 30 seconds of advert that never played come off the clock; a bug counting down
    // from 400 would be counting from a number that was true before the skip.
    #expect(carried.remainingSeconds == 370)
    #expect(carried.inBreak)
}

@Test func skippingNeverGoesPastZeroOrBackwards() {
    let programme = Feature(show: "X", episode: nil, contentType: "feature",
                            remainingSeconds: 20, inBreak: true)
    #expect(programme.skipping(50).remainingSeconds == 0)
    // A negative remainder on the entry is nonsense the box should never send; treat it as
    // nothing skipped rather than as time added.
    #expect(programme.skipping(-10).remainingSeconds == 20)
}
