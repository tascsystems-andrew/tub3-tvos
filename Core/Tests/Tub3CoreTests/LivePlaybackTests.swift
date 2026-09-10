import AVFoundation
import Foundation
import Testing
@testable import Tub3Core

/// Opt-in, because it talks to the real box and starts a real transcode on the real Plex
/// server. Run with:  TUB3_LIVE=1 swift test --package-path Core
///
/// It exists because three of this project's nastiest failures are invisible to a unit test
/// and silent at runtime: a wrong `mediaIndex` plays a different film with no error, HEVC
/// passthrough yields audio and a black screen with no error, and a join offset that Plex
/// ignores starts the film from the beginning with no error. All three need a real decode.
private let live = ProcessInfo.processInfo.environment["TUB3_LIVE"] == "1"

private func clients() async throws -> (BoxClient, PlexClient, URL) {
    let box = BoxClient(base: LiveTarget.box)
    let plexBase = try #require(try await box.plexBase())
    return (box, PlexClient(base: plexBase, clientID: "tub3-test-0001"), plexBase)
}

@Test(.enabled(if: live)) func playsWhatIsOnAScheduledChannel() async throws {
    let (box, plex, plexBase) = try await clients()
    let state = try await box.now(channel: 6)
    let entry = try #require(state.now, "channel 6 is off air")
    let ref = try #require(entry.plex, "the box could not identify this file in Plex")

    let resolver = StreamResolver(plex: plex, clientID: "tub3-test-0001")
    let item = try await resolver.resolve(entry, base: plexBase)
    print("  resolving  \(entry.displayTitle)")
    print("  rating key \(ref.ratingKey) media \(ref.mediaIndex) part \(ref.partIndex)")
    print("  route      \(item.session == nil ? "DIRECT" : "HLS \(item.session!)")")
    print("  joining at \(Int(item.joinAt))s, entitled to \(Int(item.playFor))s")

    let asset = AVURLAsset(url: item.url)
    let playerItem = AVPlayerItem(asset: asset)
    let player = AVPlayer(playerItem: playerItem)
    playerItem.forwardPlaybackEndTime = CMTime(seconds: item.stopAt, preferredTimescale: 600)
    player.play()

    var waited = 0.0
    while playerItem.status == .unknown, waited < 20 {
        try await Task.sleep(nanoseconds: 100_000_000); waited += 0.1
    }
    #expect(playerItem.status == .readyToPlay,
            "player failed: \(playerItem.error?.localizedDescription ?? "unknown")")

    // Let it actually decode rather than merely declare itself ready.
    try await Task.sleep(nanoseconds: 2_500_000_000)

    // The trap that costs a day: Plex reports success, AVPlayer reports readyToPlay, the
    // audio plays, and there is no video track at all.
    //
    // Asked via `AVURLAsset.tracks` this check silently passes nothing — an HLS asset
    // exposes no tracks at all, so that call returns empty for a perfectly good stream and
    // the assertion would fail for every channel on the dial. The tracks that exist are the
    // player item's, and they appear only once it is actually decoding.
    let video = playerItem.tracks.filter { $0.assetTrack?.mediaType == .video }
    let audio = playerItem.tracks.filter { $0.assetTrack?.mediaType == .audio }
    print("  tracks     \(video.count) video, \(audio.count) audio")
    #expect(video.isEmpty == false, "AUDIO ONLY — no video track")
    let played = playerItem.currentTime().seconds
    print("  playhead   \(String(format: "%.1f", played))s (asked for \(Int(item.joinAt))s)")
    #expect(player.rate > 0, "player is not advancing")

    // Joined where we asked, or close enough that a segment boundary explains it.
    if item.joinAt > 0 {
        #expect(played >= item.joinAt - 12, "joined far BEFORE the offset — EXT-X-START ignored?")
    }

    player.pause()
    if let session = item.session { await plex.stop(session: session) }
}

@Test(.enabled(if: live)) func everyChannelResolvesOrSaysWhyNot() async throws {
    let (box, plex, plexBase) = try await clients()
    let resolver = StreamResolver(plex: plex, clientID: "tub3-test-0001")

    for channel in try await box.channels() {
        let state = try await box.now(channel: channel.channel)
        if state.isGuide { print("  ch\(channel.channel) \(channel.station): guide"); continue }
        guard let entry = state.now else {
            print("  ch\(channel.channel) \(channel.station): off air"); continue
        }
        guard entry.plex != nil else {
            print("  ch\(channel.channel) \(channel.station): NOT IN PLEX — \(entry.displayTitle)")
            continue
        }
        let item = try await resolver.resolve(entry, base: plexBase)
        print("  ch\(channel.channel) \(channel.station): \(item.session == nil ? "direct" : "hls") "
              + "join \(Int(item.joinAt))s  \(item.title.prefix(38))")
        // Resolving an HLS route starts a transcoder; give it straight back.
        if let session = item.session { await plex.stop(session: session) }
    }
}

@Test(.enabled(if: live)) func theAmbianceChannelPlaysWhereTheClockSays() async throws {
    let (box, plex, plexBase) = try await clients()
    let state = try await box.now(channel: 13)
    let entry = try #require(state.now, "ambiance is off air")

    let resolver = StreamResolver(plex: plex, clientID: "tub3-test-0001")
    let item = try await resolver.resolve(entry, base: plexBase)
    print("  ambiance   \(item.title)")
    print("  route      \(item.session == nil ? "DIRECT" : "HLS")")
    print("  joining at \(Int(item.joinAt))s of \(Int(entry.duration))s")

    let playerItem = AVPlayerItem(url: item.url)
    let player = AVPlayer(playerItem: playerItem)
    player.play()

    var waited = 0.0
    while playerItem.status == .unknown, waited < 30 {
        try await Task.sleep(nanoseconds: 100_000_000); waited += 0.1
    }
    #expect(playerItem.status == .readyToPlay,
            "ambiance failed to load: \(playerItem.error?.localizedDescription ?? "unknown")")

    // The seek that the player engine does, and the one that was previously issued too early.
    await playerItem.seek(to: CMTime(seconds: item.joinAt, preferredTimescale: 600),
                          toleranceBefore: .zero, toleranceAfter: .zero)
    try await Task.sleep(nanoseconds: 2_500_000_000)

    let at = playerItem.currentTime().seconds
    print("  playhead   \(String(format: "%.1f", at))s")
    #expect(player.rate > 0, "ambiance is not advancing")
    #expect(abs(at - item.joinAt) < 60,
            "ambiance is playing at \(Int(at))s, not the \(Int(item.joinAt))s the clock says")
    player.pause()
    if let s = item.session { await plex.stop(session: s) }
}

@Test(.enabled(if: live)) func theBoundaryFiresSoTheChannelCanAdvance() async throws {
    let (box, plex, plexBase) = try await clients()
    let state = try await box.now(channel: 6)
    let entry = try #require(state.now)

    let resolver = StreamResolver(plex: plex, clientID: "tub3-test-0001")
    let real = try await resolver.resolve(entry, base: plexBase)

    // Same item, but entitled to only a few seconds — this is exactly what the engine does
    // at every ad break, just compressed so a test can watch it happen.
    let clipped = PlayableItem(url: real.url, joinAt: real.joinAt, playFor: 6,
                               session: real.session, title: real.title,
                               contentType: real.contentType)

    let engine = await PlayerEngine()
    await engine.attach(plex: plex)

    let fired = Fired()
    // `continued` is ignored here: with nothing queued behind it there is nothing for the
    // queue to carry over, and what this probe is checking is that the cut fires at all.
    await MainActor.run { engine.onBoundary = { _ in fired.mark() } }
    await engine.play(clipped)

    // Generous: the join and first frames take a couple of seconds before the six start.
    for _ in 0 ..< 40 {
        if fired.value { break }
        try await Task.sleep(nanoseconds: 500_000_000)
    }
    let at = await MainActor.run { engine.player.currentItem?.currentTime().seconds ?? -1 }
    print("  playhead at \(String(format: "%.1f", at))s, wanted to stop at \(Int(clipped.stopAt))s")
    print("  boundary fired: \(fired.value)")
    #expect(fired.value, "the item ended and nothing told the channel to advance")
    await engine.stop()
}

/// A tiny box so the boundary callback can be observed from the test.
final class Fired: @unchecked Sendable {
    private var flag = false
    private let lock = NSLock()
    func mark() { lock.lock(); flag = true; lock.unlock() }
    var value: Bool { lock.lock(); defer { lock.unlock() }; return flag }
}

@Test(.enabled(if: live)) func channelFourteenActuallyPlays() async throws {
    let (box, plex, plexBase) = try await clients()
    let state = try await box.now(channel: 14)
    let entry = try #require(state.now, "ch14 off air")
    let ref = try #require(entry.plex)
    print("  box says   \(entry.displayTitle)")
    print("  rating key \(ref.ratingKey) media \(ref.mediaIndex) part \(ref.partIndex)")

    let part = try await plex.part(ratingKey: ref.ratingKey,
                                   mediaIndex: ref.mediaIndex, partIndex: ref.partIndex)
    print("  part       container=\(part.container) video=\(part.videoCodec) "
          + "audio=\(part.audioCodec) width=\(part.width)")
    print("  route      \(StreamRouter.route(part))")

    let resolver = StreamResolver(plex: plex, clientID: "tub3-test-0001")
    let item = try await resolver.resolve(entry, base: plexBase)
    print("  url        \(item.url.absoluteString.prefix(120))")

    let playerItem = AVPlayerItem(url: item.url)
    let player = AVPlayer(playerItem: playerItem)
    if item.playFor > 0 {
        playerItem.forwardPlaybackEndTime = CMTime(seconds: item.stopAt, preferredTimescale: 600)
    }
    player.play()
    var waited = 0.0
    while playerItem.status == .unknown, waited < 25 {
        try await Task.sleep(nanoseconds: 100_000_000); waited += 0.1
    }
    print("  status     \(playerItem.status.rawValue) (1=ready 2=failed)")
    if let error = playerItem.error { print("  ERROR      \(error)") }
    try await Task.sleep(nanoseconds: 3_000_000_000)
    print("  tracks     \(playerItem.tracks.count)")
    print("  playhead   \(String(format: "%.1f", playerItem.currentTime().seconds))")
    print("  rate       \(player.rate)")
    #expect(playerItem.status == .readyToPlay)
    #expect(player.rate > 0)
    player.pause()
    if let s = item.session { await plex.stop(session: s) }
}
