import SwiftUI
import AppKit

// MARK: - Icon Set Model

struct IconSet: Identifiable {
    let id = UUID()
    let name: String
    let connectedSymbol:  String
    let blockedSymbol:    String
    let noNetworkSymbol:  String

    static let connectedColor:  NSColor = .systemGreen
    static let blockedColor:    NSColor = .systemYellow
    static let noNetworkColor:  NSColor = .systemRed

    func toSlots() -> (IconPreferences.Slot, IconPreferences.Slot, IconPreferences.Slot) {
        (
            IconPreferences.Slot(symbolName: connectedSymbol,  color: IconSet.connectedColor,  menuLabel: "", menuLabelEnabled: false),
            IconPreferences.Slot(symbolName: blockedSymbol,    color: IconSet.blockedColor,    menuLabel: "", menuLabelEnabled: false),
            IconPreferences.Slot(symbolName: noNetworkSymbol,  color: IconSet.noNetworkColor,  menuLabel: "", menuLabelEnabled: false)
        )
    }
}

// MARK: - Predefined Sets

let iconSets: [IconSet] = [
    IconSet(name: "WiFi",    connectedSymbol: "wifi",                              blockedSymbol: "wifi",                             noNetworkSymbol: "wifi.slash"),
    IconSet(name: "Lock",    connectedSymbol: "lock.open.fill",                    blockedSymbol: "lock.fill",                        noNetworkSymbol: "lock.slash"),
    IconSet(name: "Bolt",    connectedSymbol: "bolt.fill",                         blockedSymbol: "bolt.fill",                        noNetworkSymbol: "bolt.slash"),
    IconSet(name: "Signals", connectedSymbol: "antenna.radiowaves.left.and.right", blockedSymbol: "dot.radiowaves.left.and.right",     noNetworkSymbol: "wifi.slash"),
    IconSet(name: "Globe",   connectedSymbol: "globe",                             blockedSymbol: "globe",                            noNetworkSymbol: "wifi.slash"),
    IconSet(name: "Minimal", connectedSymbol: "circle.fill",                       blockedSymbol: "circle.fill",                      noNetworkSymbol: "circle.fill"),
    IconSet(name: "Eye",     connectedSymbol: "eye.fill",                          blockedSymbol: "eye.trianglebadge.exclamationmark", noNetworkSymbol: "eye.slash"),
    IconSet(name: "Cloud",   connectedSymbol: "cloud.fill",                        blockedSymbol: "cloud",                            noNetworkSymbol: "cloud.fill"),
    IconSet(name: "Network", connectedSymbol: "network",                           blockedSymbol: "network.badge.shield.half.filled",  noNetworkSymbol: "network.slash"),
    IconSet(name: "Heart",   connectedSymbol: "heart.fill",                        blockedSymbol: "heart.fill",                       noNetworkSymbol: "heart.slash"),
    IconSet(name: "Bell",    connectedSymbol: "bell.fill",                         blockedSymbol: "bell.badge",                       noNetworkSymbol: "bell.slash"),
    IconSet(name: "Flag",    connectedSymbol: "flag.fill",                         blockedSymbol: "flag.fill",                        noNetworkSymbol: "flag.slash"),
    IconSet(name: "Power",   connectedSymbol: "power.circle.fill",                 blockedSymbol: "powerplug.fill",                   noNetworkSymbol: "power"),
    IconSet(name: "Hands",   connectedSymbol: "hand.thumbsup.fill",                blockedSymbol: "hand.raised.fill",                 noNetworkSymbol: "hand.thumbsdown.fill"),
    IconSet(name: "Star",    connectedSymbol: "star.fill",                         blockedSymbol: "star.leadinghalf.filled",           noNetworkSymbol: "star.slash.fill"),
]

// MARK: - Icon Set Picker (modal sheet)

struct IconSetPickerView: View {

    let selectedID: UUID?
    var onSelect: (IconSet) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {

            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Icon Set")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Choose an icon set for the menu bar.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                        .symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 12)
            .background(Color(.windowBackgroundColor))

            Divider()

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(iconSets.enumerated()), id: \.element.id) { index, set in
                        IconSetRow(set: set, isSelected: set.id == selectedID) {
                            onSelect(set)
                            dismiss()
                        }
                        if index < iconSets.count - 1 {
                            Divider().padding(.leading, 16)
                        }
                    }
                }
                .background(Color(.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.primary.opacity(0.09), lineWidth: 1)
                )
                .padding(16)
            }
            .scrollContentBackground(.hidden)
            .background(Color(.windowBackgroundColor))

            Divider()
            HStack(spacing: 4) {
                Image(systemName: "hand.tap")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                Text("Click a set to apply it immediately")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Color(.windowBackgroundColor))
        }
        .frame(width: 340, height: 500)
    }
}

// MARK: - Icon Set Row

struct IconSetRow: View {

    let set: IconSet
    let isSelected: Bool
    let onTap: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                Text(set.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: 64, alignment: .leading)

                Spacer()

                HStack(spacing: 12) {
                    IconPreviewCell(symbol: set.connectedSymbol,  color: Color(IconSet.connectedColor))
                    IconPreviewCell(symbol: set.blockedSymbol,    color: Color(IconSet.blockedColor))
                    IconPreviewCell(symbol: set.noNetworkSymbol,  color: Color(IconSet.noNetworkColor))
                }

                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 20)
                    .opacity(isSelected ? 1 : 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(hovered ? Color.accentColor.opacity(0.07) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

// MARK: - Single icon preview cell

struct IconPreviewCell: View {

    let symbol: String
    let color:  Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7)
                .fill(color.opacity(0.15))
                .frame(width: 32, height: 32)

            if NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(color)
            } else {
                Image(systemName: "questionmark")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
