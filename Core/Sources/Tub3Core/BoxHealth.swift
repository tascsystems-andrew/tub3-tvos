import Foundation

/// What the box thinks of itself, translated into something a person in another room can act
/// on.
///
/// Every field is optional with a default. The box has been running long enough to produce
/// combinations that are not in this file, and a health screen that throws is worse than one
/// that says it does not know.
public struct BoxHealth: Decodable, Equatable, Sendable {
    public struct Build: Decodable, Equatable, Sendable {
        public var known: Bool = false
        public var failed: Bool = false
        public var missing: Bool = false
        public var running: Bool = false

        enum CodingKeys: String, CodingKey { case known, failed, missing, running }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            known = (try? c.decode(Bool.self, forKey: .known)) ?? false
            failed = (try? c.decode(Bool.self, forKey: .failed)) ?? false
            missing = (try? c.decode(Bool.self, forKey: .missing)) ?? false
            running = (try? c.decode(Bool.self, forKey: .running)) ?? false
        }
        public init(known: Bool = false, failed: Bool = false,
                    missing: Bool = false, running: Bool = false) {
            self.known = known; self.failed = failed
            self.missing = missing; self.running = running
        }
    }

    public var level: String = ""
    public var lowChannels: [String] = []
    public var unknown: [String] = []
    public var building: Bool = false
    public var build: Build = Build()

    enum CodingKeys: String, CodingKey {
        case level, unknown, building, build
        case lowChannels = "low_channels"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        level = (try? c.decode(String.self, forKey: .level)) ?? ""
        // The box sends objects here on some paths and strings on others; neither is worth
        // throwing over on a screen whose job is to say whether things are all right.
        lowChannels = (try? c.decode([String].self, forKey: .lowChannels)) ?? []
        unknown = (try? c.decode([String].self, forKey: .unknown)) ?? []
        building = (try? c.decode(Bool.self, forKey: .building)) ?? false
        build = (try? c.decode(Build.self, forKey: .build)) ?? Build()
    }

    public init(level: String = "", lowChannels: [String] = [], unknown: [String] = [],
                building: Bool = false, build: Build = Build()) {
        self.level = level
        self.lowChannels = lowChannels
        self.unknown = unknown
        self.building = building
        self.build = build
    }

    /// One line, for somebody who is not going to ssh into anything.
    ///
    /// From the structured fields only, never from `messages`. The box's own prose is about
    /// systemd units — "The schedule build unit is failed — no build will ever run", "KDIN
    /// has 3.2h of schedule left, under the 4h mark" — which is the right thing to say to
    /// whoever administers the box and the wrong thing to put on a television in another
    /// room. `Tuner.present` and `Tuner.recover` hold the same rule one screen earlier.
    ///
    /// Ordered by what a viewer should do about it, not by severity: a build that has
    /// stopped is worse than a channel running low, but both end in the same address.
    public var householdSummary: String {
        if building { return "Busy updating its listings" }
        if build.missing { return "It has stopped making new schedules" }
        if build.failed { return "Could not update its listings" }
        if lowChannels.count == 1 { return "\(lowChannels[0]) has run out of programmes" }
        if lowChannels.count > 1 {
            return "\(lowChannels[0]) and \(lowChannels.count - 1) others have run out"
        }
        if !unknown.isEmpty { return "A schedule cannot be read" }
        if level == "ok" { return "All well" }
        // Never raw prose, never silence. An unrecognised combination is still a combination
        // somebody can look at, and the address is on the screen under this line.
        return level.isEmpty ? "Cannot ask it" : "Worth a look"
    }

    /// The root row's value, which is shorter because it sits in a value column.
    public var shortVerdict: String {
        if building || build.missing || build.failed { return "needs attention" }
        if !lowChannels.isEmpty || !unknown.isEmpty { return "worth a look" }
        if level == "ok" { return "all well" }
        return level.isEmpty ? "cannot ask it" : "worth a look"
    }
}
