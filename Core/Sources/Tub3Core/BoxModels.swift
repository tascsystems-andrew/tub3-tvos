import Foundation

/// What the box says is on a channel, decoded exactly as `tub3/tvapi.py` emits it.
///
/// The field names are the box's, not Swift's, because a rename here is a silent decoding
/// failure later — and the one field this app cannot afford to lose is `media_index`, which
/// says *which version* of a film to ask Plex for. A wrong one answers HTTP 200 and plays a
/// different cut.

public struct PlexRef: Codable, Equatable, Sendable {
    public let ratingKey: String
    public let kind: String
    public let seconds: Double
    public let mediaIndex: Int
    public let partIndex: Int
    public let mediaID: String

    enum CodingKeys: String, CodingKey {
        case ratingKey = "rating_key"
        case kind
        case seconds
        case mediaIndex = "media_index"
        case partIndex = "part_index"
        case mediaID = "media_id"
    }

    public init(ratingKey: String, kind: String, seconds: Double,
                mediaIndex: Int, partIndex: Int, mediaID: String) {
        self.ratingKey = ratingKey
        self.kind = kind
        self.seconds = seconds
        self.mediaIndex = mediaIndex
        self.partIndex = partIndex
        self.mediaID = mediaID
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ratingKey = try c.decode(String.self, forKey: .ratingKey)
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? "item"
        seconds = try c.decodeIfPresent(Double.self, forKey: .seconds) ?? 0
        // Older maps wrote four-element entries. The box pads them, but a client that
        // assumes the newer shape and meets an older box should degrade, not throw.
        mediaIndex = try c.decodeIfPresent(Int.self, forKey: .mediaIndex) ?? 0
        partIndex = try c.decodeIfPresent(Int.self, forKey: .partIndex) ?? 0
        mediaID = try c.decodeIfPresent(String.self, forKey: .mediaID) ?? ""
    }
}

/// One entry in a channel's plan — a programme, an advert, or a station ident.
public struct NowEntry: Codable, Equatable, Sendable {
    public let contentType: String
    public let duration: Double
    /// How far into the file this entry starts. A programme resumed after an ad break does
    /// not start at zero, and an app that ignored this would replay the first half.
    public let offsetSeconds: Double
    public let remainingSeconds: Double
    public let title: String?
    /// The programme's real name, resolved by the box against Plex at schedule time.
    /// Absent from an older box, which is why `displayTitle` still has its fallback.
    public let show: String?
    public let episode: String?
    public let plex: PlexRef?

    enum CodingKeys: String, CodingKey {
        case contentType = "content_type"
        case duration
        case offsetSeconds = "offset_seconds"
        case remainingSeconds = "remaining_seconds"
        case title
        case show
        case episode
        case plex
    }

    /// What the bug should say, joined the way `ChannelBugView` splits it.
    ///
    /// The box answers this properly now. `tuner.box` has always drawn its own bug from
    /// `tuner.titles.describe`, but `/api/tv/N/now` used to hand over the pool symlink's
    /// stem — a `folder__` prefix and a scene suffix wrapped around the answer — so the
    /// television said "This Old House / The Reading House" while the app said
    /// "thisoldhouse__This Old House - S08E08 - The Reading House - 8 WEBDL-1080p". The
    /// regex below was this app guessing at something the box already knew.
    ///
    /// It is kept only as the fallback for a box that has not been updated. Delete it once
    /// no such box is left.
    public var displayTitle: String {
        if let show, !show.isEmpty {
            if let episode, !episode.isEmpty { return "\(show) — \(episode)" }
            return show
        }
        guard let raw = title else { return "" }
        let stripped = raw.replacingOccurrences(
            of: "^[a-z0-9]+__", with: "", options: [.regularExpression])
        return stripped.replacingOccurrences(of: ".", with: " ")
    }

    public var isProgramme: Bool { contentType == "feature" }
}

public struct MapState: Codable, Equatable, Sendable {
    public let builtAt: Double?
    public let keys: Int?
    public let stale: Bool?

    enum CodingKeys: String, CodingKey {
        case builtAt = "built_at"
        case keys
        case stale
    }
}

/// The whole answer to "what is on channel N".
public struct NowPlaying: Codable, Equatable, Sendable {
    public let channel: Int
    public let station: String
    public let serverTime: Double
    public let blockTitle: String?
    public let blockEndsAt: Double?
    public let now: NowEntry?
    public let next: NowEntry?
    public let map: MapState?
    public let offAir: Bool?
    public let kind: String?
    public let error: String?

    enum CodingKeys: String, CodingKey {
        case channel, station, now, next, map, kind, error
        case serverTime = "server_time"
        case blockTitle = "block_title"
        case blockEndsAt = "block_ends_at"
        case offAir = "off_air"
    }

    /// Lenient about `station` and `serverTime`, strict about everything else.
    ///
    /// The box's per-channel error branches answer with `{error, channel}` and little else —
    /// one of them has no station name to give, because the failure *is* that the channel is
    /// not on the dial. Requiring those two fields turned every such answer into a decoding
    /// failure, which the tuner turned into `.broken`, which nothing retries out of. So a
    /// fault the box could explain in one sentence bricked the app until it was relaunched,
    /// and the handling written for exactly this case never ran.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        channel = try c.decode(Int.self, forKey: .channel)
        station = try c.decodeIfPresent(String.self, forKey: .station) ?? ""
        serverTime = try c.decodeIfPresent(Double.self, forKey: .serverTime) ?? 0
        blockTitle = try c.decodeIfPresent(String.self, forKey: .blockTitle)
        blockEndsAt = try c.decodeIfPresent(Double.self, forKey: .blockEndsAt)
        now = try c.decodeIfPresent(NowEntry.self, forKey: .now)
        next = try c.decodeIfPresent(NowEntry.self, forKey: .next)
        map = try c.decodeIfPresent(MapState.self, forKey: .map)
        offAir = try c.decodeIfPresent(Bool.self, forKey: .offAir)
        kind = try c.decodeIfPresent(String.self, forKey: .kind)
        error = try c.decodeIfPresent(String.self, forKey: .error)
    }

    public var isGuide: Bool { kind == "guide" }
    public var isOffAir: Bool { offAir == true }
}

public struct Channel: Codable, Equatable, Identifiable, Sendable {
    public let channel: Int
    public let station: String
    public let kind: String

    public var id: Int { channel }
    public var isGuide: Bool { kind == "guide" }
    public var isAmbiance: Bool { kind == "ambiance" }
}

public struct ChannelList: Codable, Equatable, Sendable {
    public let channels: [Channel]
}
