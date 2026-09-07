import Foundation

/// A resolved thing to put on screen: where the bytes are, where to join, and when to stop.
public struct PlayableItem: Equatable, Sendable {
    public let url: URL
    /// Where in the file this entry begins. Not zero for a programme resumed after an ad.
    public let joinAt: Double
    /// How much of it this entry is entitled to play.
    ///
    /// This is the schedule's number, not the file's, and the difference is the whole game:
    /// a feature split around three ad breaks is one file that the plan enters and leaves
    /// four times. An item allowed to run to end-of-file plays straight through the adverts,
    /// which is the one thing this project exists to prevent.
    public let playFor: Double
    /// Present only when Plex is transcoding, and then it must be handed back.
    public let session: String?
    public let title: String
    public let contentType: String

    public var stopAt: Double { joinAt + playFor }

    public init(url: URL, joinAt: Double, playFor: Double, session: String?,
                title: String, contentType: String) {
        self.url = url
        self.joinAt = joinAt
        self.playFor = playFor
        self.session = session
        self.title = title
        self.contentType = contentType
    }
}

/// Turns "what is on" into "what to play", which means asking Plex what the version is,
/// deciding whether AVFoundation can open it, and getting permission when it cannot.
public struct StreamResolver: Sendable {
    let plex: PlexClient
    let clientID: String

    public init(plex: PlexClient, clientID: String) {
        self.plex = plex
        self.clientID = clientID
    }

    public func resolve(_ entry: NowEntry, base: URL) async throws -> PlayableItem {
        guard let ref = entry.plex else {
            throw PlexError.unreachable("the box could not identify this file in Plex")
        }
        let part = try await plex.part(ratingKey: ref.ratingKey,
                                       mediaIndex: ref.mediaIndex,
                                       partIndex: ref.partIndex)

        switch StreamRouter.route(part) {
        case .direct(let key):
            // No handshake, no session, nothing to clean up, and the seek is exact. The
            // Part key from the metadata call is the same one a direct-play decision would
            // return, so asking for that decision would be a wasted round trip.
            var c = URLComponents(url: base.appendingPathComponent(String(key.dropFirst())),
                                  resolvingAgainstBaseURL: false)!
            c.queryItems = [.init(name: "X-Plex-Client-Identifier", value: clientID)]
            return PlayableItem(url: c.url!, joinAt: entry.offsetSeconds,
                                playFor: entry.remainingSeconds, session: nil,
                                title: entry.displayTitle, contentType: entry.contentType)

        case .hls:
            let session = PlexParams.newSession()
            let params = PlexParams(ratingKey: ref.ratingKey,
                                    mediaIndex: ref.mediaIndex,
                                    partIndex: ref.partIndex,
                                    offset: entry.offsetSeconds,
                                    session: session,
                                    clientID: clientID)
            try await plex.agree(params)
            return PlayableItem(url: params.startURL(base: base),
                                joinAt: entry.offsetSeconds,
                                playFor: entry.remainingSeconds, session: session,
                                title: entry.displayTitle, contentType: entry.contentType)
        }
    }
}
