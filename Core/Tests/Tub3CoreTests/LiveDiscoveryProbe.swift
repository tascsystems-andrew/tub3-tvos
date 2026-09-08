import XCTest
@testable import Tub3Core

/// Browses the real network for a real box. Run by name:
///   swift test --package-path Core --filter LiveDiscoveryProbe
///
/// This is the only test that can prove the advertisement and the browser agree, because both
/// halves fail silently when they do not: avahi publishes nothing anyone complains about, and
/// NWBrowser reports an empty network rather than an error.
final class LiveDiscoveryProbe: XCTestCase {
    func testFindsABoxOnThisNetwork() async throws {
        let boxes = await BoxDiscovery.find(timeout: .seconds(5))
        print("PROBE found \(boxes.count) box(es)")
        for b in boxes { print("PROBE   \(b.name) -> \(b.url.absoluteString)") }
        XCTAssertFalse(boxes.isEmpty, "nothing advertising \(BoxDiscovery.serviceType) here")

        // And it must be a box, not merely something answering on a port.
        let box = try XCTUnwrap(boxes.first)
        let client = BoxClient(base: box.url)
        let channels = try await client.channels()
        print("PROBE   it answered with \(channels.count) channels: \(channels.map(\.channel))")
        XCTAssertFalse(channels.isEmpty)
    }
}
