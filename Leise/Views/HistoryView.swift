import AppKit
import SwiftUI

/// Verlauf: every dictation, newest first, with failed ones inline so they
/// can be transcribed again. Retention lives in the toolbar.
struct HistoryView: View {
    @ObservedObject private var viewModel = ServiceContainer.shared.historyViewModel
    @ObservedObject private var recovery = ServiceContainer.shared.dictationRecoveryViewModel
    @ObservedObject private var modelManager = ServiceContainer.shared.modelManagerService
    @AppStorage(UserDefaultsKeys.historyEnabled) private var historyEnabled = true
    @AppStorage(UserDefaultsKeys.historyRetentionDays) private var historyRetentionDays = 0
    @AppStorage(UserDefaultsKeys.saveAudioWithHistory) private var saveAudioWithHistory = false
    @Environment(\.settingsFocusRequest) private var focusRequest

    @State private var selection: Set<HistoryItemID> = []
    @State private var showsDeleteVisibleConfirmation = false

    private static let listWidth: CGFloat = 270

    var body: some View {
        Group {
            if isEmpty && !hasFiltersOrSearch {
                // Nothing to list yet: one calm message instead of an empty split.
                listEmptyState
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 0) {
                    listColumn
                        .frame(width: Self.listWidth)
                    Divider()
                    detailColumn
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .navigationTitle(SettingsTab.history.title)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                filterMenu
                retentionMenu
            }
        }
        .onAppear(perform: restoreSelection)
        .onChange(of: selection) { _, newSelection in
            let recordIDs = Set(newSelection.compactMap(\.recordID))
            if viewModel.selectedRecordIDs != recordIDs {
                viewModel.selectedRecordIDs = recordIDs
            }
        }
        .onChange(of: viewModel.selectedRecordIDs) { _, recordIDs in
            let current = Set(selection.compactMap(\.recordID))
            guard current != recordIDs else { return }
            selection = Set(recordIDs.map(HistoryItemID.record))
        }
        .onChange(of: recovery.lastSavedHistoryRecordID) { _, recordID in
            guard let recordID else { return }
            selection = [.record(recordID)]
            AccessibilityNotification.Announcement(String(localized: "Recording transcribed")).post()
        }
        .task(id: focusRequest?.id) {
            guard focusRequest?.row == .recovery, let newest = recovery.recoveries.first else { return }
            clearFilters()
            selection = [.recovery(newest.id)]
        }
        .confirmationDialog(
            String(localized: "Delete Entries"),
            isPresented: $showsDeleteVisibleConfirmation,
            titleVisibility: .visible
        ) {
            Button(String(localized: "Delete"), role: .destructive) {
                withLeiseAnimation(LeiseMotion.ui) {
                    viewModel.deleteAllVisible()
                }
            }
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: {
            if hasFiltersOrSearch {
                Text(String(localized: "Delete \(viewModel.visibleRecordCount) entries matching current filters?"))
            } else {
                Text(String(localized: "Delete all \(viewModel.visibleRecordCount) entries? This cannot be undone."))
            }
        }
    }

    // MARK: Items

    private var hasFiltersOrSearch: Bool {
        viewModel.hasActiveFilters || !viewModel.searchQuery.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Failed recordings carry no app or text, so filters and search hide them.
    private var visibleRecoveries: [DictationRecoveryViewModel.RecoveryItem] {
        hasFiltersOrSearch ? [] : recovery.recoveries
    }

    private var sections: [HistoryListSection] {
        HistoryListSection.merge(sections: viewModel.groupedSections, recoveries: visibleRecoveries)
    }

    private var isEmpty: Bool {
        viewModel.groupedSections.isEmpty && visibleRecoveries.isEmpty
    }

    private func restoreSelection() {
        if !viewModel.selectedRecordIDs.isEmpty {
            selection = Set(viewModel.selectedRecordIDs.map(HistoryItemID.record))
        } else if selection.isEmpty, let first = sections.first?.items.first {
            selection = [first.id]
        }
    }

    private func clearFilters() {
        viewModel.clearAllFilters()
    }

    // MARK: List

    private var listColumn: some View {
        VStack(spacing: 0) {
            NativeSearchField(text: $viewModel.searchQuery, prompt: String(localized: "Search History"))
                .padding(.horizontal, LeiseSpacing.m)
                .padding(.vertical, LeiseSpacing.s)

            if !historyEnabled {
                LabeledContent {
                    Button(String(localized: "Turn On")) { historyEnabled = true }
                        .controlSize(.small)
                } label: {
                    Text(String(localized: "New dictations aren’t saved."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, LeiseSpacing.m)
                .padding(.bottom, LeiseSpacing.s)
            }

            if isEmpty {
                listEmptyState
                    .frame(maxHeight: .infinity)
            } else {
                List(selection: $selection) {
                    ForEach(sections) { section in
                        Section(section.group.displayName) {
                            ForEach(section.items) { item in
                                row(for: item)
                                    .tag(item.id)
                            }
                        }
                    }
                }
                .listStyle(.inset)
                .onDeleteCommand(perform: deleteSelectedRecords)

                Divider()
                Text(countText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, LeiseSpacing.m)
                    .padding(.vertical, LeiseSpacing.s)
            }
        }
    }

    private var countText: String {
        let count = viewModel.visibleRecordCount
        if hasFiltersOrSearch {
            return String(localized: "\(count) of \(viewModel.totalRecords) entries")
        }
        return count == 1 ? String(localized: "1 entry") : String(localized: "\(count) entries")
    }

    @ViewBuilder
    private var listEmptyState: some View {
        if hasFiltersOrSearch {
            ContentUnavailableView {
                Label(String(localized: "No Matches"), systemImage: "magnifyingglass")
            } description: {
                Text(String(localized: "No entry matches the search or filter."))
            } actions: {
                Button(String(localized: "Clear Filters"), action: clearFilters)
            }
        } else if historyEnabled {
            ContentUnavailableView {
                Label(String(localized: "No History Yet"), systemImage: SettingsTab.history.systemImage)
            } description: {
                Text(String(localized: "Dictate into any app. Your dictations appear here so you can copy or fix them later."))
            }
        } else {
            ContentUnavailableView {
                Label(String(localized: "History Is Off"), systemImage: SettingsTab.history.systemImage)
            } description: {
                Text(String(localized: "Leise forgets dictations once they are inserted."))
            } actions: {
                Button(String(localized: "Turn On History")) { historyEnabled = true }
            }
        }
    }

    @ViewBuilder
    private func row(for item: HistoryListItem) -> some View {
        switch item {
        case .record(let record):
            HistoryRecordRow(record: record, showsDate: HistoryDateGroup.containing(record.timestamp) == .older)
                .contextMenu { recordContextMenu(for: record) }
        case .recovery(let recoveryItem):
            RecoveryListRow(item: recoveryItem)
        }
    }

    @ViewBuilder
    private func recordContextMenu(for record: TranscriptionRecord) -> some View {
        let isPartOfSelection = viewModel.selectedRecordIDs.count > 1 && viewModel.selectedRecordIDs.contains(record.id)
        if isPartOfSelection {
            let count = viewModel.selectedRecordIDs.count
            Button(String(localized: "Copy")) {
                viewModel.copyToClipboard(viewModel.selectedRecords.map(\.finalText).joined(separator: "\n\n"))
            }
            HistoryExportMenu(title: String(localized: "Export \(count) Entries")) { format in
                viewModel.exportSelectedRecords(format: format)
            }
            Divider()
            Button(String(localized: "Delete \(count) entries"), role: .destructive) {
                withLeiseAnimation(LeiseMotion.ui) { viewModel.deleteSelectedRecords() }
            }
        } else {
            Button(String(localized: "Copy")) {
                viewModel.copyToClipboard(record.finalText)
            }
            HistoryExportMenu(title: String(localized: "Export")) { format in
                viewModel.exportRecord(record, format: format)
            }
            Divider()
            Button(String(localized: "Delete"), role: .destructive) {
                withLeiseAnimation(LeiseMotion.ui) { viewModel.deleteRecord(record) }
            }
        }
    }

    private func deleteSelectedRecords() {
        guard !viewModel.selectedRecordIDs.isEmpty else { return }
        withLeiseAnimation(LeiseMotion.ui) {
            viewModel.deleteSelectedRecords()
        }
    }

    // MARK: Detail

    @ViewBuilder
    private var detailColumn: some View {
        if selection.count > 1 {
            MultipleSelectionDetail(viewModel: viewModel, count: selection.count)
        } else if let id = selection.first,
                  case .recovery(let recoveryID) = id,
                  let item = recovery.recoveries.first(where: { $0.id == recoveryID }) {
            ScrollView {
                RecoveryDetailView(item: item, recovery: recovery, modelManager: modelManager)
                    .padding(LeiseSpacing.xxl)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else if let record = viewModel.selectedRecord {
            RecordDetailView(record: record, viewModel: viewModel)
                .id(record.id)
        } else if !isEmpty {
            ContentUnavailableView(
                String(localized: "No Entry Selected"),
                systemImage: "text.alignleft",
                description: Text(String(localized: "Choose a dictation on the left to read, copy or edit it."))
            )
        } else {
            Color.clear
        }
    }

    // MARK: Toolbar

    private var appFilter: Binding<String> {
        Binding(
            get: { viewModel.selectedAppFilter ?? "" },
            set: { viewModel.selectedAppFilter = $0.isEmpty ? nil : $0 }
        )
    }

    private var filterTitle: String {
        let app = viewModel.availableApps.first { $0.bundleId == viewModel.selectedAppFilter }?.name
            ?? String(localized: "All Apps")
        guard viewModel.selectedTimeRange != .all else { return app }
        return "\(app) · \(viewModel.selectedTimeRange.displayName)"
    }

    private var filterMenu: some View {
        Menu {
            Picker(String(localized: "App"), selection: appFilter) {
                Text(String(localized: "All Apps")).tag("")
                if !viewModel.availableApps.isEmpty {
                    Divider()
                    ForEach(viewModel.availableApps) { app in
                        Text(app.name).tag(app.bundleId)
                    }
                }
            }
            .pickerStyle(.inline)

            Picker(String(localized: "Period"), selection: $viewModel.selectedTimeRange) {
                ForEach(HistoryTimeRange.allCases) { range in
                    Text(range.displayName).tag(range)
                }
            }
            .pickerStyle(.inline)

            if viewModel.hasActiveFilters {
                Divider()
                Button(String(localized: "Clear Filters"), action: clearFilters)
            }
        } label: {
            Label(
                filterTitle,
                systemImage: viewModel.hasActiveFilters
                    ? "line.3.horizontal.decrease.circle.fill"
                    : "line.3.horizontal.decrease.circle"
            )
            .labelStyle(.titleAndIcon)
        }
        .help(String(localized: "Filter History"))
        .accessibilityLabel(String(localized: "Filter: \(filterTitle)"))
    }

    private var retentionTitle: String {
        guard historyEnabled else { return String(localized: "History off") }
        switch historyRetentionDays {
        case 0: return String(localized: "Keep forever")
        default: return String(localized: "Keep \(historyRetentionDays) days")
        }
    }

    private var retentionMenu: some View {
        Menu {
            Toggle(String(localized: "Save history"), isOn: $historyEnabled)
            Toggle(String(localized: "Save audio with dictations"), isOn: $saveAudioWithHistory)
                .disabled(!historyEnabled)

            Picker(String(localized: "Delete Automatically"), selection: $historyRetentionDays) {
                Text(String(localized: "Never")).tag(0)
                Text(String(localized: "After 30 days")).tag(30)
                Text(String(localized: "After 60 days")).tag(60)
                Text(String(localized: "After 90 days")).tag(90)
                Text(String(localized: "After 180 days")).tag(180)
            }
            .disabled(!historyEnabled)

            Divider()
            Button(hasFiltersOrSearch
                ? String(localized: "Delete Visible Entries…")
                : String(localized: "Delete All Entries…"), role: .destructive) {
                showsDeleteVisibleConfirmation = true
            }
            .disabled(viewModel.filteredRecords.isEmpty)
        } label: {
            Label(retentionTitle, systemImage: "calendar.badge.clock")
                .labelStyle(.titleAndIcon)
        }
        .help(String(localized: "History retention"))
        .accessibilityLabel(String(localized: "History retention: \(retentionTitle)"))
    }
}

// MARK: - List model

enum HistoryItemID: Hashable {
    case record(UUID)
    case recovery(String)

    var recordID: UUID? {
        if case .record(let id) = self { return id }
        return nil
    }
}

enum HistoryListItem: Identifiable {
    case record(TranscriptionRecord)
    case recovery(DictationRecoveryViewModel.RecoveryItem)

    var id: HistoryItemID {
        switch self {
        case .record(let record): .record(record.id)
        case .recovery(let item): .recovery(item.id)
        }
    }

    var date: Date {
        switch self {
        case .record(let record): record.timestamp
        case .recovery(let item): item.recordedAt
        }
    }
}

struct HistoryListSection: Identifiable {
    let group: HistoryDateGroup
    let items: [HistoryListItem]

    var id: HistoryDateGroup { group }

    /// Records and failed recordings in the same day sections, newest first.
    static func merge(
        sections: [HistorySection],
        recoveries: [DictationRecoveryViewModel.RecoveryItem],
        now: Date = Date()
    ) -> [HistoryListSection] {
        var buckets: [HistoryDateGroup: [HistoryListItem]] = [:]
        for section in sections {
            buckets[section.group, default: []].append(contentsOf: section.records.map(HistoryListItem.record))
        }
        for item in recoveries {
            buckets[HistoryDateGroup.containing(item.recordedAt, now: now), default: []].append(.recovery(item))
        }
        return HistoryDateGroup.allCases.compactMap { group in
            guard let items = buckets[group], !items.isEmpty else { return nil }
            return HistoryListSection(group: group, items: items.sorted { $0.date > $1.date })
        }
    }
}

// MARK: - Rows

private struct HistoryRecordRow: View {
    let record: TranscriptionRecord
    var showsDate = false

    private var timeText: String {
        showsDate
            ? record.timestamp.formatted(.dateTime.day().month(.abbreviated).hour().minute())
            : record.timestamp.formatted(date: .omitted, time: .shortened)
    }

    var body: some View {
        HStack(alignment: .top, spacing: LeiseSpacing.m) {
            AppGlyph(bundleIdentifier: record.appBundleIdentifier, size: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(record.preview)
                    .lineLimit(2)
                Text([timeText, HistoryDuration.format(record.durationSeconds), record.appDomain]
                    .compactMap { $0 }
                    .joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(record.preview)
        .accessibilityValue([record.appName, timeText].compactMap { $0 }.joined(separator: ", "))
    }
}

// MARK: - Detail

private struct HistoryExportMenu: View {
    let title: String
    let export: (HistoryExportFormat) -> Void

    var body: some View {
        Menu(title) {
            Button { export(.markdown) } label: { Text(verbatim: "Markdown (.md)") }
            Button(String(localized: "Plain Text (.txt)")) { export(.plainText) }
            Button { export(.json) } label: { Text(verbatim: "JSON (.json)") }
        }
    }
}

private struct MultipleSelectionDetail: View {
    @ObservedObject var viewModel: HistoryViewModel
    let count: Int

    var body: some View {
        ContentUnavailableView {
            Label(String(localized: "\(count) entries selected"), systemImage: "checkmark.circle")
        } description: {
            Text(String(localized: "Copy, export or delete them together."))
        } actions: {
            HStack {
                Button(String(localized: "Copy")) {
                    viewModel.copyToClipboard(viewModel.selectedRecords.map(\.finalText).joined(separator: "\n\n"))
                }
                HistoryExportMenu(title: String(localized: "Export")) { format in
                    viewModel.exportSelectedRecords(format: format)
                }
                .fixedSize()
                Button(String(localized: "Delete"), role: .destructive) {
                    withLeiseAnimation(LeiseMotion.ui) { viewModel.deleteSelectedRecords() }
                }
            }
        }
    }
}

private struct RecordDetailView: View {
    let record: TranscriptionRecord
    @ObservedObject var viewModel: HistoryViewModel

    @State private var didCopy = false
    @Environment(\.colorSchemeContrast) private var contrast

    /// How long "Kopiert" stays on the copy button.
    private static let copiedHold: Duration = .milliseconds(1300)

    private enum TextMode: Hashable {
        case result
        case original
        case changes
    }

    @State private var textMode: TextMode = .result

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LeiseSpacing.l) {
                if viewModel.isEditing {
                    editor
                } else {
                    if record.wasPostProcessed {
                        Picker(String(localized: "Text"), selection: $textMode) {
                            Text(String(localized: "Result")).tag(TextMode.result)
                            Text(String(localized: "Original")).tag(TextMode.original)
                            Text(String(localized: "Changes")).tag(TextMode.changes)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                    }
                    textBody
                }

                if viewModel.showCorrectionBanner, !viewModel.correctionSuggestions.isEmpty {
                    learnedCorrections
                }

                metadata

                if let audioURL = viewModel.audioFileURL(for: record) {
                    AudioPlaybackBar(audioURL: audioURL, playbackService: viewModel.audioPlaybackService)
                }

                if !viewModel.isEditing {
                    actions
                }
            }
            .padding(LeiseSpacing.xxl)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onDisappear {
            viewModel.cancelEditing()
            viewModel.audioPlaybackService.stop()
        }
        .task(id: didCopy) {
            guard didCopy else { return }
            try? await Task.sleep(for: Self.copiedHold)
            withLeiseAnimation(LeiseMotion.micro) { didCopy = false }
        }
    }

    @ViewBuilder
    private var textBody: some View {
        switch textMode {
        case .result:
            selectableText(record.finalText)
        case .original:
            selectableText(record.rawText)
        case .changes:
            Text(diffAttributedString(segments: viewModel.diffSegments(for: record)))
                .font(.title3)
                .lineSpacing(LeiseSpacing.xs)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func selectableText(_ text: String) -> some View {
        Text(text)
            .font(.title3)
            .lineSpacing(LeiseSpacing.xs)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var editor: some View {
        VStack(alignment: .trailing, spacing: LeiseSpacing.m) {
            TextEditor(text: $viewModel.editedText)
                .font(.title3)
                .scrollContentBackground(.hidden)
                .padding(LeiseSpacing.s)
                .frame(minHeight: 160)
                .background(
                    Color(nsColor: .textBackgroundColor),
                    in: RoundedRectangle(cornerRadius: LeiseRadius.group, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: LeiseRadius.group, style: .continuous)
                        .strokeBorder(Color.primary.opacity(contrast == .increased ? 0.35 : 0.15), lineWidth: 0.5)
                )
                .accessibilityLabel(String(localized: "Dictated text"))
            HStack {
                Button(String(localized: "Cancel")) {
                    viewModel.cancelEditing()
                }
                .keyboardShortcut(.cancelAction)
                Button(String(localized: "Save")) {
                    viewModel.saveEditing()
                }
                .keyboardShortcut(.defaultAction)
            }
            Text(String(localized: "Words you correct here are added to the dictionary as corrections."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var learnedCorrections: some View {
        VStack(alignment: .leading, spacing: LeiseSpacing.xs) {
            HStack {
                Label(String(localized: "Corrections added to dictionary"), systemImage: "book.badge.checkmark")
                    .font(.headline)
                Spacer()
                Button {
                    viewModel.dismissCorrectionBanner()
                } label: {
                    Image(systemName: "xmark")
                        .imageScale(.small)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(String(localized: "Hide"))
            }
            ForEach(viewModel.correctionSuggestions) { suggestion in
                HStack(spacing: LeiseSpacing.xs) {
                    Text(suggestion.original)
                        .foregroundStyle(.secondary)
                    Image(systemName: "arrow.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                    Text(suggestion.replacement)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(LeiseSpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LeiseColor.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: LeiseRadius.group, style: .continuous))
    }

    private var metadata: some View {
        FlowLayout(spacing: LeiseSpacing.s) {
            if let appName = record.appName {
                MetadataChip {
                    AppGlyph(bundleIdentifier: record.appBundleIdentifier, size: 14)
                    Text(appName)
                }
            }
            if let domain = record.appDomain {
                MetadataChip { Text(domain) }
            }
            MetadataChip {
                Text(record.timestamp.formatted(date: .abbreviated, time: .shortened))
            }
            MetadataChip {
                Text(record.wordsCount == 1 ? String(localized: "1 word") : String(localized: "\(record.wordsCount) words"))
            }
            MetadataChip {
                Text(HistoryDuration.format(record.durationSeconds))
            }
            MetadataChip {
                Text(record.modelUsed ?? record.engineUsed)
            }
            if let language = record.language {
                MetadataChip { Text(localizedAppLanguageName(for: language)) }
            }
            if record.wasManuallyEdited {
                MetadataChip {
                    Image(systemName: "pencil")
                    Text(String(localized: "Edited"))
                }
            }
        }
    }

    private var actions: some View {
        HStack(spacing: LeiseSpacing.s) {
            Button {
                viewModel.copyToClipboard(record.finalText)
                withLeiseAnimation(LeiseMotion.micro) { didCopy = true }
                AccessibilityNotification.Announcement(String(localized: "Copied")).post()
            } label: {
                Label(
                    didCopy ? String(localized: "Copied") : String(localized: "Copy"),
                    systemImage: didCopy ? "checkmark" : "doc.on.doc"
                )
                .contentTransition(.symbolEffect(.replace))
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])

            Button {
                viewModel.startEditing()
            } label: {
                Label(String(localized: "Edit"), systemImage: "pencil")
            }

            HistoryExportMenu(title: String(localized: "Export")) { format in
                viewModel.exportRecord(record, format: format)
            }
            .fixedSize()

            Button(role: .destructive) {
                withLeiseAnimation(LeiseMotion.ui) { viewModel.deleteRecord(record) }
            } label: {
                Label(String(localized: "Delete"), systemImage: "trash")
            }
        }
    }

    private func diffAttributedString(segments: [DiffSegment]) -> AttributedString {
        var result = AttributedString()
        for (index, segment) in segments.enumerated() {
            let word: String
            switch segment {
            case .unchanged(let text), .removed(let text), .added(let text):
                word = text
            }

            var attributed = AttributedString(word)
            switch segment {
            case .unchanged:
                break
            case .removed:
                attributed.foregroundColor = .secondary
                attributed.strikethroughStyle = .single
            case .added:
                attributed.foregroundColor = LeiseColor.tint
                attributed.underlineStyle = .single
            }
            result += attributed

            if index < segments.count - 1 {
                result += AttributedString(" ")
            }
        }
        return result
    }
}

private struct MetadataChip<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: LeiseSpacing.xs) {
            content
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .padding(.horizontal, LeiseSpacing.s)
        .padding(.vertical, LeiseSpacing.xs)
        .background(.quaternary.opacity(0.6), in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Audio

private struct AudioPlaybackBar: View {
    let audioURL: URL
    @ObservedObject var playbackService: AudioPlaybackService

    var body: some View {
        HStack(spacing: LeiseSpacing.m) {
            Button {
                playbackService.togglePlayPause(url: audioURL)
            } label: {
                Image(systemName: playbackService.isPlaying ? "pause.fill" : "play.fill")
                    .foregroundStyle(.white)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 30, height: 30)
                    .background(LeiseColor.tintFill, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(playbackService.isPlaying ? String(localized: "Pause") : String(localized: "Play"))

            if playbackService.duration > 0 {
                Slider(
                    value: Binding(
                        get: { playbackService.currentTime },
                        set: { playbackService.seek(to: $0) }
                    ),
                    in: 0...playbackService.duration
                )
                .controlSize(.small)
                .accessibilityLabel(String(localized: "Playback position"))

                Text(verbatim: "\(HistoryDuration.format(playbackService.currentTime)) / \(HistoryDuration.format(playbackService.duration))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            } else {
                Text(String(localized: "Audio"))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([audioURL])
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)
            .help(String(localized: "Show in Finder"))
            .accessibilityLabel(String(localized: "Show in Finder"))
        }
        .padding(.horizontal, LeiseSpacing.m)
        .padding(.vertical, LeiseSpacing.s)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: LeiseRadius.group, style: .continuous))
    }
}
