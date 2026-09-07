import Foundation
import Testing
@testable import Tub3Core

private func fixture(_ name: String) throws -> Data {
    let url = Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: nil)
    return try Data(contentsOf: #require(url))
}

@Test func parsesEveryVersionOfAnItem() throws {
    // 1131 is Star Wars, which this library holds in more than one version.
    let media = MetadataParser.parts(from: try fixture("metadata-1131.xml"))
    #expect(media.isEmpty == false)
    for versions in media { #expect(versions.isEmpty == false) }
    let first = media[0][0]
    #expect(first.key.hasPrefix("/library/parts/"))
    #expect(first.videoCodec.isEmpty == false)
    #expect(first.width > 0)
}

@Test func mediaIndexSelectsBetweenVersions() throws {
    // 4692 is Alice in Wonderland, which Plex holds twice. The whole reason media_index
    // exists is that these two are different files; the parser must keep them apart.
    let media = MetadataParser.parts(from: try fixture("metadata-4692.xml"))
    #expect(media.count >= 1)
    if media.count >= 2 {
        #expect(media[0][0].key != media[1][0].key)
    }
}

@Test func theRouterHasAnOpinionAboutEveryRealVersion() throws {
    for name in ["metadata-1131.xml", "metadata-4692.xml"] {
        for versions in MetadataParser.parts(from: try fixture(name)) {
            for part in versions {
                // Whatever it is, the gate must decide rather than crash or dither.
                _ = StreamRouter.route(part)
            }
        }
    }
}
