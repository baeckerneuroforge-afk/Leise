import AppKit
import SwiftUI

/// Übersicht: the week in one sentence, seven bars, the latest dictations and
/// whether Leise is ready.
struct OverviewPage: View {
    @ObservedObject private var viewModel = ServiceContainer.shared.homeViewModel
    @ObservedObject private var dictation = ServiceContainer.shared.dictationViewModel
    @ObservedObject private var modelManager = ServiceContainer.shared.modelManagerService
    @AppStorage(OverviewPage.punctuationTipDismissedKey) private var isPunctuationTipDismissed = false

    static let punctuationTipDismissedKey = "overviewSpokenPunctuationTipDismissed"

    var body: some View {
        SettingsPage(.overview) {
            Section {
                recentRows
            } header: {
                VStack(alignment: .leading, spacing: LeiseSpacing.xxl) {
                    WeekSummaryText(
                        week: viewModel.week,
                        hasAnyDictation: viewModel.hasAnyTranscriptions,
                        shortcut: dictationShortcutName
                    )
                    if viewModel.hasAnyTranscriptions {
                        WeekChart(days: viewModel.week.days)
                    }
                    Text(String(localized: "Recent"))
                        .font(.headline)
                        .foregroundStyle(.primary)
                }
                .textCase(nil)
                .padding(.bottom, LeiseSpacing.xs)
            }

            Section {
                if dictation.needsMicPermission {
                    PermissionStatusRow(kind: .microphone) { dictation.requestMicPermission() }
                }
                if dictation.needsAccessibilityPermission {
                    PermissionStatusRow(kind: .accessibility) { dictation.requestAccessibilityPermission() }
                }

                LabeledContent(String(localized: "Speech model")) {
                    ModelStatusLabel(modelManager: modelManager, includesModelName: true)
                }

                LabeledContent(String(localized: "Privacy")) {
                    Label(String(localized: "Everything stays on this Mac"), systemImage: "lock.fill")
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: LeiseSpacing.m) {
                    Text(String(localized: "Keyboard shortcut"))
                    Spacer(minLength: LeiseSpacing.s)
                    shortcutStatus
                }
                .accessibilityElement(children: .combine)
            } header: {
                Text(String(localized: "Status"))
            } footer: {
                if showsPunctuationTip {
                    SpokenPunctuationTip {
                        withLeiseAnimation(LeiseMotion.ui) {
                            isPunctuationTipDismissed = true
                        }
                    }
                    .padding(.top, LeiseSpacing.l)
                    .transition(.opacity)
                }
            }
        }
    }

    // MARK: Recent

    @ViewBuilder
    private var recentRows: some View {
        if viewModel.recentTranscriptions.isEmpty {
            Text(String(localized: "Your latest dictations appear here, ready to copy again."))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            ForEach(viewModel.recentTranscriptions, id: \.id) { record in
                RecentDictationRow(record: record) {
                    viewModel.pendingHistoryAppBundleIdentifier = nil
                    viewModel.pendingHistoryTimeRange = .all
                    viewModel.pendingHistoryRecordID = record.id
                    viewModel.navigateToHistory = true
                }
            }
        }
    }

    // MARK: Status

    private var dictationHotkeys: [UnifiedHotkey] {
        _ = dictation.hotkeyLabelsVersion
        return dictation.hotkeys(for: .hybrid)
    }

    private var dictationShortcutName: String? {
        dictationHotkeys.first.map(HotkeyService.displayName(for:))
    }

    @ViewBuilder
    private var shortcutStatus: some View {
        if let hotkey = dictationHotkeys.first {
            HStack(spacing: LeiseSpacing.s) {
                ShortcutKeyCaps(hotkey: hotkey)
                Text(String(localized: "hold to speak"))
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        } else {
            Button(String(localized: "Set Up…")) {
                SettingsNavigationCoordinator.shared.show(.dictationShortcut)
            }
        }
    }

    private var showsPunctuationTip: Bool {
        !isPunctuationTipDismissed && viewModel.hasAnyTranscriptions
    }
}

// MARK: - Summary

/// "Diese Woche hast du 4.812 Wörter in 63 Diktaten gesprochen. …" with the
/// numbers in SF Pro Rounded; they count when the week changes.
private struct WeekSummaryText: View {
    let week: WeekOverview
    let hasAnyDictation: Bool
    let shortcut: String?

    var body: some View {
        Text(styled(summary))
            .font(.title.weight(.medium))
            .lineSpacing(LeiseSpacing.xs)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 520, alignment: .leading)
            .contentTransition(.numericText())
            .leiseAnimation(LeiseMotion.moment, value: week)
            .accessibilityAddTraits(.isHeader)
    }

    private var summary: AttributedString {
        guard hasAnyDictation else {
            if let shortcut {
                return AttributedString(localized: "Hold **\(shortcut)** in any app and speak. Your first dictation appears here.")
            }
            return AttributedString(localized: "Set a dictation shortcut, then speak into any app. Your first dictation appears here.")
        }
        guard week.dictations > 0 else {
            return AttributedString(localized: "You haven’t dictated anything this week yet.")
        }

        let words = week.words.formatted()
        var text: AttributedString
        if week.dictations == 1 {
            text = week.words == 1
                ? AttributedString(localized: "This week you spoke **one** word in **one** dictation.")
                : AttributedString(localized: "This week you spoke **\(words)** words in **one** dictation.")
        } else {
            let dictations = week.dictations.formatted()
            text = AttributedString(localized: "This week you spoke **\(words)** words in **\(dictations)** dictations.")
        }

        let savedMinutes = week.savedMinutes.rounded()
        if savedMinutes >= 1 {
            let saved = Duration.seconds(savedMinutes * 60)
                .formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
            text += AttributedString(" ")
            text += AttributedString(localized: "Compared with typing, that saved you about **\(saved)**.")
            // An abbreviation such as "5 Min." can meet the sentence's own period.
            if String(text.characters.suffix(2)) == ".." {
                text.characters.removeLast()
            }
        }
        return text
    }

    /// Numbers bold in Label and rounded; the connecting words in Secondary.
    private func styled(_ text: AttributedString) -> AttributedString {
        var text = text
        for run in text.runs {
            if run.inlinePresentationIntent?.contains(.stronglyEmphasized) == true {
                text[run.range].font = Font.system(.title, design: .rounded, weight: .bold).monospacedDigit()
                text[run.range].foregroundColor = .primary
            } else {
                text[run.range].foregroundColor = .secondary
            }
        }
        return text
    }
}

// MARK: - Week chart

/// Seven bars, today in Petrol. They rise once when the page appears.
private struct WeekChart: View {
    let days: [WeekOverviewDay]

    /// The tallest bar; labels sit below it.
    private static let plotHeight: CGFloat = 66
    private static let maximumBarWidth: CGFloat = 30
    /// Each bar starts a little after the previous one.
    private static let stagger: Double = 0.045

    @State private var hasRisen = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    private var maximumWords: Int {
        max(days.map(\.words).max() ?? 0, 1)
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: LeiseSpacing.s) {
            ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                VStack(spacing: LeiseSpacing.s) {
                    bar(for: day, index: index)
                    Text(Self.weekdayLabel(for: day.date))
                        .font(.subheadline.weight(day.isToday ? .semibold : .regular))
                        .foregroundStyle(day.isToday ? .primary : .secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: Self.plotHeight + LeiseSpacing.xxl, alignment: .bottom)
        .task { hasRisen = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Words per day"))
        .accessibilityValue(accessibilitySummary)
    }

    private func bar(for day: WeekOverviewDay, index: Int) -> some View {
        let fraction = CGFloat(day.words) / CGFloat(maximumWords)
        let height = max(LeiseSpacing.xs, Self.plotHeight * fraction)
        return RoundedRectangle(cornerRadius: LeiseRadius.control, style: .continuous)
            .fill(fill(for: day))
            .frame(maxWidth: Self.maximumBarWidth)
            .frame(height: height)
            .frame(height: Self.plotHeight, alignment: .bottom)
            .scaleEffect(x: 1, y: reduceMotion || hasRisen ? 1 : 0, anchor: .bottom)
            .opacity(!reduceMotion || hasRisen ? 1 : 0)
            .animation(
                LeiseMotion.adaptive(LeiseMotion.moment, reduceMotion: reduceMotion)
                    .delay(reduceMotion ? 0 : Double(index) * Self.stagger),
                value: hasRisen
            )
            .leiseAnimation(LeiseMotion.moment, value: day.words)
    }

    /// "Mo", "Di" … without the abbreviation dot some locales add.
    private static func weekdayLabel(for date: Date) -> String {
        date.formatted(.dateTime.weekday(.short))
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }

    private func fill(for day: WeekOverviewDay) -> AnyShapeStyle {
        if day.isToday {
            return AnyShapeStyle(LeiseColor.tint)
        }
        return contrast == .increased ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.quaternary)
    }

    private var accessibilitySummary: String {
        days
            .filter { !$0.isFuture }
            .map { day in
                String(localized: "\(day.date.formatted(.dateTime.weekday(.wide))): \(day.words.formatted()) words")
            }
            .formatted(.list(type: .and, width: .narrow))
    }
}

// MARK: - Recent dictation

private struct RecentDictationRow: View {
    let record: TranscriptionRecord
    let open: () -> Void

    @State private var isHovering = false
    @State private var didCopy = false
    @FocusState private var isCopyFocused: Bool

    /// How long the copy button shows its check mark.
    private static let copiedHold: Duration = .milliseconds(1300)

    private var singleLineText: String {
        record.finalText
            .components(separatedBy: .newlines)
            .joined(separator: " ")
    }

    var body: some View {
        HStack(spacing: LeiseSpacing.m) {
            AppGlyph(bundleIdentifier: record.appBundleIdentifier, size: 20)
            Text(singleLineText)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(RecentDictationRow.timeLabel(for: record.timestamp))
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Button(action: copy) {
                Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 16)
            }
            .buttonStyle(.borderless)
            .focused($isCopyFocused)
            .opacity(isHovering || isCopyFocused || didCopy ? 1 : 0)
            .help(String(localized: "Copy"))
            .accessibilityLabel(String(localized: "Copy"))
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            withLeiseAnimation(LeiseMotion.micro) { isHovering = hovering }
        }
        .onTapGesture(perform: open)
        .contextMenu {
            Button(String(localized: "Copy"), action: copy)
            Button(String(localized: "Show in History"), action: open)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(singleLineText)
        .accessibilityValue(accessibilityValue)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default, open)
        .accessibilityAction(named: Text(String(localized: "Copy")), copy)
        .task(id: didCopy) {
            guard didCopy else { return }
            try? await Task.sleep(for: Self.copiedHold)
            withLeiseAnimation(LeiseMotion.micro) { didCopy = false }
        }
    }

    private var accessibilityValue: String {
        [record.appName, RecentDictationRow.timeLabel(for: record.timestamp)]
            .compactMap { $0 }
            .joined(separator: ", ")
    }

    private func copy() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(record.finalText, forType: .string)
        withLeiseAnimation(LeiseMotion.micro) { didCopy = true }
        AccessibilityNotification.Announcement(String(localized: "Copied")).post()
    }

    /// "10:42" today, "Gestern" yesterday, otherwise the date.
    static func timeLabel(for date: Date, calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        if calendar.isDateInYesterday(date) {
            return String(localized: "Yesterday")
        }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }
}

// MARK: - Tip

private struct SpokenPunctuationTip: View {
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: LeiseSpacing.s) {
            Image(systemName: "info.circle")
                .foregroundStyle(LeiseColor.tint)
                .accessibilityHidden(true)
            Text(String(localized: "Say “comma”, “period”, or “question mark”. Leise inserts the marks for you."))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .imageScale(.small)
            }
            .buttonStyle(.borderless)
            .help(String(localized: "Hide Tip"))
            .accessibilityLabel(String(localized: "Hide Tip"))
        }
        .font(.body)
        .padding(LeiseSpacing.m)
        .background(
            LeiseColor.tint.opacity(0.12),
            in: RoundedRectangle(cornerRadius: LeiseRadius.group, style: .continuous)
        )
        .accessibilityElement(children: .contain)
    }
}
