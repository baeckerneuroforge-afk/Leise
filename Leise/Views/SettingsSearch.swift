import AppKit
import SwiftUI

// MARK: - Searchable rows

/// Every settings row the sidebar search can find.
///
/// This table is the single source of row labels: pages build their rows from
/// `title`, so a search result always reads exactly like the row it opens.
/// Each row belongs to one page; a page tags the matching view with
/// `.settingsRow(_:)` so search can scroll to it and flash it.
enum SettingsRow: String, CaseIterable, Hashable, Sendable {
    // Übersicht
    case weekSummary
    // Verlauf
    case historyRetention
    case recovery
    // Wörterbuch
    case corrections
    case terms
    case vocabularyBoosting
    case fillerWordList
    case termPacks
    // Transkribieren
    case recorder
    case systemAudio
    case recordingsFolder
    case fileTranscription
    // Diktat
    case dictationShortcut
    case moreShortcuts
    case spokenLanguage
    case model
    case removeFillerWords
    case spokenPunctuation
    case numbersAsDigits
    case appAwareFormatting
    case restoreClipboard
    // Apps
    case appRules
    // Audio
    case microphone
    case microphoneTest
    case fallbackMicrophones
    case playSounds
    case pauseMedia
    case lowerOtherApps
    // Darstellung
    case indicator
    case menuBarIcon
    case launchAtLogin
    case appLanguage
    // Erweitert
    case backup
    case errorLog
    case exportDiagnostics
    case usageData
    case modelUnload
    case shortQuietClips
    case whisperMode
    case punctuationStrategy
    case updateChannel
    case setupAssistant

    /// The page that shows this row.
    var page: SettingsTab {
        switch self {
        case .weekSummary:
            .overview
        case .historyRetention, .recovery:
            .history
        case .corrections, .terms, .vocabularyBoosting, .fillerWordList, .termPacks:
            .dictionary
        case .recorder, .systemAudio, .recordingsFolder, .fileTranscription:
            .transcribe
        case .dictationShortcut, .moreShortcuts, .spokenLanguage, .model, .removeFillerWords,
             .spokenPunctuation, .numbersAsDigits, .appAwareFormatting, .restoreClipboard:
            .dictation
        case .appRules:
            .apps
        case .microphone, .microphoneTest, .fallbackMicrophones, .playSounds, .pauseMedia, .lowerOtherApps:
            .audio
        case .indicator, .menuBarIcon, .launchAtLogin, .appLanguage:
            .appearance
        case .backup, .errorLog, .exportDiagnostics, .usageData, .modelUnload, .shortQuietClips,
             .whisperMode, .punctuationStrategy, .updateChannel, .setupAssistant:
            .advanced
        }
    }

    /// The Wörterbuch section that must be showing for this row.
    var dictionarySection: DictionaryPageSection? {
        switch self {
        case .corrections: .corrections
        case .terms, .vocabularyBoosting: .terms
        case .fillerWordList: .fillerWords
        case .termPacks: .termPacks
        default: nil
        }
    }

    /// The Transkribieren mode that must be showing for this row.
    var transcribeMode: TranscribeMode? {
        switch self {
        case .recorder, .systemAudio, .recordingsFolder: .recording
        case .fileTranscription: .file
        default: nil
        }
    }

    /// False for destinations that are a whole page, a toolbar menu or a
    /// section another view draws: search opens the page at the top instead.
    var scrollsToRow: Bool {
        switch self {
        case .weekSummary, .historyRetention, .recovery, .corrections, .terms, .fillerWordList,
             .termPacks, .recorder, .fileTranscription, .appRules, .indicator:
            false
        default:
            true
        }
    }

    /// The row's label on its page.
    var title: String {
        switch self {
        case .weekSummary: String(localized: "Week at a glance")
        case .historyRetention: String(localized: "History retention")
        case .recovery: String(localized: "Recovery")
        case .corrections: String(localized: "Corrections")
        case .terms: String(localized: "Terms")
        case .vocabularyBoosting: String(localized: "Prefer terms when recognizing")
        case .fillerWordList: String(localized: "Filler word list")
        case .termPacks: String(localized: "Term packs")
        case .recorder: String(localized: "Recording")
        case .systemAudio: String(localized: "Record system audio")
        case .recordingsFolder: String(localized: "Save location")
        case .fileTranscription: String(localized: "Transcribe a file")
        case .dictationShortcut: String(localized: "Dictation")
        case .moreShortcuts: String(localized: "More shortcuts")
        case .spokenLanguage: String(localized: "Language")
        case .model: String(localized: "Model")
        case .removeFillerWords: String(localized: "Remove filler words")
        case .spokenPunctuation: String(localized: "Spoken punctuation")
        case .numbersAsDigits: String(localized: "Numbers as digits")
        case .appAwareFormatting: String(localized: "Adapt to the app")
        case .restoreClipboard: String(localized: "Restore clipboard")
        case .appRules: String(localized: "Rules per app")
        case .microphone: String(localized: "Input")
        case .microphoneTest: String(localized: "Level")
        case .fallbackMicrophones: String(localized: "Backup microphones")
        case .playSounds: String(localized: "Play sounds")
        case .pauseMedia: String(localized: "Pause music and videos")
        case .lowerOtherApps: String(localized: "Lower other apps")
        case .indicator: String(localized: "Indicator")
        case .menuBarIcon: String(localized: "Menu bar icon")
        case .launchAtLogin: String(localized: "Launch at Login")
        case .appLanguage: String(localized: "App language")
        case .backup: String(localized: "Export backup")
        case .errorLog: String(localized: "Error log")
        case .exportDiagnostics: String(localized: "Export diagnostics")
        case .usageData: String(localized: "Usage data")
        case .modelUnload: String(localized: "Unload model")
        case .shortQuietClips: String(localized: "Discard very short or quiet recordings")
        case .whisperMode: String(localized: "Whisper mode")
        case .punctuationStrategy: String(localized: "Recognition")
        case .updateChannel: String(localized: "Update channel")
        case .setupAssistant: String(localized: "Setup")
        }
    }

    /// The label a search result shows when the row label alone would be
    /// ambiguous ("Input", "Level", "Recognition").
    var searchTitle: String {
        switch self {
        case .dictationShortcut: String(localized: "Keyboard shortcut")
        case .microphone: String(localized: "Microphone")
        case .microphoneTest: String(localized: "Test level")
        case .indicator: String(localized: "Indicator style")
        case .punctuationStrategy: String(localized: "Punctuation recognition")
        case .setupAssistant: String(localized: "Open setup again")
        default: title
        }
    }

    /// Extra words that find the row. Space-separated, never shown.
    var keywords: String {
        switch self {
        case .weekSummary: String(localized: "statistics words dictations time saved", comment: "Settings search keywords for the weekSummary row: space-separated words that find it, never shown")
        case .historyRetention: String(localized: "keep delete days save audio", comment: "Settings search keywords for the historyRetention row: space-separated words that find it, never shown")
        case .recovery: String(localized: "failed not transcribed recording retry", comment: "Settings search keywords for the recovery row: space-separated words that find it, never shown")
        case .corrections: String(localized: "replace spelling", comment: "Settings search keywords for the corrections row: space-separated words that find it, never shown")
        case .terms: String(localized: "vocabulary names jargon", comment: "Settings search keywords for the terms row: space-separated words that find it, never shown")
        case .vocabularyBoosting: String(localized: "vocabulary boosting names", comment: "Settings search keywords for the vocabularyBoosting row: space-separated words that find it, never shown")
        case .fillerWordList: String(localized: "um uh filler list edit", comment: "Settings search keywords for the fillerWordList row: space-separated words that find it, never shown")
        case .termPacks: String(localized: "packs jargon developer", comment: "Settings search keywords for the termPacks row: space-separated words that find it, never shown")
        case .recorder: String(localized: "recorder meeting call", comment: "Settings search keywords for the recorder row: space-separated words that find it, never shown")
        case .systemAudio: String(localized: "call meeting participants", comment: "Settings search keywords for the systemAudio row: space-separated words that find it, never shown")
        case .recordingsFolder: String(localized: "folder format m4a wav", comment: "Settings search keywords for the recordingsFolder row: space-separated words that find it, never shown")
        case .fileTranscription: String(localized: "file import subtitles srt vtt", comment: "Settings search keywords for the fileTranscription row: space-separated words that find it, never shown")
        case .dictationShortcut: String(localized: "hotkey fn globe key hold tap", comment: "Settings search keywords for the dictationShortcut row: space-separated words that find it, never shown")
        case .moreShortcuts: String(localized: "hotkey push-to-talk toggle recorder", comment: "Settings search keywords for the moreShortcuts row: space-separated words that find it, never shown")
        case .spokenLanguage: String(localized: "german english spoken", comment: "Settings search keywords for the spokenLanguage row: space-separated words that find it, never shown")
        case .model: String(localized: "parakeet engine download", comment: "Settings search keywords for the model row: space-separated words that find it, never shown")
        case .removeFillerWords: String(localized: "um uh filler cleanup", comment: "Settings search keywords for the removeFillerWords row: space-separated words that find it, never shown")
        case .spokenPunctuation: String(localized: "comma period question mark", comment: "Settings search keywords for the spokenPunctuation row: space-separated words that find it, never shown")
        case .numbersAsDigits: String(localized: "numbers digits", comment: "Settings search keywords for the numbersAsDigits row: space-separated words that find it, never shown")
        case .appAwareFormatting: String(localized: "formatting markdown", comment: "Settings search keywords for the appAwareFormatting row: space-separated words that find it, never shown")
        case .restoreClipboard: String(localized: "clipboard paste", comment: "Settings search keywords for the restoreClipboard row: space-separated words that find it, never shown")
        case .appRules: String(localized: "profiles websites per app", comment: "Settings search keywords for the appRules row: space-separated words that find it, never shown")
        case .microphone: String(localized: "input device", comment: "Settings search keywords for the microphone row: space-separated words that find it, never shown")
        case .microphoneTest: String(localized: "microphone test", comment: "Settings search keywords for the microphoneTest row: space-separated words that find it, never shown")
        case .fallbackMicrophones: String(localized: "fallback microphone order", comment: "Settings search keywords for the fallbackMicrophones row: space-separated words that find it, never shown")
        case .playSounds: String(localized: "sound feedback", comment: "Settings search keywords for the playSounds row: space-separated words that find it, never shown")
        case .pauseMedia: String(localized: "media music", comment: "Settings search keywords for the pauseMedia row: space-separated words that find it, never shown")
        case .lowerOtherApps: String(localized: "ducking volume", comment: "Settings search keywords for the lowerOtherApps row: space-separated words that find it, never shown")
        case .indicator: String(localized: "notch floating minimal live text", comment: "Settings search keywords for the indicator row: space-separated words that find it, never shown")
        case .menuBarIcon: String(localized: "dock icon", comment: "Settings search keywords for the menuBarIcon row: space-separated words that find it, never shown")
        case .launchAtLogin: String(localized: "login startup", comment: "Settings search keywords for the launchAtLogin row: space-separated words that find it, never shown")
        case .appLanguage: String(localized: "english german japanese", comment: "Settings search keywords for the appLanguage row: space-separated words that find it, never shown")
        case .backup: String(localized: "backup import restore", comment: "Settings search keywords for the backup row: space-separated words that find it, never shown")
        case .errorLog: String(localized: "errors log", comment: "Settings search keywords for the errorLog row: space-separated words that find it, never shown")
        case .exportDiagnostics: String(localized: "support report", comment: "Settings search keywords for the exportDiagnostics row: space-separated words that find it, never shown")
        case .usageData: String(localized: "statistics dashboard quality", comment: "Settings search keywords for the usageData row: space-separated words that find it, never shown")
        case .modelUnload: String(localized: "memory", comment: "Settings search keywords for the modelUnload row: space-separated words that find it, never shown")
        case .shortQuietClips: String(localized: "short quiet no speech", comment: "Settings search keywords for the shortQuietClips row: space-separated words that find it, never shown")
        case .whisperMode: String(localized: "agc gain quiet", comment: "Settings search keywords for the whisperMode row: space-separated words that find it, never shown")
        case .punctuationStrategy: String(localized: "comma period strategy test", comment: "Settings search keywords for the punctuationStrategy row: space-separated words that find it, never shown")
        case .updateChannel: String(localized: "updates beta", comment: "Settings search keywords for the updateChannel row: space-separated words that find it, never shown")
        case .setupAssistant: String(localized: "setup assistant onboarding", comment: "Settings search keywords for the setupAssistant row: space-separated words that find it, never shown")
        }
    }
}

/// The two Wörterbuch sections behind the toolbar's segmented control, plus packs.
enum DictionaryPageSection: String, CaseIterable, Identifiable, Hashable, Sendable {
    case corrections
    case terms
    case fillerWords
    case termPacks

    var id: String { rawValue }

    var title: String {
        switch self {
        case .corrections: String(localized: "Corrections")
        case .terms: String(localized: "Terms")
        case .fillerWords: String(localized: "Filler Words")
        case .termPacks: String(localized: "Packs")
        }
    }
}

/// Transkribieren › Aufnahme | Datei.
enum TranscribeMode: String, CaseIterable, Identifiable, Hashable, Sendable {
    case recording
    case file

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recording: String(localized: "Recording")
        case .file: String(localized: "File")
        }
    }
}

// MARK: - Index

struct SettingsSearchEntry: Identifiable, Equatable {
    let row: SettingsRow
    let title: String
    let keywords: String

    var id: SettingsRow { row }
    var page: SettingsTab { row.page }
}

enum SettingsSearchIndex {
    /// One entry per row, in sidebar order: the order results appear in when
    /// they match equally well.
    static var entries: [SettingsSearchEntry] {
        SettingsSidebarLayout.sections
            .flatMap(\.tabs)
            .flatMap { tab in SettingsRow.allCases.filter { $0.page == tab } }
            .map { SettingsSearchEntry(row: $0, title: $0.searchTitle, keywords: $0.keywords) }
    }

    /// Rows whose label, keywords or page title contain every word of
    /// `query`, ignoring case and diacritics ("fullworter" finds "Füllwörter").
    /// Label matches rank before keyword and page matches.
    static func results(
        for query: String,
        in entries: [SettingsSearchEntry] = entries
    ) -> [SettingsSearchEntry] {
        let terms = query
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        guard !terms.isEmpty else { return [] }

        let scored: [(entry: SettingsSearchEntry, score: Int)] = entries.compactMap { entry in
            let haystack = [entry.title, entry.keywords, entry.page.title].joined(separator: " ")
            guard terms.allSatisfy({ haystack.localizedStandardContains($0) }) else { return nil }
            let titleMatches = terms.allSatisfy { entry.title.localizedStandardContains($0) }
            let titleStarts = entry.title.localizedStandardRange(of: terms[0])?.lowerBound == entry.title.startIndex
            return (entry, titleStarts ? 0 : titleMatches ? 1 : 2)
        }

        return scored
            .enumerated()
            .sorted { lhs, rhs in
                lhs.element.score == rhs.element.score
                    ? lhs.offset < rhs.offset
                    : lhs.element.score < rhs.element.score
            }
            .map(\.element.entry)
    }
}

// MARK: - Focus

/// "Show this row": set by search or a cross-link, consumed by the page that
/// owns the row. A new `id` makes the same row flash again.
struct SettingsFocusRequest: Equatable, Sendable {
    let row: SettingsRow
    let id: UUID

    init(row: SettingsRow, id: UUID = UUID()) {
        self.row = row
        self.id = id
    }
}

private struct SettingsFocusRequestKey: EnvironmentKey {
    static let defaultValue: SettingsFocusRequest? = nil
}

private struct SettingsHighlightedRowKey: EnvironmentKey {
    static let defaultValue: SettingsRow? = nil
}

extension EnvironmentValues {
    /// The row the window wants to show; read by `SettingsPage`.
    var settingsFocusRequest: SettingsFocusRequest? {
        get { self[SettingsFocusRequestKey.self] }
        set { self[SettingsFocusRequestKey.self] = newValue }
    }

    /// The row that currently carries the search highlight.
    var settingsHighlightedRow: SettingsRow? {
        get { self[SettingsHighlightedRowKey.self] }
        set { self[SettingsHighlightedRowKey.self] = newValue }
    }
}

private struct SettingsRowLocatorKey: EnvironmentKey {
    static let defaultValue: SettingsRowLocator? = nil
}

extension EnvironmentValues {
    /// Where the page's tagged rows register their AppKit views.
    fileprivate var settingsRowLocator: SettingsRowLocator? {
        get { self[SettingsRowLocatorKey.self] }
        set { self[SettingsRowLocatorKey.self] = newValue }
    }
}

enum SettingsSearchTiming {
    /// Lets the page lay out before it scrolls to a row it just created.
    static let layoutSettle: Duration = .milliseconds(80)
    /// One frame: rows a lazy list creates while scrolling register by then.
    static let rowLoad: Duration = .milliseconds(16)
    /// How long the Petrol wash stays at full strength before it fades with
    /// `LeiseMotion.moment`: long enough to find the row after the scroll.
    static let highlightHold: Duration = .milliseconds(900)
}

extension View {
    /// Marks the row search can scroll to and flash.
    func settingsRow(_ row: SettingsRow) -> some View {
        modifier(SettingsRowAnchor(row: row))
    }
}

private struct SettingsRowAnchor: ViewModifier {
    let row: SettingsRow

    @Environment(\.settingsHighlightedRow) private var highlightedRow
    @Environment(\.settingsRowLocator) private var locator
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content
            .id(row)
            .background {
                SettingsRowLocatorView(row: row, locator: locator)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .background {
                RoundedRectangle(cornerRadius: LeiseRadius.control, style: .continuous)
                    .fill(LeiseColor.tint.opacity(contrast == .increased ? 0.22 : 0.12))
                    .padding(.horizontal, -LeiseSpacing.s)
                    .padding(.vertical, -LeiseSpacing.xs)
                    .opacity(highlightedRow == row ? 1 : 0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
    }
}

// MARK: - Scrolling

/// The AppKit views behind a page's tagged rows.
///
/// A grouped `Form` on macOS ignores `ScrollViewReader.scrollTo`, so search
/// scrolls the form's `NSScrollView` directly when the row isn't in view.
@MainActor
private final class SettingsRowLocator {
    private final class WeakView {
        weak var view: SettingsRowMarkerView?
        init(_ view: SettingsRowMarkerView) { self.view = view }
    }

    private var views: [SettingsRow: WeakView] = [:]

    func register(_ view: SettingsRowMarkerView, for row: SettingsRow) {
        view.row = row
        views[row] = WeakView(view)
    }

    /// The row's view, if the form has created it, it is in the window and a
    /// recycled table row hasn't taken it over for another row.
    func view(for row: SettingsRow) -> NSView? {
        guard let view = views[row]?.view, view.row == row, view.window != nil else { return nil }
        return view
    }

    /// The page's scroll view, found through any row that exists.
    var scrollView: NSScrollView? {
        views.values.lazy.compactMap { $0.view?.enclosingScrollView }.first
    }
}

/// An empty view behind a tagged row that knows which row it marks.
private final class SettingsRowMarkerView: NSView {
    var row: SettingsRow?
}

private struct SettingsRowLocatorView: NSViewRepresentable {
    let row: SettingsRow
    let locator: SettingsRowLocator?

    func makeNSView(context: Context) -> SettingsRowMarkerView {
        let view = SettingsRowMarkerView()
        locator?.register(view, for: row)
        return view
    }

    func updateNSView(_ view: SettingsRowMarkerView, context: Context) {
        locator?.register(view, for: row)
    }
}

@MainActor
enum SettingsScrolling {
    /// The scroll animation matches `LeiseMotion.ui` (200 ms, ease-out).
    static let duration: TimeInterval = 0.2

    static func isFullyVisible(_ view: NSView) -> Bool {
        guard let scrollView = view.enclosingScrollView, let documentView = scrollView.documentView else { return false }
        let rect = view.convert(view.bounds, to: documentView)
        return scrollView.documentVisibleRect.contains(rect)
    }

    /// Scrolls so `view` sits in the middle of its scroll view.
    static func center(_ view: NSView, animated: Bool) {
        guard let scrollView = view.enclosingScrollView, let documentView = scrollView.documentView else { return }
        let rect = view.convert(view.bounds, to: documentView)
        let clipView = scrollView.contentView
        var origin = clipView.bounds.origin
        origin.y = rect.midY - clipView.bounds.height / 2
        scroll(scrollView, to: origin, animated: animated)
    }

    /// Moves one screen further down, to make a lazy list create later rows.
    static func pageDown(_ scrollView: NSScrollView) {
        let clipView = scrollView.contentView
        let flipped = scrollView.documentView?.isFlipped ?? true
        var origin = clipView.bounds.origin
        origin.y += (flipped ? 1 : -1) * clipView.bounds.height * 0.8
        scroll(scrollView, to: origin, animated: false)
    }

    private static func scroll(_ scrollView: NSScrollView, to origin: NSPoint, animated: Bool) {
        let clipView = scrollView.contentView
        let target = clipView.constrainBoundsRect(NSRect(origin: origin, size: clipView.bounds.size)).origin
        ScrollAnimator.current?.stop()
        // A window that isn't on a screen gets no display-link ticks.
        if animated, scrollView.window?.screen != nil, target != clipView.bounds.origin {
            ScrollAnimator.current = ScrollAnimator(scrollView: scrollView, target: target)
        } else {
            setOrigin(target, of: scrollView)
        }
    }

    fileprivate static func setOrigin(_ origin: NSPoint, of scrollView: NSScrollView) {
        scrollView.contentView.setBoundsOrigin(origin)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }
}

/// Scrolls frame by frame on the display's refresh. SwiftUI's hosting scroll
/// view ignores bounds changes made through `NSClipView.animator()`.
@MainActor
private final class ScrollAnimator: NSObject {
    static var current: ScrollAnimator?

    private weak var scrollView: NSScrollView?
    private let start: NSPoint
    private let target: NSPoint
    private let startTime = CACurrentMediaTime()
    private var link: CADisplayLink?

    init(scrollView: NSScrollView, target: NSPoint) {
        self.scrollView = scrollView
        self.start = scrollView.contentView.bounds.origin
        self.target = target
        super.init()
        let link = scrollView.displayLink(target: self, selector: #selector(step(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link

        // If the display stops ticking (the window moved off screen), still end
        // at the target.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(SettingsScrolling.duration) + SettingsSearchTiming.layoutSettle)
            self?.finish()
        }
    }

    private func finish() {
        guard link != nil, let scrollView else { return }
        SettingsScrolling.setOrigin(target, of: scrollView)
        stop()
    }

    func stop() {
        link?.invalidate()
        link = nil
        if ScrollAnimator.current === self {
            ScrollAnimator.current = nil
        }
    }

    @objc private func step(_ link: CADisplayLink) {
        guard let scrollView else {
            stop()
            return
        }
        let progress = min((CACurrentMediaTime() - startTime) / SettingsScrolling.duration, 1)
        // Ease-out, like LeiseMotion.ui.
        let eased = 1 - pow(1 - progress, 3)
        let origin = NSPoint(
            x: start.x + (target.x - start.x) * eased,
            y: start.y + (target.y - start.y) * eased
        )
        SettingsScrolling.setOrigin(origin, of: scrollView)
        if progress >= 1 {
            stop()
        }
    }
}

// MARK: - Page container

/// A settings page: the grouped form under the page title, centered at most
/// 620 pt wide, that scrolls to and flashes the row search asked for.
struct SettingsPage<Content: View>: View {
    static var maximumContentWidth: CGFloat { 620 }

    let tab: SettingsTab
    @ViewBuilder var content: () -> Content

    @Environment(\.settingsFocusRequest) private var focusRequest
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var highlightedRow: SettingsRow?
    @State private var locator = SettingsRowLocator()

    /// Screens to step down while looking for a row a lazy list hasn't made yet.
    private static var maximumPageSteps: Int { 8 }

    init(_ tab: SettingsTab, @ViewBuilder content: @escaping () -> Content) {
        self.tab = tab
        self.content = content
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { scroller in
                LeiseSettingsPage(tab.title) {
                    content()
                }
                .contentMargins(
                    .horizontal,
                    Self.horizontalMargin(forWidth: geometry.size.width),
                    for: .scrollContent
                )
                .environment(\.settingsHighlightedRow, highlightedRow)
                .environment(\.settingsRowLocator, locator)
                .task(id: focusRequest?.id) {
                    await reveal(focusRequest, using: scroller)
                }
            }
        }
    }

    static func horizontalMargin(forWidth width: CGFloat) -> CGFloat {
        max(LeiseSpacing.xl, (width - maximumContentWidth) / 2)
    }

    private func reveal(_ request: SettingsFocusRequest?, using scroller: ScrollViewProxy) async {
        guard let request, request.row.page == tab, request.row.scrollsToRow else { return }
        try? await Task.sleep(for: SettingsSearchTiming.layoutSettle)
        guard !Task.isCancelled else { return }

        withLeiseAnimation(LeiseMotion.ui) {
            scroller.scrollTo(request.row, anchor: .center)
        }
        await scrollIntoView(request.row)
        guard !Task.isCancelled else { return }

        highlightedRow = request.row
        AccessibilityNotification.Announcement(request.row.title).post()

        try? await Task.sleep(for: SettingsSearchTiming.highlightHold)
        withLeiseAnimation(LeiseMotion.moment) {
            highlightedRow = nil
        }
    }

    /// The AppKit fallback for forms that ignore `scrollTo`.
    private func scrollIntoView(_ row: SettingsRow) async {
        var steps = 0
        while locator.view(for: row) == nil, steps < Self.maximumPageSteps, let scrollView = locator.scrollView {
            SettingsScrolling.pageDown(scrollView)
            steps += 1
            try? await Task.sleep(for: SettingsSearchTiming.rowLoad)
        }
        guard let view = locator.view(for: row), !SettingsScrolling.isFullyVisible(view) else { return }
        SettingsScrolling.center(view, animated: !reduceMotion)
    }
}
