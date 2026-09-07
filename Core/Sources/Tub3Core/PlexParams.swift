import Foundation

/// The query Plex needs to agree to a stream, and then to serve it.
public struct PlexParams: Sendable {

    /// Exact, case-sensitive, and not negotiable. Measured against this server: `tvOS`
    /// yields `videoDecision=copy, audioDecision=copy` and preserves EAC3 5.1; `Safari`,
    /// `iOS`, `Chrome` and `Roku` all force the audio down to MP3 stereo. Values Plex does
    /// not recognise — including `Apple TV`, `AppleTV` and lowercase `tvos` — are rejected
    /// with HTTP 400 rather than defaulted.
    public static let platform = "tvOS"

    public let ratingKey: String
    public let mediaIndex: Int
    public let partIndex: Int
    public let offset: Double
    public let session: String
    public let clientID: String

    public init(ratingKey: String, mediaIndex: Int, partIndex: Int,
                offset: Double, session: String, clientID: String) {
        self.ratingKey = ratingKey
        self.mediaIndex = mediaIndex
        self.partIndex = partIndex
        self.offset = offset
        self.session = session
        self.clientID = clientID
    }

    /// Everything goes in the query string, never in HTTP headers: AVPlayer fetches the
    /// playlist and every segment itself, and it does not carry custom headers onto those
    /// requests. A header-based identity works for the first call and then evaporates.
    public var items: [URLQueryItem] {
        [
            .init(name: "path", value: "/library/metadata/\(ratingKey)"),
            .init(name: "mediaIndex", value: String(mediaIndex)),
            .init(name: "partIndex", value: String(partIndex)),
            .init(name: "protocol", value: "hls"),
            .init(name: "offset", value: String(Int(offset.rounded(.down)))),
            .init(name: "fastSeek", value: "1"),
            .init(name: "directPlay", value: "0"),
            .init(name: "directStream", value: "1"),
            .init(name: "videoQuality", value: "100"),
            .init(name: "maxVideoBitrate", value: "20000"),
            .init(name: "location", value: "lan"),
            .init(name: "autoAdjustQuality", value: "0"),
            .init(name: "X-Plex-Platform", value: Self.platform),
            .init(name: "X-Plex-Client-Identifier", value: clientID),
            .init(name: "session", value: session),
        ]
    }

    func url(base: URL, path: String) -> URL {
        var c = URLComponents(url: base.appendingPathComponent(path),
                              resolvingAgainstBaseURL: false)!
        c.queryItems = items
        return c.url!
    }

    public func decisionURL(base: URL) -> URL {
        url(base: base, path: "video/:/transcode/universal/decision")
    }

    public func startURL(base: URL) -> URL {
        url(base: base, path: "video/:/transcode/universal/start.m3u8")
    }

    /// Plex does not reap abandoned transcodes. Eleven channel changes leave eleven live
    /// transcoders, so every tune-out must stop the session it is leaving or a few minutes
    /// of channel surfing will bury the server.
    public static func stopURL(base: URL, session: String, clientID: String) -> URL {
        var c = URLComponents(
            url: base.appendingPathComponent("video/:/transcode/universal/stop"),
            resolvingAgainstBaseURL: false)!
        c.queryItems = [
            .init(name: "session", value: session),
            .init(name: "X-Plex-Client-Identifier", value: clientID),
        ]
        return c.url!
    }

    public static func newSession() -> String {
        "tub3-" + String(format: "%08x", UInt32.random(in: 0 ... UInt32.max))
    }
}
