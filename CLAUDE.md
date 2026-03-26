# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

Open `Online Indicator.xcodeproj` in Xcode and use the standard Run/Build commands, or from the command line:

```bash
# Debug build
xcodebuild build \
  -project "Online Indicator.xcodeproj" \
  -scheme "Online Indicator" \
  -configuration Debug

# Release archive (used by CI)
xcodebuild archive \
  -project "Online Indicator.xcodeproj" \
  -scheme "Online Indicator" \
  -configuration Release \
  -archivePath build/OnlineIndicator.xcarchive \
  CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual PROVISIONING_PROFILE_SPECIFIER=""

# Run tests
xcodebuild test \
  -project "Online Indicator.xcodeproj" \
  -scheme "OnlineIndicatorTests"
```

Releases are built automatically by `.github/workflows/build-dmg.yml` on `v*` tags. `MARKETING_VERSION` is injected from the git tag at build time.

## Architecture

This is a **menu bar only** SwiftUI + AppKit macOS app (no main window). The entry point is `Online-IndicatorApp.swift` (`AppDelegate`), which owns the `NSStatusItem`.

### Core status flow

```
NetworkMonitor (NWPathMonitor)
    └─► AppState.checkConnection()
            ├─► .noNetwork  (if no path)
            └─► ConnectivityChecker.checkOutboundConnection()
                    ├─► .connected  (HTTP 200–399, body "Success" for captive.apple.com)
                    └─► .blocked    (any other result)
                         └─► AppDelegate.applyIcon(for:)
                                  └─► StatusIconRenderer.render(for:wifiName:)
```

`AppState` owns the timer (default 30 s, configurable) and debounces rapid `NetworkMonitor` path changes (1 s). Settings changes call `AppState.restart()` to reset the timer and probe immediately.

### Menu

`MenuBuilder` builds the `NSMenu` once and updates it dynamically:
- **Static items**: WiFi, IPv4, IPv6 (updated via stored `NSMenuItem?` references)
- **Dynamic items**: DNS entries and Known Networks use integer tags (`dnsTag = 800`, `knownNetworksTag = 900`) so items can be removed and re-inserted on each update without rebuilding the full menu.
- `IPAddressProvider.current()` reads live network state (via `getifaddrs` + `SCDynamicStore`) on every menu open; DNS via `State:/Network/Global/DNS`.

### Icon customisation

`IconPreferences` stores per-status slots (SF Symbol name, color, optional text label) in `UserDefaults` under keys like `iconSymbol.connected`. The `userIconSets_v1` key stores user-saved icon sets as JSON-encoded `[UserIconSet]`.

`StatusIconRenderer.render(for:wifiName:)` is stateless — it reads `IconPreferences` and returns an `Output` with a tinted `NSImage` (and an optional `NSAttributedString` for text-label mode). `AppDelegate.applyIcon` consumes this output and sets it on the `NSStatusItem.button`.

### Settings & persistence

All `UserDefaults` keys are defined in `UserDefaultsKeys.swift` as `UserDefaults.Key` enum cases — always add new keys there. Settings UI is in `SettingsView.swift` and uses `SettingsSection` / `SettingsRow` components throughout; follow that pattern for new settings.

`WindowCoordinator` manages opening/closing the Settings and Onboarding windows (both `NSPanel`-backed SwiftUI).

### Key files

| File | Purpose |
|------|---------|
| `AppState.swift` | Single source of truth for `ConnectionStatus`; owns timer + monitoring |
| `ConnectivityChecker.swift` | HTTP probe to `captive.apple.com` (or custom URL) |
| `MenuBuilder.swift` | Builds and dynamically updates the `NSMenu` |
| `StatusIconRenderer.swift` | Stateless icon rendering from preferences |
| `IconPreferences.swift` | Read/write per-status icon slots; posts `iconPreferencesChanged` notification |
| `IPAddressProvider.swift` | Reads live IPv4/IPv6/gateway/DNS/WiFi name |
| `UserDefaultsKeys.swift` | Central registry of all `UserDefaults` keys |
| `Plans/FEATURES.md` | Detailed implementation notes for planned features |
