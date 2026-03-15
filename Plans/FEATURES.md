# Online Indicator — Feature Roadmap

Features are organized into phases by complexity and impact. Work through them incrementally — each feature is self-contained and won't break existing behaviour. Check off items as you implement them.

---

## Phase 1 — High Impact, Lower Complexity

These can each be shipped as a small, focused PR.

---

### 1.1 System Notifications on Status Change

- [ ] **Implement**

**Description**  
Send a macOS `UNUserNotification` whenever the connection status transitions (e.g. Connected → Blocked, No Network → Connected). Give users per-transition toggles in Settings so they can opt out of noisy alerts (e.g. suppress "reconnected" if they only care about drops).

**Implementation notes**
- Import `UserNotifications` and request authorization in `AppDelegate.startApp()` alongside the existing `UpdateChecker.checkIfNeeded` call.
- In `AppState`, track `previousStatus` alongside the existing `statusUpdateHandler`. Call a new `NotificationManager` (new file) when `previousStatus != newStatus`.
- `NotificationManager` exposes `notify(from: ConnectionStatus, to: ConnectionStatus)` — it checks three new `UserDefaults` booleans (e.g. `notifyOnDisconnect`, `notifyOnReconnect`, `notifyOnBlocked`) before firing.
- Add three toggle rows to `SettingsView`'s General tab inside a new "Notifications" `SettingsSection`, using the existing `SettingsRow` + `Toggle` pattern already used for "Launch at Login" and "Show Known Networks".
- Add three new `UserDefaults.Key` cases in `UserDefaultsKeys.swift`.

---

### 1.2 Force Check — Menu Action & Keyboard Shortcut

- [ ] **Implement**

**Description**  
Add a "Check Now" item to the status bar menu that immediately triggers a connectivity probe outside the normal interval. Optionally bind it to a keyboard shortcut (e.g. `⌘R`).

**Implementation notes**
- In `MenuBuilder.build()`, insert a new `NSMenuItem` with title "Check Now" and key equivalent `"r"` (modifier mask `.command`) above the Settings item.
- Add a `var onForceCheck: (() -> Void)?` callback on `MenuBuilder`, wired in `AppDelegate.setupStatusItem()` to call `AppState.shared.restart()` (which already calls `checkConnection()` immediately).
- No new files needed; change is confined to `MenuBuilder.swift` and `Online-IndicatorApp.swift`.

---

### 1.3 Response Time / Latency Display

- [ ] **Implement**

**Description**  
Capture the round-trip time of each connectivity probe and display it in the status bar menu (e.g. "23 ms"). Optionally show it as a subtitle on the menu header.

**Implementation notes**
- In `ConnectivityChecker.checkOutboundConnection`, record `Date()` before `task.resume()` and compute `latency = Date().timeIntervalSince(startDate) * 1000` inside the completion closure. Update the callback signature to `(Bool, Double?)` — the second parameter is the latency in milliseconds (nil on failure).
- Add a `var lastLatencyMs: Double?` stored property to `AppState`, updated each time `statusUpdateHandler` fires.
- In `MenuBuilder`, update `MenuHeaderView` to accept an optional latency value and render it as a secondary label (e.g. `"23 ms"`) to the right of the version string, following the existing `versionLabel` layout pattern.
- Add `menuBuilder.updateLatency(AppState.shared.lastLatencyMs)` inside `AppDelegate.applyIcon(for:)`.

---

## Phase 2 — Power User Features

Slightly larger changes, each still bounded to 2–4 files.

---

### 2.1 Connectivity History & Uptime Log

- [ ] **Implement**

**Description**  
Record every status transition with a timestamp. Show a scrollable history list and a daily uptime percentage in a new "History" tab in Settings.

**Implementation notes**
- Create `ConnectivityHistory.swift`. Define `struct HistoryEntry: Codable { let date: Date; let status: ConnectionStatus }` and a `ConnectivityHistory` actor that appends entries to a JSON file at `~/Library/Application Support/Online Indicator/history.json` (capping at 500 entries to bound disk use). Expose `entries: [HistoryEntry]` and `uptimePercentage(for:) -> Double`.
- In `AppState`, call `ConnectivityHistory.shared.record(status)` each time `statusUpdateHandler` fires and the status has changed.
- Add a third tab "History" to `SettingsView` using the same `Picker` segmented control. Render entries in a `List` with relative timestamps (using `RelativeDateTimeFormatter`) and coloured status badges matching the existing icon colours from `IconPreferences`. Show an uptime summary row at the top.
- Add `UserDefaults.Key.historyEnabled` toggle in General tab to let users opt out of logging.

---

### 2.2 Run Script on Status Change

- [ ] **Implement**

**Description**  
Let users configure a shell command (or AppleScript path) to be run when the status transitions to a chosen state. Useful for pausing downloads, toggling a VPN, running a notification webhook, etc.

**Implementation notes**
- Create `ScriptRunner.swift` with a single `static func run(_ command: String, environment: [String: String])` that calls `Process` with `/bin/zsh -c` and passes `ONLINE_INDICATOR_STATUS` as an environment variable (values: `"connected"`, `"blocked"`, `"noNetwork"`).
- Add `UserDefaults.Key` cases: `scriptOnConnected`, `scriptOnBlocked`, `scriptOnNoNetwork` (all `String?`).
- Call `ScriptRunner.run` from `AppState`'s `statusUpdateHandler` when the status changes, reading the relevant key.
- Add a new "Automation" `SettingsSection` in the General tab with three `TextField` rows (one per state) for the command strings. Use the existing URL-field layout from the Ping URL row as a template.
- Run the process on a background queue; do not block the main thread or surface errors to the user beyond a brief console log.

---

### 2.3 VPN Detection

- [ ] **Implement**

**Description**  
Detect when a VPN tunnel is active (`utun*` interfaces) and show a distinct badge or icon overlay in the menu bar, separate from the three connectivity states.

**Implementation notes**
- In `IPAddressProvider.current()`, the `excluded` set already filters out `utun` interfaces from the IP display. Add a companion `static func isVPNActive() -> Bool` that iterates `getifaddrs` and returns `true` if any `utun*` interface is up and has an assigned address. The existing `getifaddrs` traversal can be reused.
- Add `var isVPNActive: Bool` to `AppState`, updated on each `checkConnection()` call alongside the existing status.
- In `StatusIconRenderer.render(for:wifiName:)`, accept an additional `isVPNActive: Bool` parameter. When true, composite a small lock badge (SF Symbol `lock.shield.fill`) onto the rendered image using `NSImage` drawing — follow the same image-compositing approach already used in `applyIcon(for:)` in `AppDelegate`.
- Add a `UserDefaults.Key.showVPNBadge` toggle in the Appearance tab.

---

## Phase 3 — Rich Visualizations

More involved UI work; each feature is independent.

---

### 3.1 Sparkline in Menu Bar

- [ ] **Implement**

**Description**  
Render a tiny inline graph of the last N probe latencies directly in the status bar, similar to how iStatMenus shows CPU load. The graph replaces or sits beside the icon when enabled.

**Implementation notes**
- Depends on **Phase 1.3** (latency tracking) being implemented first.
- Create `SparklineRenderer.swift` with a `static func render(samples: [Double?], size: NSSize) -> NSImage` that draws a line graph using `NSBezierPath`. Use three colours: green for < 100 ms, yellow for 100–500 ms, red for > 500 ms or nil (failed). Keep the rendering stateless and cache-free.
- `AppState` maintains `var latencyHistory: [Double?]` (ring buffer, max 20 samples), appended on each probe completion.
- In `AppDelegate.applyIcon(for:)`, when sparkline is enabled (`UserDefaults.Key.showSparkline`), call `SparklineRenderer.render` and composite it with the status icon image.
- Add a "Show Sparkline" toggle in the Appearance tab.

---

### 3.2 Network Quality Score

- [ ] **Implement**

**Description**  
Combine latency and recent probe failure rate into a 1–5 signal-strength score displayed as an optional menu bar icon variant. Gives a richer signal than the binary connected/blocked state.

**Implementation notes**
- Depends on **Phase 1.3** (latency) and **Phase 3.1** (latency history) being implemented first.
- Add `var qualityScore: Int` (1–5) to `AppState`, computed from the last 5 `latencyHistory` samples: score 5 = all successful + p50 < 100 ms; score 1 = majority failed. Define thresholds as constants in a `NetworkQuality.swift` helper.
- In `StatusIconRenderer`, when quality score mode is enabled, swap the symbol name for a `wifi.N` style variant (e.g. `wifi`, `wifi.exclamationmark`, `wifi.slash`) sized 1–5, using SF Symbols' built-in signal bar variants.
- Add a "Show Quality Score" toggle in the Appearance tab.

---

### 3.3 Multi-Endpoint Monitoring

- [ ] **Implement**

**Description**  
Probe several URLs in parallel (e.g. `captive.apple.com`, `1.1.1.1`, a custom URL) and report connectivity only when a configurable minimum number pass. Reduces false negatives from single-endpoint failures.

**Implementation notes**
- Extend `ConnectivityChecker` with a `checkMultiple(urls: [URL], threshold: Int, completion: (Bool, Double?) -> Void)` method that fires concurrent `URLSession` data tasks using a `DispatchGroup`. Average the latencies of successful probes.
- Add `UserDefaults.Key.additionalPingURLs` (`[String]`) and `UserDefaults.Key.pingThreshold` (`Int`, default 1) to `UserDefaultsKeys.swift`.
- Update `AppState.checkConnection()` to call the multi-endpoint variant when `additionalPingURLs` is non-empty.
- Add a "Additional Endpoints" section in Settings (General tab → Monitoring), with an `+` button to add URLs and a stepper for the threshold, following the existing Ping URL field style.

---

## Phase 4 — Ecosystem & Sharing

---

### 4.1 Apple Shortcuts Integration

- [ ] **Implement**

**Description**  
Expose three Shortcuts app actions: "Get Current Status", "Force Check Now", and "Get Last Probe Latency". Enables no-code automation with other apps.

**Implementation notes**
- Add `AppIntents` framework. Create `GetStatusIntent.swift`, `ForceCheckIntent.swift`, and `GetLatencyIntent.swift`, each conforming to `AppIntent`.
- `GetStatusIntent` reads `AppState.shared.currentStatus` (make this `public` / accessible) and returns it as an `AppEnum` with three cases matching `ConnectionStatus`.
- `ForceCheckIntent` calls `AppState.shared.restart()` on the main actor and returns immediately.
- `GetLatencyIntent` returns `AppState.shared.lastLatencyMs` as a `Double?`.
- No UI changes needed; Shortcuts discovers intents automatically via the `AppIntents` conformances at build time (requires macOS 13+).

---

### 4.2 Location-Based Profiles

- [ ] **Implement**

**Description**  
Automatically switch check interval, ping URL, and icon set based on the connected Wi-Fi SSID. Useful for aggressive checking on public networks and relaxed checking at home.

**Implementation notes**
- Create `NetworkProfile.swift`: `struct NetworkProfile: Codable, Identifiable { var ssid: String; var refreshInterval: Double?; var pingURL: String?; var iconSetName: String? }`.
- Store an array of profiles in `UserDefaults.Key.networkProfiles` (`[NetworkProfile]`).
- In `AppState.checkConnection()`, after reading the SSID from `IPAddressProvider.current().wifiName`, look up a matching profile and temporarily override `refreshInterval` and `ConnectivityChecker.monitoringURLString` for that check cycle.
- Add a "Network Profiles" `SettingsSection` in the General tab with a list of saved SSIDs (populated from `CWWiFiClient` known profiles, already used in `MenuBuilder`) and inline editors for interval/URL overrides.

---

### 4.3 Icon Set Sharing (Export / Import)

- [ ] **Implement**

**Description**  
Export a custom icon set as a `.onlineindicator` file that another user can import. Enables sharing themed sets in the community.

**Implementation notes**
- The `UserIconSet` model is already `Codable` and stored as JSON (see `IconPreferences.swift` / `userIconSets_v1` key). Export is simply writing the JSON to a file with a custom UTI extension.
- Register `com.yourname.onlineindicator.iconset` as a document type in `Info.plist` with extension `.onlineindicator`.
- In `SymbolBrowserView`'s "My Sets" tab, add "Export" (using `NSSavePanel`) and "Import" (using `NSOpenPanel`) buttons alongside the existing "Save" flow.
- On import, decode the file as `UserIconSet`, call `userSetsStore.add(_:)`, and refresh the list.

---

### 4.4 DNS Server Display

- [ ] **Implement**

**Description**  
Show the current DNS servers in the status bar menu alongside the IP addresses, with click-to-copy.

**Implementation notes**
- In `IPAddressProvider.Addresses`, add `var dnsServers: [String]`.
- Populate it in `IPAddressProvider.current()` by reading `/etc/resolv.conf` (parse `nameserver` lines) or via `SCDynamicStoreCopyValue` with key `State:/Network/Global/DNS` for a more reliable programmatic approach.
- In `MenuBuilder.build()`, add a "DNS" menu item styled identically to the existing IPv4/IPv6 items (using `ipAttributedString(label:value:available:)`). Show the primary DNS server; if more than one, join them with a comma.
- Wire up `onCopyDNS` callback on `MenuBuilder` for click-to-copy, following the existing `onCopyIPv4` / `onCopyIPv6` pattern.

---

## Phase 5 — Platform & Sync

Larger scope or requiring additional entitlements / tooling.

---

### 5.1 iCloud Sync

- [ ] **Implement**

**Description**  
Sync icon preferences, check interval, ping URL, and custom icon sets across multiple Macs using iCloud key-value storage.

**Implementation notes**
- Enable the iCloud entitlement in the Xcode project (target → Signing & Capabilities → iCloud → Key-value storage).
- Create `CloudSync.swift` wrapping `NSUbiquitousKeyValueStore`. Mirror the same `UserDefaults.Key` raw values — on `NSUbiquitousKeyValueStoreDidChangeExternallyNotification`, copy changed keys into `UserDefaults` and post `iconPreferencesChanged` / trigger `AppState.shared.restart()` as appropriate.
- Add a "Sync with iCloud" toggle in the General tab. When enabled, do an initial push of local values to the store and subscribe to external change notifications.
- Custom icon sets (`userIconSets_v1`) are a JSON blob that fits comfortably within the 1 MB iCloud KV limit for typical use.

---

### 5.2 CLI Companion Tool

- [ ] **Implement**

**Description**  
A small command-line executable (`onlineindicator`) that queries the running app's current status, useful for shell scripts, CI environments, and Alfred/Raycast workflows.

**Implementation notes**
- Add a new macOS Command Line Tool target in Xcode (`onlineindicator-cli`).
- Use `DistributedNotificationCenter` or a Unix domain socket in `~/Library/Application Support/Online Indicator/cli.sock` for IPC. The app writes its current status JSON to the socket; the CLI reads it and exits with a status code (0 = connected, 1 = blocked, 2 = noNetwork).
- CLI usage: `onlineindicator status` (prints `connected` / `blocked` / `noNetwork`), `onlineindicator check` (forces a probe and waits for the result), `onlineindicator latency` (prints last latency in ms).
- Install the CLI to `/usr/local/bin` via a post-install script or document it for manual symlink in `README.md`.

---

### 5.3 Menu Bar Text Mode

- [ ] **Implement**

**Description**  
Show "Online", "Blocked", or "Offline" as text only in the menu bar, with no icon, for users who prefer words over symbols.

**Implementation notes**
- This is almost fully implemented already. `StatusIconRenderer` already supports `menuLabelEnabled` and `attributedLabel` on its output — and `AppDelegate.applyIcon(for:)` already branches on `output.attributedLabel` to display text instead of an image.
- The only addition needed is a master "Text Mode" toggle in the Appearance tab that sets all three slots' `menuLabelEnabled = true` and pre-fills their labels with "Online", "Blocked", and "Offline" respectively (using `IconPreferences.save`).
- Consider also offering a combined icon + label mode by rendering both in a single `NSAttributedString` (icon as attachment + space + text).

---

### 5.4 "What's New" Sheet After Updates

- [ ] **Implement**

**Description**  
Show a one-time "What's New" sheet on first launch after an update, summarising new features, similar to how native macOS apps handle version upgrades.

**Implementation notes**
- `UpdateChecker` already fetches and caches the GitHub release notes as `lastUpdateNotes` in `UserDefaults`. The raw Markdown is already surfaced in `SettingsView`'s update row.
- Add `UserDefaults.Key.lastSeenVersion` (`String`). On `applicationDidFinishLaunching`, compare `AppInfo.marketingVersion` against `lastSeenVersion`; if they differ and `lastUpdateNotes` is non-nil, call `WindowCoordinator.showWhatsNew(notes:)`.
- Create `WhatsNewView.swift` — a simple SwiftUI sheet with the app icon, version heading, and a `ScrollView` rendering the cached release notes. Style it to match the existing `OnboardingView`.
- After the user dismisses it, set `lastSeenVersion = AppInfo.marketingVersion` so it only appears once.

---

## Notes

- All `UserDefaults.Key` additions should be made in `UserDefaultsKeys.swift` to keep key management centralised.
- All new Settings UI should reuse the existing `SettingsSection` / `SettingsRow` components from `SettingsView.swift` for visual consistency.
- The `AppState.ConnectionStatus` enum is the single source of truth for status — never duplicate it.
- Run the existing `OnlineIndicatorTests` target after each phase to confirm no regressions.
