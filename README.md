# 8008TUB3 for tvOS

The dial, on an Apple TV. Same channels, same schedule, same commercials as the box in the
living room — but the bytes come from Plex instead of the NAS, so it works anywhere the Plex
server does.

This is a *front end*, not a second scheduler. The box decides what is on; this asks, plays
what it is told, and asks again when the slot is up.

## Running it

```bash
make core     # 69 tests, no simulator, seconds
make live     # real box, real Plex, real decode
make tv       # build for the tvOS simulator
make uitest   # remote input, the channel strip, the guide
make uiprobe  # the live probes — abandoned transcoders, one open per burst of presses
```

`make uitest` is the gate and is meant to be believable: it skips everything in
`Tests/TVUITests/Live`, because none of it can fail for a reason the app is answerable for.
The parks hold a screen still for a photograph; the two probes assert only that a label is
still there, since what they actually measure is read off Plex and out of the unified log by
a person. Anything that could go red for the box's reasons is out of the gate, or the gate
going red stops meaning anything.

## Layout

```
Core/      the brain — models, clients, routing, the tuner. Builds for macOS, which is why
           the hard parts are testable in seconds without a simulator.
Shared/    SwiftUI for both platforms. Every `#if os(tvOS)` in it is about the remote or
           the focus engine, which is the only thing an iPad genuinely does not have.
Apps/TV    tvOS shell        Apps/Phone   iPhone/iPad shell
Tests/     XCUIRemote tests — the only way to check remote behaviour from a terminal.
           `Tests/TVUITests/Live` is the opt-in half: probes and photography, never the gate.
```

## Things that are true and cost a day each to discover

**Plex will not serve a stream it has not agreed to.** Call
`/video/:/transcode/universal/decision` before `start.m3u8`. It looks optional because a
*cold* rating key answers 200 the first time and 400 on every repeat — so it works in a demo
and fails in steady state, where the same films and adverts replay constantly.

**`X-Plex-Platform=tvOS`** is exact and case-sensitive. It is also worth having: tvOS gets
`videoDecision=copy` with EAC3 5.1 preserved, where `Safari`, `iOS` and `Chrome` all force
audio down to MP3 stereo. Unrecognised values are a 400, not a default.

**Put every `X-Plex-*` value in the query string**, never in a header. AVPlayer fetches the
playlist and each segment itself and does not carry custom headers onto those requests.

**`mediaIndex` selects which version of a film plays.** A wrong one returns HTTP 200 and
quietly plays a different cut.

**Do not chase HEVC passthrough.** Plex reports success, AVPlayer reports `readyToPlay`, audio
plays, and there is no video track — a silent black screen.

**Plex does not reap abandoned transcodes.** Every tune-out must stop its session or eleven
channel flips leave eleven live transcoders.

**`forwardPlaybackEndTime`, always.** The box's `duration` is the schedule entry's length, not
the file's, so an item left to run to end-of-file plays straight through its own ad breaks.

**On tvOS, `.onTapGesture` never fires from the clickpad**, and wrapping the screen in a
`Button` to catch the press collapses the whole view tree into one accessibility element —
which makes the channel strip and the channel bug unaddressable by VoiceOver and by tests.
Move commands need something `.focusable()`, or the remote is simply dead.

## Not done yet

The ambiance channel plays but is not yet phase-locked to the box's clock, so it will be at a
different point in the loop than the television. iPad builds and shares the code but has no
touch controls. Nothing is tuned for a real Apple TV yet — see below.

## Getting it onto a real Apple TV

Pairing is interactive and cannot be scripted: Xcode › Window › Devices and Simulators, pair
the Apple TV over the network, enter the code it shows. Everything after that is scriptable.
The signing team is `32CZP96PT9` — not the id inside the certificate's common name.

## Getting it onto an Apple TV

### The straightforward way — Xcode, no API key

This is the same flow as any iOS app and needs nothing set up in advance:

```bash
make gen && open Tub3.xcodeproj
```

Then **Product › Archive**, and in the Organizer **Distribute App › TestFlight (and App Store)**.
Xcode creates the Apple Distribution certificate and the App Store provisioning profile itself,
prompting once. You will also need an app record at App Store Connect (bundle
`com.tascsystems.tub3`, platform tvOS); the store-wide name must be unique.

**Why the command line cannot do this unattended.** `xcodebuild archive` with automatic
signing asks Apple for a *development* profile, and a tvOS development profile requires a
registered Apple TV. With none registered the archive fails with

> Your team has no devices from which to generate a provisioning profile

which is a message about devices when the actual missing thing is a distribution certificate.
Either register an Apple TV, or archive from the GUI, or supply an API key (below).

### The unattended way — an App Store Connect API key

Only needed for CI or a scripted release. Generate one at App Store Connect › Users and
Access › Integrations › App Store Connect API › Team Keys with the **App Manager** role, save
the `.p8` to `~/.appstoreconnect/private_keys/AuthKey_<KEYID>.p8`, then:

```bash
ASC_KEY_ID=XXXXXXXXXX ASC_ISSUER_ID=xxxxxxxx-... make testflight
```

### Running it on your own Apple TV directly

Pair it once — Xcode › Window › Devices and Simulators, add over the network, enter the code
shown on screen. That also registers it with your team, which makes the command-line archive
above work. The signing team is `32CZP96PT9`, not the id inside the certificate's common name.
