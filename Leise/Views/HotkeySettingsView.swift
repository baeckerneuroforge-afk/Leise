import SwiftUI

// MARK: - Key caps

/// A shortcut drawn as key caps: fn with the globe, modifiers and short keys
/// as caps, longer names ("Right Option", mouse buttons) as one label.
struct ShortcutKeyCaps: View {
    let hotkey: UnifiedHotkey

    private enum Part: Hashable {
        case cap(label: String, systemImage: String?)
        case name(String)
    }

    /// Longer key names don't fit a small cap.
    private static let maximumCapLabelLength = 3

    private var parts: [Part] {
        if hotkey.mouseButton != nil || (hotkey.kind == .modifierCombo && !hotkey.modifierKeyCodes.isEmpty) {
            return [.name(Self.displayNameWithoutRepeat(hotkey))]
        }
        if hotkey.isFn {
            return [.cap(label: "fn", systemImage: "globe")]
        }

        var parts: [Part] = []
        let flags = NSEvent.ModifierFlags(rawValue: hotkey.modifierFlags)
        if flags.contains(.function) { parts.append(.cap(label: "fn", systemImage: "globe")) }
        if flags.contains(.control) { parts.append(.cap(label: "⌃", systemImage: nil)) }
        if flags.contains(.option) { parts.append(.cap(label: "⌥", systemImage: nil)) }
        if flags.contains(.shift) { parts.append(.cap(label: "⇧", systemImage: nil)) }
        if flags.contains(.command) { parts.append(.cap(label: "⌘", systemImage: nil)) }

        if hotkey.kind != .modifierCombo {
            let key = HotkeyService.keyName(for: hotkey.keyCode)
            parts.append(key.count <= Self.maximumCapLabelLength ? .cap(label: key, systemImage: nil) : .name(key))
        }
        return parts
    }

    var body: some View {
        HStack(spacing: LeiseSpacing.xs) {
            ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                switch part {
                case let .cap(label, systemImage):
                    KeyCap(label: label, systemImage: systemImage)
                case let .name(name):
                    KeyNameLabel(name: name)
                }
            }
            if hotkey.isDoubleTap {
                Text(String(localized: "twice"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(HotkeyService.displayName(for: hotkey))
    }

    private static func displayNameWithoutRepeat(_ hotkey: UnifiedHotkey) -> String {
        let name = HotkeyService.displayName(for: hotkey)
        return hotkey.isDoubleTap && name.hasSuffix(" x2") ? String(name.dropLast(3)) : name
    }
}

/// A key name that is too long for a cap, drawn with the same edge.
private struct KeyNameLabel: View {
    let name: String

    var body: some View {
        Text(name)
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, LeiseSpacing.s)
            .padding(.vertical, LeiseSpacing.xs)
            .background {
                RoundedRectangle(cornerRadius: LeiseRadius.control, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: LeiseRadius.control, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
                    )
            }
    }
}

// MARK: - Assignment

@MainActor
enum HotkeyAssignment {
    /// Adds `hotkey` to `slot` (or replaces `existing`), taking it away from
    /// any other slot first. A duplicate inside the same slot is ignored.
    static func assign(
        _ hotkey: UnifiedHotkey,
        to slot: HotkeySlotType,
        replacing existing: UnifiedHotkey? = nil,
        dictation: DictationViewModel
    ) {
        if let existing, existing.conflicts(with: hotkey) {
            dictation.replaceHotkey(existing, with: hotkey, for: slot)
            return
        }

        let duplicatesInSlot = dictation.hotkeys(for: slot).contains { candidate in
            if let existing, candidate == existing { return false }
            return candidate.conflicts(with: hotkey)
        }
        guard !duplicatesInSlot else { return }

        if let conflict = dictation.isHotkeyAssigned(hotkey, excluding: slot) {
            dictation.removeConflictingHotkey(hotkey, for: conflict)
        }

        if let existing {
            dictation.replaceHotkey(existing, with: hotkey, for: slot)
        } else {
            dictation.addHotkey(hotkey, for: slot)
        }
    }
}

// MARK: - Diktat › Tastenkürzel › Diktat

/// The one shortcut most people need: hold to talk, tap to toggle.
struct DictationShortcutRow: View {
    @ObservedObject var dictation: DictationViewModel

    private var hotkeys: [UnifiedHotkey] {
        _ = dictation.hotkeyLabelsVersion
        return dictation.hotkeys(for: .hybrid)
    }

    var body: some View {
        LabeledContent {
            controls
        } label: {
            SettingsRowLabel(
                title: SettingsRow.dictationShortcut.title,
                subtitle: String(localized: "Hold: speak as long as you hold. Tap: starts and stops.")
            )
        }
        .settingsRow(.dictationShortcut)
    }

    @ViewBuilder
    private var controls: some View {
        let assigned = self.hotkeys
        if assigned.count > 1 {
            HotkeyChips(slot: .hybrid, hotkeys: assigned, title: SettingsRow.dictationShortcut.title, dictation: dictation)
        } else {
            HStack(spacing: LeiseSpacing.m) {
                if let hotkey = assigned.first {
                    ShortcutKeyCaps(hotkey: hotkey)
                } else {
                    Text(String(localized: "Not set"))
                        .foregroundStyle(.secondary)
                }
                HotkeyRecorderView(
                    label: "",
                    title: SettingsRow.dictationShortcut.title,
                    presentation: .pushButton(title: assigned.isEmpty
                        ? String(localized: "Set…")
                        : String(localized: "Change…")),
                    onRecord: { newHotkey in
                        HotkeyAssignment.assign(newHotkey, to: .hybrid, replacing: assigned.first, dictation: dictation)
                    },
                    onClear: {}
                )
            }
        }
    }
}

// MARK: - Diktat › Tastenkürzel › Weitere Tastenkürzel

struct MoreShortcutsGroup: View {
    @ObservedObject var dictation: DictationViewModel

    @State private var isExpanded = false
    @Environment(\.settingsHighlightedRow) private var highlightedRow

    private static let slots: [(slot: HotkeySlotType, title: String, info: String)] = [
        (
            .pushToTalk,
            String(localized: "Hold only (push-to-talk)"),
            String(localized: "Speak while you hold the keys. Letting go ends the dictation.")
        ),
        (
            .toggle,
            String(localized: "Toggle only"),
            String(localized: "Press once to start, press again to stop.")
        ),
        (
            .recorderToggle,
            String(localized: "Start recording"),
            String(localized: "Starts and stops a recording under Transcribe.")
        ),
        (
            .recentTranscriptions,
            String(localized: "Recent transcriptions"),
            String(localized: "Shows your latest transcriptions. Return inserts one into the front app.")
        ),
        (
            .copyLastTranscription,
            String(localized: "Copy last transcription"),
            String(localized: "Copies your latest transcription to the clipboard.")
        ),
    ]

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ForEach(Self.slots, id: \.slot) { entry in
                HotkeySlotRow(slot: entry.slot, title: entry.title, info: entry.info, dictation: dictation)
            }
        } label: {
            HStack {
                Text(SettingsRow.moreShortcuts.title)
                Spacer()
                Text(Self.slots.count.formatted())
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
        .settingsRow(.moreShortcuts)
        .onChange(of: highlightedRow) { _, row in
            if row == .moreShortcuts {
                withLeiseAnimation(LeiseMotion.shape) { isExpanded = true }
            }
        }
    }
}

/// One shortcut slot: its assigned shortcuts as chips, or "Festlegen …".
struct HotkeySlotRow: View {
    let slot: HotkeySlotType
    let title: String
    var info: String?
    @ObservedObject var dictation: DictationViewModel

    private var hotkeys: [UnifiedHotkey] {
        _ = dictation.hotkeyLabelsVersion
        return dictation.hotkeys(for: slot)
    }

    var body: some View {
        LabeledContent {
            let assigned = self.hotkeys
            if assigned.isEmpty {
                HotkeyRecorderView(
                    label: "",
                    title: title,
                    presentation: .pushButton(title: String(localized: "Set…")),
                    onRecord: { HotkeyAssignment.assign($0, to: slot, dictation: dictation) },
                    onClear: {}
                )
            } else {
                HotkeyChips(slot: slot, hotkeys: assigned, title: title, dictation: dictation)
            }
        } label: {
            SettingsRowLabel(title: title, info: info)
        }
    }
}

/// Assigned shortcuts as chips: click one to record a replacement, ⓧ to
/// remove it, + to add another.
private struct HotkeyChips: View {
    let slot: HotkeySlotType
    let hotkeys: [UnifiedHotkey]
    let title: String
    @ObservedObject var dictation: DictationViewModel

    var body: some View {
        HStack(spacing: LeiseSpacing.s) {
            ForEach(hotkeys, id: \.self) { hotkey in
                HotkeyRecorderView(
                    label: HotkeyService.displayName(for: hotkey),
                    title: title,
                    presentation: .compactChip,
                    onRecord: { HotkeyAssignment.assign($0, to: slot, replacing: hotkey, dictation: dictation) },
                    onClear: { dictation.removeHotkey(hotkey, for: slot) }
                )
            }
            HotkeyRecorderView(
                label: "",
                title: String(localized: "Add Shortcut"),
                presentation: .iconButton(systemName: "plus.circle"),
                onRecord: { HotkeyAssignment.assign($0, to: slot, dictation: dictation) },
                onClear: {}
            )
        }
    }
}

// MARK: - Secure input

/// Shown while another app holds Secure Input, which blocks fn and
/// modifier-only shortcuts.
struct SecureInputNotice: View {
    let owner: String

    var body: some View {
        Label {
            SettingsRowLabel(
                title: String(localized: "Secure Input is on in \(owner)"),
                info: String(localized: "While an app asks for a password, macOS blocks shortcuts that use only fn or modifier keys. Shortcuts with a regular key keep working.")
            )
        } icon: {
            Image(systemName: "lock.shield")
                .foregroundStyle(.secondary)
        }
    }
}
