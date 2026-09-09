import Foundation
import Testing
@testable import Tub3Core

/// The translation table. Pure, cheap, and the thing most likely to be quietly wrong — the
/// screen it feeds is read by somebody who cannot see the box.
struct BoxHealthTests {

    private func decode(_ json: String) throws -> BoxHealth {
        try JSONDecoder().decode(BoxHealth.self, from: Data(json.utf8))
    }

    @Test func theRealPayloadFromTheBoxReadsAllWell() throws {
        // Copied from http://boobtube.local:8008/api/status, unedited.
        let h = try decode("""
        {"level":"ok","messages":[],"build":{"known":true,"failed":false,"missing":false,
        "running":false,"result":"success","exit_code":0,"finished":1788967056.0},
        "low_channels":[],"orphans":[],"unknown":[],"building":false,"alert_hours":4.0}
        """)
        #expect(h.householdSummary == "All well")
        #expect(h.shortVerdict == "all well")
    }

    @Test func buildingBeatsEverythingElse() {
        let h = BoxHealth(level: "warning", lowChannels: ["KDIN"], building: true)
        // Channels run low *because* it is rebuilding. Saying so is more use than the symptom.
        #expect(h.householdSummary == "Busy updating its listings")
    }

    @Test func aStoppedBuilderIsNamedPlainly() {
        #expect(BoxHealth(build: .init(missing: true)).householdSummary
                == "It has stopped making new schedules")
        #expect(BoxHealth(build: .init(failed: true)).householdSummary
                == "Could not update its listings")
    }

    @Test func oneLowChannelIsNamedAndSeveralAreCounted() {
        #expect(BoxHealth(level: "warning", lowChannels: ["KDIN"]).householdSummary
                == "KDIN has run out of programmes")
        #expect(BoxHealth(level: "warning", lowChannels: ["KDIN", "BBC", "THE ZONE"])
                .householdSummary == "KDIN and 2 others have run out")
    }

    @Test func anEmptyOrUnrecognisedAnswerNeverGoesBlank() {
        // The two ends of the fail-open rule: nothing at all, and something we do not know.
        #expect(BoxHealth().householdSummary == "Cannot ask it")
        #expect(BoxHealth(level: "banana").householdSummary == "Worth a look")
        #expect(BoxHealth(level: "banana").shortVerdict == "worth a look")
    }

    @Test func aPayloadMissingEveryFieldStillDecodes() throws {
        // A box older than this screen, or one mid-upgrade. Degrade, never throw.
        let h = try decode("{}")
        #expect(h.householdSummary == "Cannot ask it")
    }

    @Test func aPayloadWithTheWrongTypesStillDecodes() throws {
        // low_channels arrives as objects on some paths. Not worth throwing over.
        let h = try decode(#"{"level":"ok","low_channels":[{"name":"KDIN"}],"building":"no"}"#)
        #expect(h.householdSummary == "All well")
    }
}
