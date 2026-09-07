import Foundation

/// Whether an item can be handed to AVFoundation as-is, or has to go through Plex's
/// transcoder.
public enum StreamRoute: Equatable, Sendable {
    /// Play the file itself. No decision call, no transcode session, nothing to clean up,
    /// and the seek is frame-accurate.
    case direct(partKey: String)
    /// Ask Plex to transcode. Costs a handshake, a session, and a session to stop later.
    case hls(reason: String)
}

/// One version of one item, as `/library/metadata/<ratingKey>` describes it.
public struct PlexPart: Equatable, Sendable {
    public let container: String
    public let videoCodec: String
    public let audioCodec: String
    public let width: Int
    public let key: String

    public init(container: String, videoCodec: String, audioCodec: String,
                width: Int, key: String) {
        self.container = container
        self.videoCodec = videoCodec
        self.audioCodec = audioCodec
        self.width = width
        self.key = key
    }
}

public enum StreamRouter {

    /// Codecs and containers AVFoundation will open directly. Deliberately strict.
    ///
    /// The temptation is to ask Plex whether it can direct-play, and the temptation must be
    /// resisted: asked about an mkv, Plex answers `decision="directplay"` and hands back a
    /// part key that AVFoundation then rejects with -11828 "media format is not supported".
    /// Plex is answering "can I serve these bytes untouched", which is a different question
    /// from "can this client open them". So the gate is ours and it is conservative — a
    /// wrong "yes" is a black screen, a wrong "no" costs a transcode nobody will notice.
    static let directContainers: Set<String> = ["mp4", "m4v", "mov"]
    static let directVideo: Set<String> = ["h264"]
    static let directAudio: Set<String> = ["aac", "ac3", "eac3"]

    public static func route(_ part: PlexPart) -> StreamRoute {
        let container = part.container.lowercased()
        let video = part.videoCodec.lowercased()
        let audio = part.audioCodec.lowercased()

        guard directContainers.contains(container) else {
            return .hls(reason: "container \(container)")
        }
        guard directVideo.contains(video) else {
            // HEVC is excluded even inside mp4. Apple wants HEVC in fMP4 and this server
            // only emits MPEG-TS, and the failure mode is the nastiest kind: Plex reports
            // success, AVPlayer reports readyToPlay, the audio plays, and there is no video
            // track at all. A silent black screen is worse than a transcode.
            return .hls(reason: "video \(video)")
        }
        guard directAudio.contains(audio) else {
            return .hls(reason: "audio \(audio)")
        }
        guard part.width <= 1920 else {
            // The Apple TV HD tops out at 1080p. Sending it 4K is a stall, not a picture.
            return .hls(reason: "width \(part.width)")
        }
        return .direct(partKey: part.key)
    }
}
