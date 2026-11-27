import LeiseCore
import SwiftUI

/// Wörterbuch: corrections, terms, filler words and term packs, switched in
/// the toolbar.
struct DictionarySettingsView: View {
    @Binding var section: DictionaryPageSection

    @ObservedObject private var viewModel = ServiceContainer.shared.dictionaryViewModel
    @ObservedObject private var termPackRegistryService = ServiceContainer.shared.termPackRegistryService
    @ObservedObject private var modelManager = ServiceContainer.shared.modelManagerService
    /// The filler-word component writes its list here on every edit.
    @AppStorage(DictionarySettingsView.fillerWordsKey) private var fillerWordsText = ""

    @State private var showsFillerWordsEditor = false
    @State private var showsEngineSettings = false

    /// `ComponentSettingsStore(namespace: "filler-words")`, key "words".
    static let fillerWordsKey = "component.filler-words.words"

    var body: some View {
        SettingsPage(.dictionary) {
            switch section {
            case .corrections:
                correctionsSection
            case .terms:
                termsSection
            case .fillerWords:
                fillerWordsSection
            case .termPacks:
                termPacksSections
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker(String(localized: "Section"), selection: $section) {
                    ForEach(DictionaryPageSection.allCases) { section in
                        Text(section.title).tag(section)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            ToolbarItem(placement: .primaryAction) {
                addMenu
            }
        }
        .sheet(isPresented: $viewModel.isEditing) {
            DictionaryEditorSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $showsFillerWordsEditor) {
            FillerWordsEditorSheet()
        }
        .sheet(isPresented: $showsEngineSettings, onDismiss: {
            // Vocabulary boosting changes don't publish an engine state change.
            modelManager.objectWillChange.send()
        }) {
            EngineSettingsSheet()
        }
        .alert(String(localized: "Error"), isPresented: Binding(
            get: { viewModel.error != nil },
            set: { if !$0 { viewModel.clearError() } }
        )) {
            Button(String(localized: "OK")) { viewModel.clearError() }
        } message: {
            Text(viewModel.error ?? "")
        }
        .alert(String(localized: "Import Complete"), isPresented: Binding(
            get: { viewModel.importMessage != nil },
            set: { if !$0 { viewModel.clearImportMessage() } }
        )) {
            Button(String(localized: "OK")) { viewModel.clearImportMessage() }
        } message: {
            Text(viewModel.importMessage ?? "")
        }
    }

    // MARK: Toolbar

    private var addMenu: some View {
        Menu {
            Button(String(localized: "Add Correction…")) {
                section = .corrections
                viewModel.startCreating(type: .correction)
            }
            Button(String(localized: "Add Term…")) {
                section = .terms
                viewModel.startCreating(type: .term)
            }
            Button(String(localized: "Edit Filler Words…")) {
                section = .fillerWords
                showsFillerWordsEditor = true
            }
            Divider()
            Button(String(localized: "Import Dictionary…")) {
                viewModel.importDictionary()
            }
            Button(String(localized: "Export Dictionary…")) {
                viewModel.exportDictionary()
            }
            .disabled(viewModel.entries.isEmpty)
        } label: {
            Label(String(localized: "Add"), systemImage: "plus")
        }
        .help(String(localized: "Add a correction or term"))
    }

    // MARK: Korrekturen

    @ViewBuilder
    private var correctionsSection: some View {
        let corrections = viewModel.rows(of: .correction)
        Section {
            if corrections.isEmpty {
                DictionaryEmptyRow(
                    title: String(localized: "No corrections yet"),
                    message: String(localized: "A correction replaces one spelling with another after every dictation, for example “Kesler” with “Kessler”."),
                    actionTitle: String(localized: "Add Correction…")
                ) {
                    viewModel.startCreating(type: .correction)
                }
            } else {
                ForEach(corrections) { row in
                    CorrectionRow(
                        row: row,
                        setEnabled: { viewModel.setEntryEnabled(id: row.id, enabled: $0) },
                        edit: { viewModel.startEditingEntry(id: row.id) },
                        delete: { viewModel.deleteEntry(id: row.id) }
                    )
                }
            }
        } header: {
            Text(SettingsRow.corrections.title)
        } footer: {
            if !corrections.isEmpty {
                Text(String(localized: "Leise replaces these spellings after every dictation."))
            }
        }
    }

    // MARK: Begriffe

    private var isVocabularyBoostingOn: Bool {
        modelManager.engine(for: modelManager.selectedProviderId)?.capabilities.dictionaryHints == .available
    }

    @ViewBuilder
    private var termsSection: some View {
        let terms = viewModel.rows(of: .term)
        Section {
            if terms.isEmpty {
                DictionaryEmptyRow(
                    title: String(localized: "No terms yet"),
                    message: String(localized: "Terms are names and special words Leise should know, such as “Parakeet” or your colleagues’ names."),
                    actionTitle: String(localized: "Add Term…")
                ) {
                    viewModel.startCreating(type: .term)
                }
            } else {
                FlowLayout(spacing: LeiseSpacing.s) {
                    ForEach(terms) { row in
                        TermChip(
                            row: row,
                            edit: { viewModel.startEditingEntry(id: row.id) },
                            setEnabled: { viewModel.setEntryEnabled(id: row.id, enabled: $0) },
                            delete: { viewModel.deleteEntry(id: row.id) }
                        )
                    }
                }
                .padding(.vertical, LeiseSpacing.xs)
            }

            LabeledContent {
                HStack(spacing: LeiseSpacing.m) {
                    Text(isVocabularyBoostingOn ? String(localized: "On") : String(localized: "Off"))
                        .foregroundStyle(.secondary)
                    Button(String(localized: "Set Up…")) {
                        showsEngineSettings = true
                    }
                }
            } label: {
                SettingsRowLabel(
                    title: SettingsRow.vocabularyBoosting.title,
                    subtitle: String(localized: "Helps with names and special words."),
                    info: String(localized: "Leise weights these words more strongly while recognizing. A small extra model loads once for this.")
                )
            }
            .settingsRow(.vocabularyBoosting)
        } header: {
            Text(SettingsRow.terms.title)
        }
    }

    // MARK: Füllwörter

    private var fillerWords: [String] {
        var seen = Set<String>()
        return fillerWordsText
            .components(separatedBy: CharacterSet(charactersIn: "\n,;"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }

    @ViewBuilder
    private var fillerWordsSection: some View {
        let words = fillerWords
        Section {
            if words.isEmpty {
                Text(String(localized: "No filler words. Leise leaves your text as it is."))
                    .foregroundStyle(.secondary)
            } else {
                FlowLayout(spacing: LeiseSpacing.s) {
                    ForEach(words, id: \.self) { word in
                        WordChip(text: word)
                    }
                }
                .padding(.vertical, LeiseSpacing.xs)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(String(localized: "Filler words: \(words.formatted(.list(type: .and)))"))
            }

            LabeledContent {
                Button(String(localized: "Edit…")) {
                    showsFillerWordsEditor = true
                }
            } label: {
                SettingsRowLabel(
                    title: SettingsRow.fillerWordList.title,
                    subtitle: String(localized: "Add words, or restore the default list.")
                )
            }
            .settingsRow(.fillerWordList)
        } header: {
            Text(String(localized: "Filler Words"))
        } footer: {
            Text(AttributedString(localized: "Applies when [“Remove filler words”](leise-settings://dictation/filler-words) is on under Dictation."))
                .environment(\.openURL, OpenURLAction { _ in
                    MainActor.assumeIsolated {
                        SettingsNavigationCoordinator.shared.show(.removeFillerWords)
                    }
                    return .handled
                })
        }
    }

    // MARK: Pakete

    @ViewBuilder
    private var termPacksSections: some View {
        Section {
            ForEach(viewModel.visibleBuiltInPacks) { pack in
                TermPackRow(pack: pack, viewModel: viewModel)
            }
        } header: {
            Text(String(localized: "Term Packs"))
        } footer: {
            Text(String(localized: "Packs add ready-made term lists. You can remove them at any time."))
        }

        Section {
            switch termPackRegistryService.fetchState {
            case .idle, .loading:
                HStack(spacing: LeiseSpacing.s) {
                    ProgressView()
                        .controlSize(.small)
                    Text(String(localized: "Loading more packs…"))
                        .foregroundStyle(.secondary)
                }
            case .error(let message):
                LabeledContent {
                    Button(String(localized: "Retry")) {
                        Task { await termPackRegistryService.fetchRegistry(force: true) }
                    }
                } label: {
                    StatusLabel(kind: .error, text: String(localized: "More packs could not be loaded."))
                        .help(message)
                }
            case .loaded:
                if viewModel.visibleCommunityPacks.isEmpty {
                    Text(String(localized: "No more packs available yet."))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.visibleCommunityPacks) { pack in
                        TermPackRow(pack: pack, viewModel: viewModel)
                    }
                }
            }
        } header: {
            Text(String(localized: "More Packs"))
        }
        .task {
            await termPackRegistryService.fetchRegistry()
        }
    }
}

// MARK: - Rows

/// An empty section that says what belongs here and offers the first step.
private struct DictionaryEmptyRow: View {
    let title: String
    let message: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: LeiseSpacing.s) {
            Text(title)
                .font(.headline)
            Text(message)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(actionTitle, action: action)
                .padding(.top, LeiseSpacing.xs)
        }
        .padding(.vertical, LeiseSpacing.xs)
    }
}

/// "Kesler → Kessler" with its switch.
private struct CorrectionRow: View {
    let row: DictionaryEntryRow
    let setEnabled: @MainActor (Bool) -> Void
    let edit: () -> Void
    let delete: () -> Void

    private var replacement: String { row.replacementDisplayText ?? "" }

    private var accessibilityTitle: String {
        String(localized: "Replace “\(row.original)” with “\(replacement)”")
    }

    var body: some View {
        HStack(spacing: LeiseSpacing.m) {
            Button(action: edit) {
                HStack(spacing: LeiseSpacing.s) {
                    Text(row.original)
                        .foregroundStyle(.secondary)
                    Image(systemName: "arrow.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text(replacement)
                        .foregroundStyle(.primary)
                    if let origin {
                        Text(origin)
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                    }
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityTitle)
            .accessibilityHint(String(localized: "Opens the correction"))

            Toggle(isOn: Binding(get: { row.isEnabled }, set: setEnabled)) {
                Text(accessibilityTitle)
            }
            .toggleStyle(.switch)
            .labelsHidden()
        }
        .contextMenu {
            Button(String(localized: "Edit…"), action: edit)
            Divider()
            Button(String(localized: "Delete"), role: .destructive, action: delete)
        }
    }

    private var origin: String? {
        if let packName = row.packName {
            return String(localized: "from \(packName)")
        }
        return row.source == .autoLearned ? String(localized: "learned") : nil
    }
}

/// A term as a chip: click to edit, right-click for more.
private struct TermChip: View {
    let row: DictionaryEntryRow
    let edit: () -> Void
    let setEnabled: @MainActor (Bool) -> Void
    let delete: () -> Void

    var body: some View {
        Button(action: edit) {
            WordChip(text: row.original, isDimmed: !row.isEnabled)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(String(localized: "Edit…"), action: edit)
            Button(row.isEnabled ? String(localized: "Turn Off") : String(localized: "Turn On")) {
                setEnabled(!row.isEnabled)
            }
            Divider()
            Button(String(localized: "Delete"), role: .destructive, action: delete)
        }
        .accessibilityLabel(row.original)
        .accessibilityValue(row.isEnabled ? "" : String(localized: "Off"))
        .accessibilityHint(String(localized: "Opens the term"))
        .accessibilityAction(named: Text(row.isEnabled ? String(localized: "Turn Off") : String(localized: "Turn On"))) {
            setEnabled(!row.isEnabled)
        }
        .accessibilityAction(named: Text(String(localized: "Delete")), delete)
    }
}

/// A word in a capsule, for terms and filler words.
private struct WordChip: View {
    let text: String
    var isDimmed = false

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Text(text)
            .strikethrough(isDimmed)
            .foregroundStyle(isDimmed ? .secondary : .primary)
            .padding(.horizontal, LeiseSpacing.s)
            .padding(.vertical, LeiseSpacing.xs)
            .background(contrast == .increased ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.quaternary), in: Capsule())
    }
}

/// A term pack with Installieren or Entfernen.
private struct TermPackRow: View {
    let pack: TermPack
    @ObservedObject var viewModel: DictionaryViewModel

    private var isInstalled: Bool { viewModel.isPackActivated(pack) }

    var body: some View {
        LabeledContent {
            HStack(spacing: LeiseSpacing.m) {
                if isInstalled {
                    StatusLabel(kind: .ready, text: String(localized: "Installed"))
                    if viewModel.hasUpdate(for: pack) {
                        Button(String(localized: "Update")) {
                            withLeiseAnimation(LeiseMotion.ui) { viewModel.updatePack(pack) }
                        }
                    }
                    Button(String(localized: "Remove")) {
                        withLeiseAnimation(LeiseMotion.ui) { viewModel.deactivatePack(pack) }
                    }
                    .help(String(localized: "Remove this pack and its unchanged entries"))
                    .accessibilityLabel(String(localized: "Remove \(pack.name) pack"))
                } else {
                    Button(String(localized: "Install")) {
                        withLeiseAnimation(LeiseMotion.ui) { viewModel.activatePack(pack) }
                    }
                    .accessibilityLabel(String(localized: "Install \(pack.name) pack"))
                }
            }
        } label: {
            Label {
                SettingsRowLabel(
                    title: pack.name,
                    subtitle: String(localized: "\(pack.entryCount) entries")
                )
            } icon: {
                Image(systemName: pack.icon)
                    .foregroundStyle(LeiseColor.tint)
                    .frame(width: 20)
            }
        }
    }
}

// MARK: - Sheets

/// The filler-word component's own editor, with "Standard wiederherstellen".
private struct FillerWordsEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            ServiceContainer.shared.builtInComponents.fillerCleanupSettingsView
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            Divider()
            HStack {
                Spacer()
                Button(String(localized: "Done")) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(LeiseSpacing.l)
        }
        .frame(width: 460, height: 460)
    }
}

private struct DictionaryEditorSheet: View {
    @ObservedObject var viewModel: DictionaryViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Field?

    private enum Field {
        case original
        case replacement
    }

    private var isTerm: Bool { viewModel.editType == .term }

    private var title: String {
        switch (viewModel.isCreatingNew, isTerm) {
        case (true, true): String(localized: "New Term")
        case (true, false): String(localized: "New Correction")
        case (false, true): String(localized: "Edit Term")
        case (false, false): String(localized: "Edit Correction")
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    if isTerm {
                        TextField(String(localized: "Term"), text: $viewModel.editOriginal, prompt: Text(String(localized: "e.g. Kubernetes")))
                            .focused($focusedField, equals: .original)
                    } else {
                        TextField(String(localized: "Recognized as"), text: $viewModel.editOriginal, prompt: Text(String(localized: "e.g. kubernetees")))
                            .focused($focusedField, equals: .original)
                        TextField(String(localized: "Replace with"), text: $viewModel.editReplacement, prompt: Text(String(localized: "e.g. Kubernetes")))
                            .focused($focusedField, equals: .replacement)
                    }
                    Toggle(String(localized: "Case sensitive"), isOn: $viewModel.editCaseSensitive)
                } header: {
                    Text(title)
                } footer: {
                    Text(isTerm
                        ? String(localized: "Leise prefers terms while recognizing when “Prefer terms when recognizing” is on.")
                        : String(localized: "Corrections replace text after transcription."))
                }

                if isTerm {
                    Section {
                        Picker(String(localized: "Boosting"), selection: $viewModel.editTermBoostingMode) {
                            ForEach(DictionaryViewModel.TermBoostingMode.allCases) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }

                        if viewModel.editTermBoostingMode == .advanced {
                            LabeledContent(String(localized: "Threshold")) {
                                HStack(spacing: LeiseSpacing.s) {
                                    Slider(
                                        value: $viewModel.editAdvancedCtcMinSimilarity,
                                        in: DictionaryViewModel.minimumAdvancedCtcMinSimilarity...DictionaryViewModel.maximumAdvancedCtcMinSimilarity
                                    )
                                    .frame(width: 160)
                                    .accessibilityLabel(String(localized: "Threshold"))
                                    Text(viewModel.editAdvancedCtcMinSimilarity.formatted(.number.precision(.fractionLength(2))))
                                        .monospacedDigit()
                                        .foregroundStyle(.secondary)
                                        .frame(width: 36, alignment: .trailing)
                                }
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                if viewModel.canDeleteEditingEntry {
                    Button(String(localized: "Delete"), role: .destructive) {
                        viewModel.deleteEditingEntry()
                        dismiss()
                    }
                }
                Spacer()
                Button(String(localized: "Cancel")) {
                    viewModel.cancelEditing()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button(String(localized: "Save")) {
                    viewModel.saveEditing()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(viewModel.editOriginal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(LeiseSpacing.l)
        }
        .frame(width: 460, height: isTerm ? 400 : 340)
        .onAppear {
            focusedField = .original
        }
    }
}

// MARK: - FlowLayout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.width ?? 0, subviews: subviews, spacing: spacing)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            subview.place(
                at: CGPoint(x: bounds.minX + result.positions[index].x, y: bounds.minY + result.positions[index].y),
                proposal: .unspecified
            )
        }
    }

    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []

        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var rowHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)

                if x + size.width > maxWidth && x > 0 {
                    x = 0
                    y += rowHeight + spacing
                    rowHeight = 0
                }

                positions.append(CGPoint(x: x, y: y))
                rowHeight = max(rowHeight, size.height)
                x += size.width + spacing
            }

            self.size = CGSize(width: maxWidth, height: y + rowHeight)
        }
    }
}
