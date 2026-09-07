import Testing
@testable import Tub3Core

@Test func mp4H264AacPlaysDirectly() {
    let part = PlexPart(container: "mp4", videoCodec: "h264", audioCodec: "aac",
                        width: 1920, key: "/library/parts/1/2/file.mp4")
    #expect(StreamRouter.route(part) == .direct(partKey: "/library/parts/1/2/file.mp4"))
}

@Test func eac3SurvivesTheGate() {
    // tvOS carries EAC3 natively, and it is the reason to send X-Plex-Platform=tvOS at all.
    let part = PlexPart(container: "mp4", videoCodec: "h264", audioCodec: "eac3",
                        width: 1920, key: "/k")
    #expect(StreamRouter.route(part) == .direct(partKey: "/k"))
}

@Test func mkvIsTranscodedEvenThoughPlexClaimsOtherwise() {
    // Plex answers directplay for this and hands back a key AVFoundation rejects with
    // -11828. Our gate has to be stricter than the server's opinion.
    let part = PlexPart(container: "mkv", videoCodec: "h264", audioCodec: "aac",
                        width: 1920, key: "/k")
    #expect(StreamRouter.route(part) == .hls(reason: "container mkv"))
}

@Test func hevcIsTranscodedEvenInsideMp4() {
    // Passthrough here yields audio with no video track and no error at all.
    let part = PlexPart(container: "mp4", videoCodec: "hevc", audioCodec: "aac",
                        width: 1920, key: "/k")
    #expect(StreamRouter.route(part) == .hls(reason: "video hevc"))
}

@Test func fourKIsTranscodedForTheAppleTvHd() {
    let part = PlexPart(container: "mp4", videoCodec: "h264", audioCodec: "aac",
                        width: 3840, key: "/k")
    #expect(StreamRouter.route(part) == .hls(reason: "width 3840"))
}
