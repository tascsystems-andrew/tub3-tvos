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

    /// - Parameter forceTranscode: ask Plex to stream it even when the file looks playable
    ///   as it stands. Used after a direct fetch has failed, so a channel is not left
    ///   re-requesting a URL the server has already refused.
    public func resolve(_ entry: NowEntry, base: URL,
                        forceTranscode: Bool = false) async throws -> PlayableItem {
        guard let ref = entry.plex else {
            throw PlexError.unreachable("the box could not identify this file in Plex")
        }
        let part = try await plex.part(ratingKey: ref.ratingKey,
                                       mediaIndex: ref.mediaIndex,
                                       partIndex: ref.partIndex)

        switch forceTranscode ? .hls(reason: "a direct fetch was refused") : StreamRouter.route(part) {
        case .direct(let key):
            // No handshake, no session, nothing to clean up, and the seek is exact. The
            // Part key from the metadata call is the same one a direct-play decision would
            // return, so asking for that decision would be a wasted round trip.
            //
            // Deliberately anonymous. Naming the client here is what broke the one channel
            // that used this path: Plex answers /library/parts/... with 503 for this app's
            // identifier while answering its API calls with 200 for the same identifier, and
            // an unnamed request for the same file returns 206. Identity buys nothing on a
            // raw file — the server grants LAN clients access without it — and evidently
            // costs the file.
            var c = URLComponents(url: base.appendingPathComponent(String(key.dropFirst())),
                                  resolvingAgainstBaseURL: false)!
            c.queryItems = nil
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
