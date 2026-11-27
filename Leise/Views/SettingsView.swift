import AppKit
import SwiftUI

// MARK: - Pages

/// The nine pages of the main window.
enum SettingsTab: String, Hashable, CaseIterable, Identifiable, Sendable {
    case overview
    case history
    case dictionary
    case transcribe
    case dictation
    case apps
    case audio
    case appearance
    case advanced

    var id: String { rawValue }

    /// Pre-redesign name, still used by callers outside the window.
    static let home: SettingsTab = .overview
    /// Recovery lives in the history now.
    static let dictationRecovery: SettingsTab = .history

    var title: String {
        switch self {
        case .overview: String(localized: "Overview")
        case .history: String(localized: "History")
        case .dictionary: String(localized: "Dictionary")
        case .transcribe: String(localized: "Transcribe")
        case .dictation: String(localized: "Dictation")
        case .apps: String(localized: "Apps")
        case .audio: String(localized: "Audio")
        case .appearance: String(localized: "Appearance")
        case .advanced: String(localized: "Advanced")
        }
    }

    var systemImage: String {
        switch self {
        case .overview: "house"
        case .history: "clock.arrow.circlepath"
        case .dictionary: "character.book.closed"
        case .transcribe: "waveform"
        case .dictation: "mic"
        case .apps: "app.badge"
        case .audio: "speaker.wave.2"
        case .appearance: "paintbrush"
        case .advanced: "slider.horizontal.3"
        }
    }
}

/// The single source of truth for sidebar structure: every tab must appear in
/// exactly one section here, or it is unreachable from the UI (verified by
/// `SettingsStructureTests`).
enum SettingsSidebarLayout {
    /// What you work with, without a header.
    static let workTabs: [SettingsTab] = [.overview, .history, .dictionary, .transcribe]
    /// The settings, under the header "Einstellungen".
    static let preferenceTabs: [SettingsTab] = [.dictation, .apps, .audio, .appearance, .advanced]

    static let sections: [(id: String, tabs: [SettingsTab])] = [
        ("work", workTabs),
        ("preferences", preferenceTabs),
    ]

    static func title(forSection id: String) -> String? {
        id == "preferences" ? String(localized: "Settings") : nil
    }
}

// MARK: - Window state

@MainActor
final class SettingsWindowState: ObservableObject {
    @Published private(set) var selection: SettingsTab = .overview
    @Published var dictionarySection: DictionaryPageSection = .corrections
    @Published var transcribeMode: TranscribeMode = .recording
    /// The row the visible page should scroll to and flash.
    @Published private(set) var focusRequest: SettingsFocusRequest?
    /// The search result the sidebar shows as selected.
    @Published var searchSelection: SettingsRow?

    /// A plain page change from the sidebar: nothing to flash.
    func select(_ tab: SettingsTab) {
        focusRequest = nil
        if selection != tab {
            selection = tab
        }
    }

    /// Opens the page that owns `row`, in the right section, and flashes the row.
    func reveal(_ row: SettingsRow) {
        if let section = row.dictionarySection {
            dictionarySection = section
        }
        if let mode = row.transcribeMode {
            transcribeMode = mode
        }
        focusRequest = SettingsFocusRequest(row: row)
        if selection != row.page {
            selection = row.page
        }
    }

    func open(_ tab: SettingsTab, row: SettingsRow?) {
        if let row, row.page == tab {
            reveal(row)
        } else {
            select(tab)
        }
    }
}

// MARK: - Window

struct SettingsView: View {
    @StateObject private var state = SettingsWindowState()
    @State private var searchText = ""
    @ObservedObject private var fileTranscription = ServiceContainer.shared.fileTranscriptionViewModel
    @ObservedObject private var dictationRecovery = ServiceContainer.shared.dictationRecoveryViewModel
    @ObservedObject private var homeViewModel = ServiceContainer.shared.homeViewModel
    @ObservedObject private var settingsNavigation = SettingsNavigationCoordinator.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if #available(macOS 15, *) {
                SettingsSplitShell(
                    state: state,
                    searchText: $searchText,
                    recoveryCount: dictationRecovery.recoveries.count,
                    detail: { detail }
                )
            } else {
                SettingsLegacyShell(
                    state: state,
                    searchText: $searchText,
                    recoveryCount: dictationRecovery.recoveries.count,
                    detail: { detail }
                )
            }
        }
        .frame(minWidth: 860, idealWidth: 1000, minHeight: 540, idealHeight: 660)
        .onAppear {
            openFileTranscriptionIfRequested()
        }
        .onChange(of: fileTranscription.showFilePickerFromMenu) { _, _ in
            openFileTranscriptionIfRequested()
        }
        .onChange(of: homeViewModel.navigateToHistory) { _, navigate in
            guard navigate else { return }
            let historyViewModel = ServiceContainer.shared.historyViewModel
            historyViewModel.selectedAppFilter = homeViewModel.pendingHistoryAppBundleIdentifier
            historyViewModel.selectedTimeRange = homeViewModel.pendingHistoryTimeRange
            if let recordID = homeViewModel.pendingHistoryRecordID {
                historyViewModel.selectedRecordIDs = [recordID]
            }
            state.select(.history)
            homeViewModel.navigateToHistory = false
            homeViewModel.clearPendingHistoryNavigation()
        }
        .onReceive(settingsNavigation.$request.compactMap { $0 }) { request in
            searchText = ""
            state.open(request.tab, row: request.row)
            settingsNavigation.didHandle(request)
        }
    }

    private var detail: some View {
        ZStack {
            page(for: state.selection)
                .id(state.selection)
                .transition(pageTransition)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .environment(\.settingsFocusRequest, state.focusRequest)
        .leiseAnimation(LeiseMotion.ui, value: state.selection)
    }

    private var pageTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(
                insertion: .opacity.combined(with: .offset(y: LeiseSpacing.xs)),
                removal: .opacity
            )
    }

    private func openFileTranscriptionIfRequested() {
        guard fileTranscription.showFilePickerFromMenu else { return }
        state.transcribeMode = .file
        state.select(.transcribe)
    }

    @ViewBuilder
    private func page(for tab: SettingsTab) -> some View {
        switch tab {
        case .overview:
            OverviewPage()
        case .history:
            HistoryView()
        case .dictionary:
            DictionarySettingsView(section: $state.dictionarySection)
        case .transcribe:
            TranscribePage(mode: $state.transcribeMode)
        case .dictation:
            DictationSettingsPage()
        case .apps:
            ProfilesSettingsView()
        case .audio:
            AudioSettingsPage()
        case .appearance:
            AppearanceSettingsPage()
        case .advanced:
            AdvancedSettingsView()
        }
    }
}

// MARK: - Shells

@available(macOS 15, *)
private struct SettingsSplitShell<Detail: View>: View {
    @ObservedObject var state: SettingsWindowState
    @Binding var searchText: String
    let recoveryCount: Int
    @ViewBuilder let detail: () -> Detail

    var body: some View {
        NavigationSplitView {
            SettingsSidebar(state: state, query: searchText, recoveryCount: recoveryCount)
                .searchable(
                    text: $searchText,
                    placement: .sidebar,
                    prompt: Text(String(localized: "Search Settings"))
                )
                .navigationSplitViewColumnWidth(min: 200, ideal: 232, max: 300)
        } detail: {
            detail()
        }
    }
}

/// macOS 14: the default NavigationSplitView sidebar reveal glitches there, so
/// the sidebar is a plain column with its own toggle and search field.
private struct SettingsLegacyShell<Detail: View>: View {
    @ObservedObject var state: SettingsWindowState
    @Binding var searchText: String
    let recoveryCount: Int
    @ViewBuilder let detail: () -> Detail

    @State private var isSidebarVisible = true

    var body: some View {
        HStack(spacing: 0) {
            if isSidebarVisible {
                SettingsSidebar(state: state, query: searchText, recoveryCount: recoveryCount)
                    .safeAreaInset(edge: .top, spacing: 0) {
                        NativeSearchField(text: $searchText, prompt: String(localized: "Search Settings"))
                            .padding(.horizontal, LeiseSpacing.s + LeiseSpacing.xs)
                            .padding(.vertical, LeiseSpacing.s)
                    }
                    .frame(width: 232)

                Divider()
            }

            detail()
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button(action: toggleSidebar) {
                    Image(systemName: "sidebar.leading")
                }
                .help(String(localized: "Toggle Sidebar"))
                .accessibilityLabel(String(localized: "Toggle Sidebar"))
            }
        }
    }

    private func toggleSidebar() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            context.allowsImplicitAnimation = false
            withAnimation(nil) {
                isSidebarVisible.toggle()
            }
        }
    }
}

/// The native search field (macOS 14 sidebar, history list).
struct NativeSearchField: NSViewRepresentable {
    @Binding var text: String
    let prompt: String

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = prompt
        field.sendsSearchStringImmediately = true
        field.delegate = context.coordinator
        field.setAccessibilityLabel(prompt)
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        if field.stringValue != text {
            field.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        private let text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }
            MainActor.assumeIsolated {
                text.wrappedValue = field.stringValue
            }
        }
    }
}

// MARK: - Sidebar

private enum SidebarItem: Hashable {
    case page(SettingsTab)
    case result(SettingsRow)
}

private struct SettingsSidebar: View {
    @ObservedObject var state: SettingsWindowState
    let query: String
    let recoveryCount: Int

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSearching: Bool { !trimmedQuery.isEmpty }

    var body: some View {
        List(selection: selection) {
            if isSearching {
                searchResults
            } else {
                pages
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            SettingsSidebarFooter()
        }
    }

    private var selection: Binding<SidebarItem?> {
        Binding(
            get: {
                if isSearching {
                    return state.searchSelection.map(SidebarItem.result)
                }
                return .page(state.selection)
            },
            set: { item in
                switch item {
                case .page(let tab):
                    state.select(tab)
                case .result(let row):
                    state.searchSelection = row
                    state.reveal(row)
                case nil:
                    break
                }
            }
        )
    }

    @ViewBuilder
    private var pages: some View {
        ForEach(SettingsSidebarLayout.sections, id: \.id) { section in
            Section {
                ForEach(section.tabs) { tab in
                    Label(tab.title, systemImage: tab.systemImage)
                        .badge(tab == .history ? recoveryCount : 0)
                        .accessibilityValue(
                            tab == .history && recoveryCount > 0
                                ? String(localized: "Not transcribed: \(recoveryCount)")
                                : ""
                        )
                        .tag(SidebarItem.page(tab))
                }
            } header: {
                if let title = SettingsSidebarLayout.title(forSection: section.id) {
                    Text(title)
                }
            }
        }
    }

    @ViewBuilder
    private var searchResults: some View {
        let results = SettingsSearchIndex.results(for: trimmedQuery)
        if results.isEmpty {
            Text(String(localized: "No results for “\(trimmedQuery)”."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .selectionDisabled()
        } else {
            Section {
                ForEach(results) { entry in
                    SearchResultRow(entry: entry)
                        .tag(SidebarItem.result(entry.row))
                }
            } header: {
                Text(results.count == 1
                    ? String(localized: "1 result")
                    : String(localized: "\(results.count) results"))
            }
        }
    }
}

private struct SearchResultRow: View {
    let entry: SettingsSearchEntry

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.title)
                    .lineLimit(2)
                Text(entry.page.title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: entry.page.systemImage)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "\(entry.title), \(entry.page.title)"))
    }
}

private struct SettingsSidebarFooter: View {
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    var body: some View {
        HStack(spacing: LeiseSpacing.s) {
            LeiseMark()
                .frame(height: 11)
            Text(verbatim: "Leise \(version)")
            Text(verbatim: "·")
                .accessibilityHidden(true)
            Text(String(localized: "Local, no account"))
                .lineLimit(1)
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .padding(.horizontal, LeiseSpacing.l)
        .padding(.vertical, LeiseSpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Leise \(version), local, no account"))
    }
}

// MARK: - Shared row parts

/// A row label: the title in Body, an optional subtitle in Secondary, and an
/// optional ⓘ that keeps longer explanations out of the page.
struct SettingsRowLabel: View {
    let title: String
    var subtitle: String?
    var info: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: LeiseSpacing.xs) {
                Text(title)
                if let info {
                    SettingsInfoButton(text: info, topic: title)
                }
            }
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// ⓘ: opens a popover with the explanation that used to be a grey footnote.
struct SettingsInfoButton: View {
    let text: String
    var topic: String?

    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Image(systemName: "info.circle")
                .imageScale(.small)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .help(text)
        .accessibilityLabel(topic.map { String(localized: "More about \($0)") } ?? String(localized: "More information"))
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
                .padding(LeiseSpacing.m)
                .frame(width: 280, alignment: .leading)
        }
    }
}
