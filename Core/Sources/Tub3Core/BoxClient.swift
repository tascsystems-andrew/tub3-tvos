import Foundation

public enum BoxError: Error, LocalizedError {
    case unreachable(String)
    case badStatus(Int)

    public var errorDescription: String? {
        switch self {
        case .unreachable(let why): "The box is not answering (\(why))"
        case .badStatus(let code): "The box answered HTTP \(code)"
        }
    }
}

/// Everything the app asks the Pi.
///
/// The box is the only authority on *what is on*; Plex is only ever asked *how to play it*.
/// Keeping that split sharp is what lets the schedule stay a schedule — the app never
/// decides what to show next, it asks.
public actor BoxClient {
    public let base: URL
    private let session: URLSession

    public init(base: URL, session: URLSession = .shared) {
        self.base = base
        self.session = session
    }

    private func get<T: Decodable>(_ path: String, as: T.Type) async throws -> T {
        let url = base.appendingPathComponent(path)
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse else {
                throw BoxError.unreachable("no response")
            }
            guard (200 ..< 300).contains(http.statusCode) else {
                throw BoxError.badStatus(http.statusCode)
            }
            return try JSONDecoder().decode(T.self, from: data)
        } catch let error as BoxError {
            throw error
        } catch {
            throw BoxError.unreachable(error.localizedDescription)
        }
    }

    public func channels() async throws -> [Channel] {
        try await get("api/tv/channels", as: ChannelList.self).channels
    }

    public func now(channel: Int) async throws -> NowPlaying {
        try await get("api/tv/\(channel)/now", as: NowPlaying.self)
    }

    public func guide() async throws -> Guide {
        try await get("api/guide", as: Guide.self)
    }

    /// The tracks the box plays behind its own listings, as absolute URLs on the box.
    ///
    /// Absolute here rather than at the call site: the box answers with paths, and the one
    /// thing that knows where the box is, is the box's client.
    public func guideMusic() async throws -> [URL] {
        try await get("api/tv/guide/music", as: MusicList.self).tracks.compactMap {
            URL(string: $0.url, relativeTo: base)?.absoluteURL
        }
    }

    public func plexBase() async throws -> URL? {
        struct Info: Decodable { let url: String? }
        guard let raw = try await get("api/tv/plex", as: Info.self).url, !raw.isEmpty else {
            return nil
        }
        return URL(string: raw)
    }
}
