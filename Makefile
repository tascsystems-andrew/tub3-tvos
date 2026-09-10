# Every command an agent should ever need. No Xcode GUI anywhere.
SIM_TV  := platform=tvOS Simulator,name=Apple TV 4K (3rd generation)
SCHEME  := Tub3TV
# The box the UI tests point the app at. `TEST_RUNNER_` is xcodebuild's own prefix for
# variables it forwards into the test runner; it strips it on the way in.
BOX     ?= http://boobtube.local:8008

.PHONY: gen core tv run uitest uiprobe clean
gen:                       ## regenerate the project after a source-layout change
	xcodegen generate

core:                      ## the fast loop — no simulator, seconds
	swift test --package-path Core

live:                      ## real box, real Plex, real decode
	TUB3_LIVE=1 swift test --package-path Core --no-parallel

tv: gen                    ## build the tvOS app for the simulator
	xcodebuild -project Tub3.xcodeproj -scheme $(SCHEME) \
	  -destination '$(SIM_TV)' -derivedDataPath build build | tail -5

# Everything under Tests/TVUITests/Live, and for one reason: none of it can fail for a
# reason the app is answerable for. The parks are photography aids that hold a screen still
# and assert almost nothing; the two probes assert only that a label is still there, because
# what they actually measure — abandoned Plex transcoders, one `play url` per burst of
# presses — is read off the server and out of the unified log by a person. Each is another
# launch and another live Plex session, and a gate that can go red for the box's reasons is
# a gate whose red means nothing.
#
# Here rather than in the scheme's `skippedTests`, because a scheme skip cannot be
# overridden: measured, `-only-testing` against a skipped test runs zero tests and exits 0,
# so `uiprobe` below and the by-name screenshot park would both have silently done nothing.
PROBES  := -skip-testing:Tub3TVUITests/ParkTests \
           -skip-testing:Tub3TVUITests/LiveSurfProbe \
           -skip-testing:Tub3TVUITests/LiveSettleProbe

uitest: gen               ## remote input, the strip, the guide — muted
	xcodebuild -project Tub3.xcodeproj -scheme $(SCHEME) \
	  -destination '$(SIM_TV)' -derivedDataPath build build-for-testing >/dev/null
	TEST_RUNNER_TUB3_BOX=$(BOX) xcodebuild -project Tub3.xcodeproj -scheme $(SCHEME) \
	  -destination '$(SIM_TV)' -derivedDataPath build test-without-building $(PROBES) \
	  | grep -E '^Test Case .*(passed|failed)'

uiprobe: gen              ## the live probes: abandoned transcoders, one open per burst
	xcodebuild -project Tub3.xcodeproj -scheme $(SCHEME) \
	  -destination '$(SIM_TV)' -derivedDataPath build build-for-testing >/dev/null
	TEST_RUNNER_TUB3_BOX=$(BOX) xcodebuild -project Tub3.xcodeproj -scheme $(SCHEME) \
	  -destination '$(SIM_TV)' -derivedDataPath build test-without-building \
	  -only-testing:Tub3TVUITests/LiveSurfProbe \
	  -only-testing:Tub3TVUITests/LiveSettleProbe \
	  | grep -E '^Test Case .*(passed|failed)'

phone: gen                 ## build the iOS/iPadOS app
	xcodebuild -project Tub3.xcodeproj -scheme Tub3Phone \
	  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath build build | tail -3

# --- TestFlight -------------------------------------------------------------------------
# Needs an App Store Connect API key at ~/.appstoreconnect/private_keys/AuthKey_<ID>.p8 and
# these two set in your environment (or on the make command line):
#   ASC_KEY_ID=XXXXXXXXXX  ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
# With the key present, xcodebuild creates the distribution certificate and provisioning
# profile itself — which is why the key is the single thing that unblocks all of this.
ASC_KEY := $(HOME)/.appstoreconnect/private_keys/AuthKey_$(ASC_KEY_ID).p8

archive: gen               ## build a signed .xcarchive for the App Store
	xcodebuild -project Tub3.xcodeproj -scheme $(SCHEME) \
	  -destination 'generic/platform=tvOS' \
	  -archivePath build/Tub3TV.xcarchive archive \
	  -allowProvisioningUpdates \
	  -authenticationKeyPath $(ASC_KEY) \
	  -authenticationKeyID $(ASC_KEY_ID) \
	  -authenticationKeyIssuerID $(ASC_ISSUER_ID)

testflight: archive        ## upload that archive to TestFlight
	xcodebuild -exportArchive \
	  -archivePath build/Tub3TV.xcarchive \
	  -exportOptionsPlist ExportOptions.plist \
	  -exportPath build/export \
	  -allowProvisioningUpdates \
	  -authenticationKeyPath $(ASC_KEY) \
	  -authenticationKeyID $(ASC_KEY_ID) \
	  -authenticationKeyIssuerID $(ASC_ISSUER_ID)

clean:
	rm -rf build Tub3.xcodeproj
