# Feature Ideas

Captured 2026-03-28. Candidates for future implementation.

---

## Connectivity & Monitoring

### 1. Connection History & Uptime Tracking
Log status changes (connected/blocked/offline) with timestamps. Show "Online for 4h 23m since last outage" in the menu, and a history view in Settings. Gives users visibility into flaky connections they might miss.

### 2. Outage Notifications
System notifications when connectivity changes state — e.g. "Connection lost" and "Back online (was down 4m 12s)". Configurable: only notify after N seconds of outage to avoid noise on brief blips.

### 3. Latency Thresholds / "Slow" State
Add a 4th status — "slow" (orange?) — when latency exceeds a user-defined threshold (e.g. >500ms). Currently the app only distinguishes blocked vs. connected, but a high-latency connection is a real degraded state worth surfacing.

### 4. Multiple Endpoint Monitoring
Let users add extra URLs to probe (e.g. a work VPN gateway, `8.8.8.8`, a specific service). Show each independently in the menu. Useful for knowing if a site is down vs. your whole internet.

---

## Network Info

### 5. WiFi Signal Strength (RSSI)
Show signal strength for the current WiFi network in the menu. Already reads WiFi SSID via `CoreWLAN`; RSSI is available from the same `CWInterface`. A simple bar indicator would be natural here.

### 6. ISP / ASN Name Alongside External IP
When fetching the external IP, also resolve the ISP name (e.g. "Comcast" or "Cloudflare WARP") via an IP-to-ASN lookup. Low cost, interesting context.

### 7. DNS Latency
Measure and display DNS resolution time separately from HTTP latency. Useful for diagnosing slow-DNS situations where HTTP probes look fine but browsing feels slow.

---

## UX & Convenience

### 8. Per-Network Settings (Known Networks Preferences)
The menu already tracks "Known Networks." Let users assign names, tags, or different poll intervals to known networks (e.g. poll every 5m on trusted home WiFi, every 30s on a coffee shop network).

### 9. Menu Bar Latency Sparkline
A tiny 10-point sparkline of recent latency values rendered in the menu bar (text or image mode). Shows trend at a glance — is latency creeping up, spiking, or stable?

### 10. Diagnostics Export
A "Copy Diagnostics" menu item that puts a formatted summary (IP, DNS, latency, speed, VPN status, OS/version) on the clipboard. Instantly useful when filing a support ticket with IT or an ISP.

---

## Settings & Integrations

### 11. macOS Focus / Do Not Disturb Integration
Suppress outage notifications during active Focus modes. Uses `EventKit`/`FocusFilter` — respectful of the user's attention. (Pairs with feature #2.)

### 12. iCloud Sync for Preferences
Sync icon sets, known network names, and settings across Macs via `NSUbiquitousKeyValueStore`. Zero-config for users who already have iCloud.

---

## Priority Suggestions

| Priority | Feature | Reason |
|----------|---------|--------|
| High | #2 Outage Notifications | Immediate user value, low complexity |
| High | #3 Latency Threshold / Slow State | Fills a real gap in the 3-state model |
| High | #1 Connection History | Transforms app from status indicator into diagnostic tool |
| Medium | #5 WiFi Signal Strength | Low effort, `CWInterface` already in use |
| Medium | #10 Diagnostics Export | High utility, minimal implementation effort |
| Medium | #8 Per-Network Settings | Builds on existing Known Networks infrastructure |
| Low | #4 Multiple Endpoints | More complex UI/state management |
| Low | #9 Latency Sparkline | Polish feature, requires history data (#1 first) |
| Low | #6 ISP / ASN Lookup | Nice-to-have, external API dependency |
| Low | #7 DNS Latency | Niche audience, adds complexity |
| Low | #11 Focus Integration | Depends on #2 being built first |
| Low | #12 iCloud Sync | Low demand, adds sync complexity |
