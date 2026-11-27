import AppKit
import Foundation

@MainActor
final class RecentTranscriptionPaletteHandler {
    private let paletteController: any SelectionPaletteControlling
    private let textInsertionService: TextInsertionService
    private let historyService: HistoryService
    private let recentTranscriptionStore: RecentTranscriptionStore
    var pasteboardProvider: () -> NSPasteboard = { .general }

    var onShowNotchFeedback: ((String, String, TimeInterval, Bool, String?) -> Void)?
    var getPreserveClipboard: (() -> Bool)?

    /// Wide enough for two lines of a typical dictation next to the app icon.
    static let panelWidth: CGFloat = 540
    static let titleLineLimit = 2

    init(
        textInsertionService: TextInsertionService,
        historyService: HistoryService,
        recentTranscriptionStore: RecentTranscriptionStore,
        paletteController: any SelectionPaletteControlling = SelectionPaletteController()
    ) {
        self.textInsertionService = textInsertionService
        self.historyService = historyService
        self.recentTranscriptionStore = recentTranscriptionStore
        self.paletteController = paletteController
    }

    func hide() {
        paletteController.hide()
    }

    func triggerSelection(currentState: DictationViewModel.State) {
        if paletteController.isVisible {
            paletteController.hide()
            return
        }

        guard currentState == .idle else { return }

        let entries = recentTranscriptionStore.mergedEntries(historyRecords: historyService.records)
        guard !entries.isEmpty else {
            onShowNotchFeedback?(
                String(localized: "No recent transcriptions"),
                "clock.arrow.circlepath",
                2.5,
                false,
                nil
            )
            return
        }

        let entriesByID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
        let now = Date()
        let items = entries.map { entry in
            SelectionPaletteItem(
                id: entry.id,
                title: entry.finalText,
                subtitle: appName(for: entry),
                iconSystemName: nil,
                searchTokens: [entry.appName, entry.appBundleIdentifier].compactMap { $0 },
                appBundleIdentifier: entry.appBundleIdentifier,
                detail: Self.timeLabel(for: entry.timestamp, relativeTo: now)
            )
        }

        paletteController.show(
            configuration: Self.configuration,
            items: items,
            onSelect: { [weak self] item in
                guard let self, let entry = entriesByID[item.id] else { return }
                Task { @MainActor in
                    await self.insert(entry)
                }
            },
            onCopy: { [weak self] item in
                guard let self, let entry = entriesByID[item.id] else { return }
                self.copy(entry)
            }
        )
    }

    static var configuration: SelectionPaletteConfiguration {
        SelectionPaletteConfiguration(
            panelWidth: panelWidth,
            panelHeight: .greatestFiniteMagnitude,
            titleLineLimit: titleLineLimit,
            searchPrompt: String(localized: "Search History"),
            searchAccessibilityLabel: String(localized: "Search recent transcriptions"),
            emptyStateTitle: String(localized: "No recent transcriptions"),
            noMatchesTitle: String(localized: "No matches"),
            footerHints: [
                SelectionPaletteHint(key: "↩", label: String(localized: "Insert")),
                SelectionPaletteHint(key: "⌘C", label: String(localized: "Copy")),
                SelectionPaletteHint(key: "esc", label: String(localized: "Close")),
            ]
        )
    }

    /// The time for today's entries, "Yesterday" or a date for older ones.
    static func timeLabel(for date: Date, relativeTo now: Date, calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        return relativeDayFormatter.string(from: date)
    }

    private static let relativeDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()

    private func insert(_ entry: RecentTranscriptionStore.Entry) async {
        do {
            _ = try await textInsertionService.insertText(
                entry.finalText,
                preserveClipboard: getPreserveClipboard?() ?? false,
                autoEnter: false
            )
            onShowNotchFeedback?(String(localized: "Text inserted"), "checkmark.circle.fill", 2.5, false, nil)
        } catch {
            onShowNotchFeedback?(error.localizedDescription, "xmark.circle.fill", 2.5, true, "recentTranscriptions")
        }
    }

    private func copy(_ entry: RecentTranscriptionStore.Entry) {
        let text = entry.finalText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let pasteboard = pasteboardProvider()
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        onShowNotchFeedback?(String(localized: "Copied to clipboard"), "doc.on.doc", 2.5, false, nil)
    }

    private func appName(for entry: RecentTranscriptionStore.Entry) -> String? {
        guard let name = entry.appName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
            return nil
        }
        return name
    }
}
