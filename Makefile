# Every command an agent should ever need. No Xcode GUI anywhere.
SIM_TV  := platform=tvOS Simulator,name=Apple TV 4K (3rd generation)
SCHEME  := Tub3TV

.PHONY: gen core tv run clean
gen:                       ## regenerate the project after a source-layout change
	xcodegen generate

core:                      ## the fast loop — no simulator, seconds
	swift test --package-path Core

live:                      ## real box, real Plex, real decode
	TUB3_LIVE=1 swift test --package-path Core --no-parallel

tv: gen                    ## build the tvOS app for the simulator
	xcodebuild -project Tub3.xcodeproj -scheme $(SCHEME) \
	  -destination '$(SIM_TV)' -derivedDataPath build build | tail -5

uitest: gen               ## remote input, the strip, the guide — muted
	xcodebuild -project Tub3.xcodeproj -scheme $(SCHEME) \
	  -destination '$(SIM_TV)' -derivedDataPath build build-for-testing >/dev/null
	xcodebuild -project Tub3.xcodeproj -scheme $(SCHEME) \
	  -destination '$(SIM_TV)' -derivedDataPath build test-without-building \
	  | grep -E '^Test Case .*(passed|failed)'

phone: gen                 ## build the iOS/iPadOS app
	xcodebuild -project Tub3.xcodeproj -scheme Tub3Phone \
	  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath build build | tail -3

clean:
	rm -rf build Tub3.xcodeproj
