import SwiftUI
import AppKit

struct SettingsView: View {

    @State private var interval: Double = {
        let v = UserDefaults.standard.double(for: .refreshInterval)
        return v == 0 ? 60 : v
    }()
    @State private var intervalText    = ""
    @State private var intervalSaved   = false
    @State private var intervalInvalid = false
    @State private var pingURL         = ""
    @State private var pingURLSaved    = false
    @State private var pingURLInvalid  = false
    @State private var isLaunchEnabled = false
    @State private var loginItemError: String?

    enum UpdateStatus: Equatable {
        case idle, checking
        case available(tag: String, notes: String?)
        case upToDate
        case error(String)
    }
    @State private var updateStatus: UpdateStatus = .idle
    @State private var cachedUpdateURL: URL?
    @State private var showChangelog = false
    @State private var lastCheckDate: Date? = UserDefaults.standard.object(for: .lastUpdateCheck) as? Date

    @State private var showIconSetPicker = false
    @State private var selectedIconSetID: UUID?

    // MARK: - Icon set helpers

    private var currentIconSetName: String {
        iconSets.first { $0.id == selectedIconSetID }?.name ?? "Custom"
    }

    private func resolveSelectedSet() {
        let c = IconPreferences.slot(for: .connected).symbolName
        let b = IconPreferences.slot(for: .blocked).symbolName
        let n = IconPreferences.slot(for: .noNetwork).symbolName
        selectedIconSetID = iconSets.first {
            $0.connectedSymbol == c && $0.blockedSymbol == b && $0.noNetworkSymbol == n
        }?.id
    }

    private func applyIconSet(_ set: IconSet) {
        let (c, b, n) = set.toSlots()
        IconPreferences.save(c, for: .connected)
        IconPreferences.save(b, for: .blocked)
        IconPreferences.save(n, for: .noNetwork)
        selectedIconSetID = set.id
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {

                SettingsSection(title: "General") {
                    SettingsRow(
                        icon: "arrow.clockwise.circle.fill",
                        iconColor: .red,
                        title: "Launch at Login",
                        subtitle: "Opens automatically when your Mac starts up",
                        onTap: { isLaunchEnabled.toggle() }
                    ) {
                        Toggle("", isOn: $isLaunchEnabled)
                            .labelsHidden()
                            .onChange(of: isLaunchEnabled) { _, newValue in
                                if let error = LoginItemManager.shared.setEnabled(newValue) {
                                    isLaunchEnabled = !newValue
                                    loginItemError = error.localizedDescription
                                }
                            }
                    }

                    Divider().padding(.leading, 56)

                    SettingsRow(
                        icon: "arrow.down.circle.fill",
                        iconColor: .blue,
                        title: "Check for Updates",
                        subtitle: updateRowSubtitle
                    ) {
                        HStack(spacing: 8) {
                            switch updateStatus {
                            case .idle:
                                Button("Check") { checkForUpdates() }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .transition(.opacity.combined(with: .scale))
                            case .checking:
                                HStack(spacing: 6) {
                                    ProgressView()
                                        .controlSize(.small)
                                        .scaleEffect(0.8)
                                    Text("Checking…")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                }
                                .transition(.opacity)
                            case .upToDate:
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                    Text("Up to date")
                                        .foregroundStyle(.green)
                                }
                                .font(.system(size: 12))
                                .transition(.opacity.combined(with: .scale))
                            case .available(let tag, let notes):
                                HStack(spacing: 6) {
                                    Button("Update to \(tag)") { openLatestRelease() }
                                        .buttonStyle(.borderedProminent)
                                        .controlSize(.small)
                                    if notes != nil {
                                        Button {
                                            withAnimation(.easeInOut(duration: 0.2)) {
                                                showChangelog.toggle()
                                            }
                                        } label: {
                                            Image(systemName: showChangelog ? "chevron.up" : "chevron.down")
                                                .font(.system(size: 10, weight: .semibold))
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                    }
                                }
                                .transition(.opacity.combined(with: .scale))
                            case .error(let msg):
                                HStack(spacing: 4) {
                                    Image(systemName: "exclamationmark.circle.fill")
                                        .foregroundStyle(.red)
                                    Text(msg)
                                        .foregroundStyle(.red)
                                        .lineLimit(1)
                                }
                                .font(.system(size: 11))
                                .transition(.opacity)
                            }
                        }
                        .animation(.easeInOut(duration: 0.2), value: updateStatus)
                    }

                    if case .available(_, let notes) = updateStatus, let notes, showChangelog {
                        ScrollView {
                            Text(notes)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                        }
                        .frame(maxHeight: 120)
                        .background(Color(.textBackgroundColor).opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.08)))
                        .padding(.top, 4)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }

                SettingsSection(title: "Menu Bar Icon") {
                    SettingsRow(
                        icon: "square.grid.2x2.fill",
                        iconColor: .purple,
                        title: "Icon Set",
                        subtitle: currentIconSetName
                    ) {
                        Button("Choose") { showIconSetPicker = true }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                    .sheet(isPresented: $showIconSetPicker) {
                        IconSetPickerView(selectedID: selectedIconSetID) { set in
                            applyIconSet(set)
                        }
                    }
                }

                SettingsSection(title: "Monitoring") {
                    SettingsRow(
                        icon: "clock.fill",
                        iconColor: .orange,
                        title: "Check Interval",
                        subtitle: "How often the app checks if you're connected"
                    ) {
                        HStack(spacing: 8) {
                            TextField("", text: $intervalText)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 56)
                                .multilineTextAlignment(.trailing)
                                .onChange(of: intervalText) { _, newValue in
                                    let digitsOnly = newValue.filter { $0.isNumber }
                                    if digitsOnly != newValue { intervalText = digitsOnly }
                                    if intervalInvalid { intervalInvalid = false }
                                }

                            Text("sec")
                                .foregroundStyle(.secondary)
                                .font(.system(size: 12))

                            if intervalSaved {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .font(.system(size: 16))
                                    .transition(.scale.combined(with: .opacity))
                            } else {
                                Button("Apply") { applyInterval() }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .transition(.opacity.combined(with: .scale))
                            }
                        }
                        .animation(.easeInOut(duration: 0.18), value: intervalSaved)
                    }

                    if intervalInvalid {
                        HStack(spacing: 0) {
                            Spacer().frame(width: 56)
                            HStack(spacing: 4) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 9))
                                Text("Minimum interval is 30 seconds")
                                    .font(.system(size: 10))
                            }
                            .foregroundStyle(.red)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                            Spacer()
                        }
                        .padding(.bottom, 4)
                        .animation(.easeInOut(duration: 0.18), value: intervalInvalid)
                    }

                    HStack(spacing: 0) {
                        Spacer().frame(width: 56)
                        HStack(spacing: 6) {
                            ForEach([("30s", 30.0), ("1m", 60.0), ("2m", 120.0), ("5m", 300.0)], id: \.1) { lbl, val in
                                Button {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        interval        = val
                                        intervalText    = formatInterval(val)
                                        intervalInvalid = false
                                    }
                                } label: {
                                    Text(lbl)
                                        .font(.system(size: 11, weight: .medium))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4)
                                        .background(
                                            RoundedRectangle(cornerRadius: 6)
                                                .fill(interval == val
                                                      ? Color.accentColor.opacity(0.15)
                                                      : Color.primary.opacity(0.07))
                                        )
                                        .foregroundStyle(interval == val ? Color.accentColor : .secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        Spacer()
                    }
                    .padding(.vertical, 10)

                    Divider().padding(.leading, 56)

                    SettingsRow(
                        icon: "target",
                        iconColor: .green,
                        title: "Ping URL",
                        subtitle: "The address the app visits to test your connection"
                    ) {
                        EmptyView()
                    }

                    HStack(spacing: 0) {
                        Spacer().frame(width: 56)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                TextField(ConnectivityChecker.defaultURLString, text: $pingURL)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 12, design: .monospaced))
                                    .onChange(of: pingURL) { _, _ in pingURLInvalid = false }

                                if pingURLSaved {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                        .font(.system(size: 16))
                                        .transition(.scale.combined(with: .opacity))
                                } else {
                                    Button("Apply") { applyPingURL() }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                        .transition(.opacity.combined(with: .scale))
                                }
                            }
                            .animation(.easeInOut(duration: 0.18), value: pingURLSaved)

                            if pingURLInvalid {
                                HStack(spacing: 4) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.system(size: 9))
                                    Text("Enter a valid URL")
                                        .font(.system(size: 10))
                                }
                                .foregroundStyle(.red)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        }
                        .padding(.trailing, 18)
                        .animation(.easeInOut(duration: 0.18), value: pingURLInvalid)
                    }
                    .padding(.bottom, 4)

                    HStack(spacing: 0) {
                        Spacer().frame(width: 56)
                        Button("Restore Default") { restoreDefaultPingURL() }
                            .buttonStyle(.plain)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .disabled(pingURL.isEmpty)
                            .opacity(pingURL.isEmpty ? 0.4 : 1)
                        Spacer()
                    }
                    .padding(.bottom, 12)
                }

                footerView
            }
            .padding(20)
        }
        .frame(width: 440)
        .scrollContentBackground(.hidden)
        .background(Color(.windowBackgroundColor))
        .onAppear {
            isLaunchEnabled = LoginItemManager.shared.isEnabled()
            intervalText    = formatInterval(interval)
            pingURL         = UserDefaults.standard.string(for: .pingURL) ?? ""
            resolveSelectedSet()

            if updateStatus == .idle, let cached = UpdateChecker.cachedResult {
                applyUpdateResult(cached, autoDismiss: false)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .settingsWindowDidBecomeKey)) { _ in
            isLaunchEnabled = LoginItemManager.shared.isEnabled()
            resolveSelectedSet()
        }
        .alert("Launch at Login Failed", isPresented: Binding(
            get: { loginItemError != nil },
            set: { if !$0 { loginItemError = nil } }
        )) {
            Button("OK", role: .cancel) { loginItemError = nil }
        } message: {
            if let msg = loginItemError { Text(msg) }
        }
    }

    // MARK: - Shared footer

    private var footerView: some View {
        HStack(spacing: 4) {
            Text(AppInfo.appName)
            Text("·")
            Text(AppInfo.fullVersionString)
        }
        .font(.system(size: 11))
        .foregroundStyle(.tertiary)
        .padding(.bottom, 4)
    }

    // MARK: - Saved feedback helper

    /// Briefly shows a ✓ confirmation by flipping `binding` to true, then back to false after `duration` seconds.
    private func showSavedFeedback(_ binding: Binding<Bool>, duration: Double = 2) {
        withAnimation { binding.wrappedValue = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            withAnimation { binding.wrappedValue = false }
        }
    }

    // MARK: - Interval helpers

    private func formatInterval(_ v: Double) -> String {
        v.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(v)) : String(v)
    }

    private func applyInterval() {
        let value = Double(intervalText) ?? 0
        guard value >= 30 else {
            withAnimation { intervalInvalid = true }
            return
        }
        intervalInvalid = false
        interval        = value
        UserDefaults.standard.set(value, for: .refreshInterval)
        AppState.shared.restart()
        showSavedFeedback($intervalSaved)
    }

    // MARK: - Ping URL helpers

    private func applyPingURL() {
        let trimmed = pingURL.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            let isValid = URL(string: trimmed).flatMap { url in
                url.scheme.map { ["http", "https"].contains($0) }
            } ?? false
            if !isValid {
                withAnimation { pingURLInvalid = true }
                return
            }
        }
        pingURLInvalid = false
        if trimmed.isEmpty {
            UserDefaults.standard.removeObject(for: .pingURL)
        } else {
            UserDefaults.standard.set(trimmed, for: .pingURL)
        }
        showSavedFeedback($pingURLSaved)
    }

    private func restoreDefaultPingURL() {
        UserDefaults.standard.removeObject(for: .pingURL)
        withAnimation { pingURL = "" }
        showSavedFeedback($pingURLSaved)
    }

    // MARK: - Update helpers

    private var updateRowSubtitle: String {
        let version = "Version \(AppInfo.marketingVersion) (Build \(AppInfo.buildVersion))"
        guard let date = lastCheckDate else { return version }
        return "\(version)\n\(formattedCheckDate(date))"
    }

    private func formattedCheckDate(_ date: Date) -> String {
        let calendar = Calendar.current
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "h:mm a"
        let timeString = timeFormatter.string(from: date)
        if calendar.isDateInToday(date) {
            return "Checked today at \(timeString)"
        } else if calendar.isDateInYesterday(date) {
            return "Checked yesterday at \(timeString)"
        } else {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "MMM d"
            return "Checked \(dateFormatter.string(from: date))"
        }
    }

    private func checkForUpdates() {
        withAnimation { updateStatus = .checking }
        UpdateChecker.check { result in
            let now = Date()
            UserDefaults.standard.set(now, for: .lastUpdateCheck)
            lastCheckDate = now
            withAnimation { applyUpdateResult(result, autoDismiss: true) }
        }
    }

    private func applyUpdateResult(_ result: UpdateChecker.UpdateResult, autoDismiss: Bool) {
        switch result {
        case .upToDate:
            updateStatus = .upToDate
            if autoDismiss {
                DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                    withAnimation { updateStatus = .idle }
                }
            }
        case .updateAvailable(let tag, let notes, let downloadURL, let pageURL):
            cachedUpdateURL = downloadURL ?? pageURL
            updateStatus = .available(tag: tag, notes: notes)
        case .error(let msg):
            updateStatus = .error(msg)
            if autoDismiss {
                DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                    withAnimation { updateStatus = .idle }
                }
            }
        }
    }

    private func openLatestRelease() {
        guard let url = cachedUpdateURL else { return }
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Section container

private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                content
            }
            .background(Color(.quaternarySystemFill))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.primary.opacity(0.09), lineWidth: 1)
            )
        }
    }
}

// MARK: - Reusable row

private struct SettingsRow<Control: View>: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    var onTap: (() -> Void)? = nil
    @ViewBuilder let control: Control

    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(iconColor)
                    .frame(width: 30, height: 30)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            control
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(onTap != nil && isHovered ? Color.primary.opacity(0.04) : Color.clear)
        .contentShape(Rectangle())
        .onHover { hovering in
            if onTap != nil { isHovered = hovering }
        }
        .onTapGesture { onTap?() }
    }
}
