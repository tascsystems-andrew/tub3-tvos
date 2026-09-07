import Foundation

public enum PlexError: Error, LocalizedError {
    case unreachable(String)
    case badStatus(Int)
    case noSuchPart(mediaIndex: Int, partIndex: Int)

    public var errorDescription: String? {
        switch self {
        case .unreachable(let why): "Plex is not answering (\(why))"
        case .badStatus(let code): "Plex answered HTTP \(code)"
        case .noSuchPart(let m, let p): "Plex has no media \(m) part \(p) for that item"
        }
    }
}

/// Talks to Plex: what a version actually is, and permission to stream it.
public actor PlexClient {
    public let base: URL
    public let clientID: String
    private let session: URLSession

    public init(base: URL, clientID: String, session: URLSession = .shared) {
        self.base = base
        self.clientID = clientID
        self.session = session
    }

    /// The version the box named, so the routing gate can judge it.
    ///
    /// `mediaIndex` is honoured here rather than assumed: an item routinely holds several
    /// versions of different containers and resolutions, and taking the first one is how a
    /// 720p rip ends up billed as the 1080p cut — or worse, how a different film plays.
    public func part(ratingKey: String, mediaIndex: Int, partIndex: Int) async throws -> PlexPart {
        var c = URLComponents(
            url: base.appendingPathComponent("library/metadata/\(ratingKey)"),
            resolvingAgainstBaseURL: false)!
        c.queryItems = [.init(name: "X-Plex-Client-Identifier", value: clientID)]
        let url = c.url!

        var request = URLRequest(url: url)
        request.setValue("application/xml", forHTTPHeaderField: "Accept")
        let data: Data
        do {
            let (body, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw PlexError.unreachable("no response")
            }
            guard (200 ..< 300).contains(http.statusCode) else {
                throw PlexError.badStatus(http.statusCode)
            }
            data = body
        } catch let error as PlexError {
            throw error
        } catch {
            throw PlexError.unreachable(error.localizedDescription)
        }

        let parts = MetadataParser.parts(from: data)
        guard mediaIndex < parts.count, partIndex < parts[mediaIndex].count else {
            throw PlexError.noSuchPart(mediaIndex: mediaIndex, partIndex: partIndex)
        }
        return parts[mediaIndex][partIndex]
    }

    /// Plex will not serve a stream it has not agreed to.
    ///
    /// This is not folklore and not a browser artefact. Measured against this server: a cold
    /// `start.m3u8` answers 200 the *first* time a rating key is asked for and 400 on every
    /// repeat — so on a dial where the same films and the same few hundred adverts replay
    /// constantly, skipping the handshake fails in steady state while looking fine in a
    /// one-shot test. The decision is also what actually chooses the transcode profile;
    /// `start.m3u8` merely inherits it.
    @discardableResult
    public func agree(_ params: PlexParams) async throws -> Bool {
        let url = params.decisionURL(base: base)
        do {
            let (_, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse else { return false }
            return (200 ..< 300).contains(http.statusCode)
        } catch {
            throw PlexError.unreachable(error.localizedDescription)
        }
    }

    /// Hand back the transcoder.
    ///
    /// Plex does not reap abandoned sessions: measured, eleven channel changes left eleven
    /// live transcoders running. Someone flipping through the dial would bury the server in
    /// a couple of minutes, so this is called on every tune-out, and failures are swallowed
    /// because a channel change must never be blocked by tidying up the last one.
    public func stop(session id: String) async {
        let url = PlexParams.stopURL(base: base, session: id, clientID: clientID)
        _ = try? await session.data(from: url)
    }
}

/// Pulls Media/Part out of a `/library/metadata` response.
///
/// Written by hand rather than with a model layer because exactly five attributes matter and
/// the nesting — Media contains Part — is the whole point: it is what `mediaIndex` indexes.
enum MetadataParser {
    static func parts(from data: Data) -> [[PlexPart]] {
        let delegate = Delegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.media
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        var media: [[PlexPart]] = []
        private var container = ""
        private var videoCodec = ""
        private var audioCodec = ""
        private var width = 0

        func parser(_ parser: XMLParser, didStartElement name: String,
                    namespaceURI: String?, qualifiedName: String?,
                    attributes attr: [String: String] = [:]) {
            switch name {
            case "Media":
                container = attr["container"] ?? ""
                videoCodec = attr["videoCodec"] ?? ""
                audioCodec = attr["audioCodec"] ?? ""
                width = Int(attr["width"] ?? "") ?? 0
                media.append([])
            case "Part":
                guard !media.isEmpty else { return }
                // A Part may override its Media's container, and when it does the Part is
                // the one that describes the bytes AVFoundation will be handed.
                media[media.count - 1].append(
                    PlexPart(container: attr["container"] ?? container,
                             videoCodec: videoCodec,
                             audioCodec: audioCodec,
                             width: width,
                             key: attr["key"] ?? ""))
            default:
                break
            }
        }
    }
}
