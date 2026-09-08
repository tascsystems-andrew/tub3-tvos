import Foundation
import Testing
@testable import Tub3Core

/// What people actually type into a setup screen, and what a Bonjour resolver actually hands
/// back. Both have a shape `URL(string:)` gets wrong quietly.
@Suite("Box address")
struct BoxAddressTests {

    @Test("an address and a port, the most likely thing anyone types")
    func addressAndPort() throws {
        let url = try #require(BoxAddress.parse("10.0.1.116:8008"))
        #expect(url.absoluteString == "http://10.0.1.116:8008")
        // The failure this exists to prevent: URL(string:) takes this and parses no scheme.
        #expect(URL(string: "10.0.1.116:8008")?.scheme != "http")
    }

    @Test("a bare hostname gets a scheme and the default port")
    func bareHost() throws {
        #expect(try #require(BoxAddress.parse("tub3.local")).absoluteString
                == "http://tub3.local:8008")
        #expect(try #require(BoxAddress.parse("  boobtube  ")).absoluteString
                == "http://boobtube:8008")
    }

    @Test("a full URL is kept, and a trailing path is not")
    func fullURL() throws {
        #expect(try #require(BoxAddress.parse("http://box:9000")).absoluteString
                == "http://box:9000")
        #expect(try #require(BoxAddress.parse("http://box:9000/api/tv/")).absoluteString
                == "http://box:9000")
    }

    @Test("https is refused rather than accepted and failed later")
    func onlyHTTP() {
        // Accepting it would produce a URL that dies at connect time with a certificate
        // error, which is not something a viewer can act on.
        #expect(BoxAddress.parse("https://box:8008") == nil)
    }

    @Test("nonsense is nil, not a crash and not a half-URL")
    func rubbish() {
        #expect(BoxAddress.parse("") == nil)
        #expect(BoxAddress.parse("   ") == nil)
        #expect(BoxAddress.parse("http://") == nil)
    }

    /// Bonjour resolves to `10.0.1.116%en0`, and `URL(string:)` returns nil for a host with a
    /// zone in it. Measured against the real box on this network.
    @Test("an interface zone is stripped, because a URL cannot carry one")
    func zone() {
        #expect(BoxAddress.stripZone("10.0.1.116%en0") == "10.0.1.116")
        #expect(BoxAddress.stripZone("fe80::1%en0") == "fe80::1")
        #expect(BoxAddress.stripZone("10.0.1.116") == "10.0.1.116")
        #expect(URL(string: "http://10.0.1.116%en0:8008") == nil)   // the bug itself
    }
}
