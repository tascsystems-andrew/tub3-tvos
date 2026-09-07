# 8008TUB3 for tvOS

The dial, on an Apple TV. Same channels, same schedule, same commercials as the box in the
living room — but the bytes come from Plex instead of the NAS, so it works anywhere the Plex
server does.

This is a *front end*, not a second scheduler. The box decides what is on; this asks, plays
what it is told, and asks again when the slot is up.

## Running it

```bash
make core     # 24 tests, no simulator, ~5ms
make live     # real box, real Plex, real decode
make tv       # build for the tvOS simulator
make uitest   # remote input, the channel strip, the guide
```

## Layout

```
Core/      the brain — models, clients, routing, the tuner. Builds for macOS, which is why
           the hard parts are testable in seconds without a simulator.
Shared/    SwiftUI for both platforms. Exactly one `#if os(tvOS)` so far.
Apps/TV    tvOS shell        Apps/Phone   iPhone/iPad shell
Tests/     XCUIRemote tests — the only way to check remote behaviour from a terminal.
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
