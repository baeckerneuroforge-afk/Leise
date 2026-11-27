import AppKit
import Charts
import SwiftUI

/// Erweitert › Diagnose › Nutzungsdaten: the analytics the old dashboard
/// showed (activity, apps, quality), in a sheet.
struct UsageAnalyticsSheet: View {
    @ObservedObject private var viewModel = ServiceContainer.shared.homeViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showsClearConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: LeiseSpacing.l) {
                Text(SettingsRow.usageData.title)
                    .font(.title3.bold())
                Spacer()
                Picker(String(localized: "Period"), selection: $viewModel.selectedTimePeriod) {
                    ForEach(TimePeriod.allCases, id: \.self) { period in
                        Text(period.displayName).tag(period)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            .padding(.horizontal, LeiseSpacing.xl)
            .padding(.top, LeiseSpacing.xl)
            .padding(.bottom, LeiseSpacing.m)

            if viewModel.hasAnyTranscriptions {
                Picker(String(localized: "Area"), selection: $viewModel.selectedSection) {
                    ForEach(DashboardSection.allCases) { section in
                        Text(Self.title(for: section)).tag(section)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, LeiseSpacing.xl)
                .padding(.bottom, LeiseSpacing.m)

                ScrollView {
                    VStack(alignment: .leading, spacing: LeiseSpacing.l) {
                        switch viewModel.selectedSection {
                        case .overview: activityDashboard
                        case .apps: appsDashboard
                        case .quality: qualityDashboard
                        }
                    }
                    .padding(.horizontal, LeiseSpacing.xl)
                    .padding(.bottom, LeiseSpacing.xl)
                }
            } else {
                ContentUnavailableView {
                    Label(String(localized: "No usage data yet"), systemImage: "chart.bar")
                } description: {
                    Text(String(localized: "Leise counts dictations locally on this Mac. Statistics appear after your first dictation."))
                }
                .frame(maxHeight: .infinity)
            }

            Divider()

            HStack {
                Button(String(localized: "Delete Usage Data…"), role: .destructive) {
                    showsClearConfirmation = true
                }
                .disabled(!viewModel.hasAnyTranscriptions)
                #if DEBUG
                debugMenu
                #endif
                Spacer()
                Button(String(localized: "Done")) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(LeiseSpacing.l)
        }
        .frame(width: 720, height: 640)
        .confirmationDialog(
            String(localized: "Clear Usage Statistics?"),
            isPresented: $showsClearConfirmation
        ) {
            Button(String(localized: "Clear Statistics"), role: .destructive) {
                ServiceContainer.shared.usageStatisticsService.clearUsageStatistics()
            }
        } message: {
            Text(String(localized: "This will permanently delete all aggregate activity, application, habit, and quality statistics. Transcription history entries are unchanged."))
        }
    }

    private static func title(for section: DashboardSection) -> String {
        switch section {
        case .overview: String(localized: "Activity")
        case .apps: String(localized: "Apps")
        case .quality: String(localized: "Quality")
        }
    }

    // MARK: - Activity

    private var activityDashboard: some View {
        VStack(alignment: .leading, spacing: LeiseSpacing.l) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: LeiseSpacing.m)], spacing: LeiseSpacing.m) {
                StatCard(title: String(localized: "Dictations"), value: viewModel.dictationCount.formatted(), systemImage: "waveform", trend: viewModel.dictationsTrend)
                StatCard(title: String(localized: "Words"), value: viewModel.wordsCount.formatted(), systemImage: "text.word.spacing", trend: viewModel.wordsTrend)
                StatCard(title: String(localized: "Avg. WPM"), value: viewModel.averageWPM, systemImage: "speedometer", trend: viewModel.wpmTrend)
                StatCard(
                    title: String(localized: "Time Saved"),
                    value: viewModel.timeSaved,
                    systemImage: "clock.badge.checkmark",
                    trend: viewModel.timeSavedTrend,
                    subtitle: String(localized: "vs. 45 WPM typing")
                )
            }

            activitySection
            habitSummary
            habitsHeatmapSection
            durationDistributionSection
        }
    }

    private var activitySection: some View {
        AnalyticsCard {
            VStack(alignment: .leading, spacing: LeiseSpacing.s) {
                HStack {
                    Text(String(localized: "Activity"))
                        .font(.headline)
                    Spacer()
                    Text(activityGranularityLabel)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if viewModel.chartData.isEmpty || viewModel.chartData.allSatisfy({ $0.wordCount == 0 }) {
                    emptyAnalyticsMessage(String(localized: "No activity in this period."))
                } else {
                    Chart(viewModel.chartData) { point in
                        BarMark(
                            x: .value(String(localized: "Date"), point.date, unit: activityCalendarComponent),
                            y: .value(String(localized: "Words"), point.wordCount),
                            width: .ratio(0.68)
                        )
                        .foregroundStyle(LeiseColor.tint)
                        .cornerRadius(LeiseRadius.control)
                        .accessibilityLabel(activityLabel(point.date))
                        .accessibilityValue(String(localized: "\(point.wordCount) words, \(point.transcriptionCount) dictations"))
                    }
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 7)) { value in
                            AxisGridLine()
                            AxisValueLabel {
                                if let date = value.as(Date.self) {
                                    Text(activityLabel(date))
                                }
                            }
                        }
                    }
                    .chartXScale(range: .plotDimension(startPadding: activityChartEdgePadding, endPadding: activityChartEdgePadding))
                    .frame(height: 220)
                    .accessibilityLabel(String(localized: "Words dictated over time"))
                }
            }
        }
    }

    private var habitSummary: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: LeiseSpacing.m)], spacing: LeiseSpacing.m) {
            StatCard(title: String(localized: "Active Days"), value: viewModel.activeDays.formatted(), systemImage: "calendar.badge.checkmark")
            StatCard(title: String(localized: "Current Streak"), value: viewModel.currentStreak.formatted(), systemImage: "flame", subtitle: String(localized: "days"))
            StatCard(title: String(localized: "Avg. Duration"), value: viewModel.averageDictationDuration, systemImage: "timer")
            StatCard(title: String(localized: "Words / Dictation"), value: viewModel.averageWordsPerDictation, systemImage: "textformat.abc")
        }
    }

    private var habitsHeatmapSection: some View {
        AnalyticsCard {
            VStack(alignment: .leading, spacing: LeiseSpacing.s) {
                Text(String(localized: "Dictation Habits"))
                    .font(.headline)
                Text(String(localized: "When you dictate most"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Chart(viewModel.habitHeatmap) { point in
                    RectangleMark(
                        x: .value(String(localized: "Weekday"), point.weekdayKey),
                        y: .value(String(localized: "Time"), point.hourLabel)
                    )
                    .foregroundStyle(heatmapColor(for: point.count))
                    .cornerRadius(LeiseRadius.control)
                    .accessibilityLabel(Text(verbatim: "\(point.weekdayLabel), \(point.hourLabel):00"))
                    .accessibilityValue(String(localized: "\(point.count) dictations"))
                }
                .chartXScale(domain: heatmapWeekdayDomain)
                .chartXAxis {
                    AxisMarks(values: heatmapWeekdayDomain) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let key = value.as(String.self), let label = heatmapWeekdayLabel(for: key) {
                                Text(label)
                            }
                        }
                    }
                }
                .chartYScale(domain: heatmapHourDomain)
                .frame(height: 210)
                .accessibilityLabel(String(localized: "Dictations by weekday and time of day"))
            }
        }
    }

    private var durationDistributionSection: some View {
        AnalyticsCard {
            VStack(alignment: .leading, spacing: LeiseSpacing.s) {
                Text(String(localized: "Dictation Length"))
                    .font(.headline)
                Text(String(localized: "Distribution by speaking duration"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Chart(viewModel.durationBuckets) { bucket in
                    BarMark(
                        x: .value(String(localized: "Duration"), bucket.label),
                        y: .value(String(localized: "Dictations"), bucket.count)
                    )
                    .foregroundStyle(LeiseColor.tint)
                    .cornerRadius(LeiseRadius.control)
                    .annotation(position: .top) {
                        if bucket.count > 0 {
                            Text(bucket.count.formatted())
                                .font(.caption2)
                                .monospacedDigit()
                        }
                    }
                    .accessibilityLabel(bucket.label)
                    .accessibilityValue(String(localized: "\(bucket.count) dictations"))
                }
                .chartXScale(domain: viewModel.durationBuckets.sorted { $0.order < $1.order }.map(\.label))
                .frame(height: 180)
                .accessibilityLabel(String(localized: "Distribution of dictation duration"))
            }
        }
    }

    // MARK: - Apps

    private var appsDashboard: some View {
        VStack(alignment: .leading, spacing: LeiseSpacing.l) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: LeiseSpacing.m)], spacing: LeiseSpacing.m) {
                StatCard(title: String(localized: "Top App"), value: viewModel.topAppLabel, systemImage: "app.badge")
                StatCard(title: String(localized: "Apps Used"), value: viewModel.appsUsed.formatted(), systemImage: "square.grid.2x2")
                StatCard(title: String(localized: "Top-App Share"), value: viewModel.topAppShare, systemImage: "chart.bar.fill")
            }

            AnalyticsCard {
                VStack(alignment: .leading, spacing: LeiseSpacing.m) {
                    HStack {
                        Text(String(localized: "Usage by Application"))
                            .font(.headline)
                        Spacer()
                        Picker(String(localized: "Application metric"), selection: $viewModel.selectedAppMetric) {
                            ForEach(AppUsageMetric.allCases) { metric in
                                Text(metric.displayName).tag(metric)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                    }

                    if viewModel.appUsage.isEmpty {
                        emptyAnalyticsMessage(String(localized: "Application details will appear after your next dictation."))
                    } else {
                        let maximum = viewModel.appUsage.map { $0.value(for: viewModel.selectedAppMetric) }.max() ?? 1
                        VStack(spacing: LeiseSpacing.s) {
                            ForEach(viewModel.appUsage.prefix(12)) { item in
                                UsageBarRow(
                                    bundleIdentifier: item.id,
                                    label: item.label,
                                    value: appValueLabel(item),
                                    fraction: maximum > 0 ? item.value(for: viewModel.selectedAppMetric) / maximum : 0,
                                    accessibilityValue: String(localized: "\(item.transcriptionCount) dictations, \(item.words) words")
                                ) {
                                    viewModel.requestHistory(forAppBundleIdentifier: item.id)
                                    dismiss()
                                }
                            }
                        }
                    }
                }
            }

            AnalyticsCard {
                VStack(alignment: .leading, spacing: LeiseSpacing.m) {
                    Text(String(localized: "Browser Domains"))
                        .font(.headline)
                    Text(String(localized: "Stored locally from browser context"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if viewModel.domainUsage.isEmpty {
                        emptyAnalyticsMessage(String(localized: "No browser-domain activity in this period."))
                    } else {
                        let maximum = viewModel.domainUsage.map(\.transcriptionCount).max() ?? 1
                        VStack(spacing: LeiseSpacing.s) {
                            ForEach(viewModel.domainUsage.prefix(10)) { item in
                                UsageBarRow(
                                    label: item.label,
                                    value: item.transcriptionCount.formatted(),
                                    fraction: Double(item.transcriptionCount) / Double(maximum),
                                    accessibilityValue: String(localized: "\(item.transcriptionCount) dictations")
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Quality

    private var qualityDashboard: some View {
        VStack(alignment: .leading, spacing: LeiseSpacing.l) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: LeiseSpacing.m)], spacing: LeiseSpacing.m) {
                StatCard(title: String(localized: "Post-processed"), value: viewModel.postProcessedCount.formatted(), systemImage: "text.badge.checkmark", subtitle: viewModel.enhancementRate)
                StatCard(title: String(localized: "Words changed"), value: viewModel.changedWordCount.formatted(), systemImage: "character.cursor.ibeam")
                StatCard(
                    title: String(localized: "Manual Edits"),
                    value: viewModel.manualCorrectionCount.formatted(),
                    systemImage: "pencil.and.outline",
                    subtitle: String(localized: "\(viewModel.manuallyChangedWordCount) words changed")
                )
                StatCard(
                    title: String(localized: "Dictionary Fixes"),
                    value: viewModel.dictionaryCorrectionDictationCount.formatted(),
                    systemImage: "book.badge.checkmark",
                    subtitle: String(localized: "dictations improved")
                )
            }

            postProcessingCoverageSection
            correctionTrendSection
            processingBreakdownSection
            categoryUsageSection(title: String(localized: "Languages"), items: viewModel.languageUsage)
            categoryUsageSection(title: String(localized: "Models"), items: viewModel.engineUsage)
            learnedCorrectionsSection
        }
    }

    private var postProcessingCoverageSection: some View {
        AnalyticsCard {
            VStack(alignment: .leading, spacing: LeiseSpacing.s) {
                Text(String(localized: "Post-Processing Coverage"))
                    .font(.headline)

                if viewModel.dictationCount == 0 {
                    emptyAnalyticsMessage(String(localized: "No quality data in this period."))
                } else {
                    Chart {
                        BarMark(
                            x: .value(String(localized: "Dictations"), viewModel.postProcessedCount),
                            y: .value(String(localized: "Category"), String(localized: "All dictations"))
                        )
                        .foregroundStyle(by: .value(String(localized: "Result"), String(localized: "Post-processed")))

                        BarMark(
                            x: .value(String(localized: "Dictations"), max(0, viewModel.dictationCount - viewModel.postProcessedCount)),
                            y: .value(String(localized: "Category"), String(localized: "All dictations"))
                        )
                        .foregroundStyle(by: .value(String(localized: "Result"), String(localized: "Unchanged")))
                    }
                    .chartForegroundStyleScale([
                        String(localized: "Post-processed"): LeiseColor.tint,
                        String(localized: "Unchanged"): Color.secondary.opacity(0.35),
                    ])
                    .chartLegend(position: .bottom, alignment: .leading)
                    .frame(height: 105)
                    .accessibilityLabel(String(localized: "Share of post-processed and unchanged dictations"))
                }
            }
        }
    }

    private var correctionTrendSection: some View {
        AnalyticsCard {
            VStack(alignment: .leading, spacing: LeiseSpacing.s) {
                Text(String(localized: "Manual Corrections Over Time"))
                    .font(.headline)

                if viewModel.chartData.allSatisfy({ $0.manualCorrectionCount == 0 }) {
                    emptyAnalyticsMessage(String(localized: "Manual edits made from now on will appear here."))
                } else {
                    Chart(viewModel.chartData) { point in
                        LineMark(
                            x: .value(String(localized: "Date"), point.date),
                            y: .value(String(localized: "Manual Edits"), point.manualCorrectionCount)
                        )
                        .foregroundStyle(LeiseColor.tint)
                        .symbol(.circle)
                        .interpolationMethod(.catmullRom)
                        .accessibilityLabel(activityLabel(point.date))
                        .accessibilityValue(String(localized: "\(point.manualCorrectionCount) manual edits"))
                    }
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 7)) { value in
                            AxisGridLine()
                            AxisValueLabel {
                                if let date = value.as(Date.self) { Text(activityLabel(date)) }
                            }
                        }
                    }
                    .frame(height: 180)
                    .accessibilityLabel(String(localized: "Manual corrections over time"))
                }
            }
        }
    }

    private var processingBreakdownSection: some View {
        AnalyticsCard {
            VStack(alignment: .leading, spacing: LeiseSpacing.m) {
                Text(String(localized: "Processing Contributions"))
                    .font(.headline)

                if viewModel.pipelineUsage.isEmpty {
                    emptyAnalyticsMessage(String(localized: "No processing steps changed text in this period."))
                } else {
                    let maximum = viewModel.pipelineUsage.map(\.count).max() ?? 1
                    VStack(spacing: LeiseSpacing.s) {
                        ForEach(viewModel.pipelineUsage.prefix(10)) { item in
                            UsageBarRow(
                                label: item.label,
                                value: item.count.formatted(),
                                fraction: Double(item.count) / Double(maximum),
                                accessibilityValue: String(localized: "\(item.count) dictations")
                            )
                        }
                    }
                }
            }
        }
    }

    private func categoryUsageSection(title: String, items: [RankedUsageItem]) -> some View {
        AnalyticsCard {
            VStack(alignment: .leading, spacing: LeiseSpacing.m) {
                Text(title)
                    .font(.headline)
                if items.isEmpty {
                    emptyAnalyticsMessage(String(localized: "No data in this period."))
                } else {
                    let maximum = items.map(\.transcriptionCount).max() ?? 1
                    VStack(spacing: LeiseSpacing.s) {
                        ForEach(items.prefix(10)) { item in
                            UsageBarRow(
                                label: item.label,
                                value: item.transcriptionCount.formatted(),
                                fraction: Double(item.transcriptionCount) / Double(maximum),
                                accessibilityValue: String(localized: "\(item.transcriptionCount) dictations")
                            )
                        }
                    }
                }
            }
        }
    }

    private var learnedCorrectionsSection: some View {
        AnalyticsCard {
            VStack(alignment: .leading, spacing: LeiseSpacing.s) {
                Text(String(localized: "Learned Corrections"))
                    .font(.headline)

                if viewModel.correctionUsage.isEmpty {
                    emptyAnalyticsMessage(String(localized: "Corrections learned from History edits will appear here."))
                } else {
                    ForEach(Array(viewModel.correctionUsage.prefix(10).enumerated()), id: \.element.id) { index, correction in
                        HStack(spacing: LeiseSpacing.s) {
                            Text(correction.original)
                                .foregroundStyle(.secondary)
                            Image(systemName: "arrow.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .accessibilityHidden(true)
                            Text(correction.replacement)
                                .fontWeight(.medium)
                            Spacer()
                            Text(verbatim: "×\(correction.count)")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                        if index < min(viewModel.correctionUsage.count, 10) - 1 { Divider() }
                    }
                }
            }
        }
    }

    // MARK: - Debug

    #if DEBUG
    private var debugMenu: some View {
        Menu {
            Button(String(localized: "Seed Demo Data")) {
                let historyService = ServiceContainer.shared.historyService
                historyService.seedDemoData()
                ServiceContainer.shared.usageStatisticsService.replaceWithHistoryRecords(historyService.records)
            }
            Divider()
            Button(String(localized: "Clear All Data"), role: .destructive) {
                ServiceContainer.shared.historyService.clearAll()
                ServiceContainer.shared.usageStatisticsService.clearUsageStatistics()
            }
        } label: {
            Image(systemName: "ladybug")
                .accessibilityLabel(String(localized: "Debug Actions"))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(String(localized: "Debug Actions"))
    }
    #endif

    // MARK: - Formatting

    private var activityGranularityLabel: String {
        switch viewModel.chartGranularity {
        case .day: String(localized: "Daily")
        case .week: String(localized: "Weekly")
        case .month: String(localized: "Monthly")
        }
    }

    private var activityCalendarComponent: Calendar.Component {
        switch viewModel.chartGranularity {
        case .day: .day
        case .week: .weekOfYear
        case .month: .month
        }
    }

    private var activityChartEdgePadding: CGFloat {
        viewModel.selectedTimePeriod == .allTime ? LeiseSpacing.l : 0
    }

    private func activityLabel(_ date: Date) -> String {
        switch viewModel.chartGranularity {
        case .day: date.formatted(.dateTime.month(.abbreviated).day())
        case .week: String(localized: "Week of \(date.formatted(.dateTime.month(.abbreviated).day()))")
        case .month: date.formatted(.dateTime.month(.abbreviated).year())
        }
    }

    private var heatmapWeekdayDomain: [String] {
        (0..<7).compactMap { index in
            viewModel.habitHeatmap.first(where: { $0.weekdayIndex == index })?.weekdayKey
        }
    }

    private func heatmapWeekdayLabel(for key: String) -> String? {
        viewModel.habitHeatmap.first(where: { $0.weekdayKey == key })?.weekdayLabel
    }

    private var heatmapHourDomain: [String] {
        stride(from: 0, through: 20, by: 4).map { String(format: "%02d", $0) }
    }

    private func heatmapColor(for count: Int) -> Color {
        let maximum = max(viewModel.habitHeatmap.map(\.count).max() ?? 0, 1)
        guard count > 0 else { return Color.secondary.opacity(0.08) }
        return LeiseColor.tint.opacity(0.2 + 0.8 * Double(count) / Double(maximum))
    }

    private func appValueLabel(_ item: RankedUsageItem) -> String {
        switch viewModel.selectedAppMetric {
        case .dictations: item.transcriptionCount.formatted()
        case .words: item.words.formatted()
        case .time: Duration.seconds(item.durationSeconds.rounded())
            .formatted(.units(allowed: [.minutes, .seconds], width: .narrow))
        }
    }

    private func emptyAnalyticsMessage(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 54, alignment: .center)
    }
}

private struct AnalyticsCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(LeiseSpacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: LeiseRadius.group, style: .continuous))
    }
}

private struct UsageBarRow: View {
    var bundleIdentifier: String?
    let label: String
    let value: String
    let fraction: Double
    let accessibilityValue: String
    var action: (() -> Void)?

    var body: some View {
        Group {
            if let action {
                Button(action: action) { rowContent }
                    .buttonStyle(.plain)
            } else {
                rowContent
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(accessibilityValue)
        .accessibilityAddTraits(action == nil ? [] : .isButton)
    }

    private var rowContent: some View {
        HStack(spacing: LeiseSpacing.s) {
            if let bundleIdentifier {
                AppGlyph(bundleIdentifier: bundleIdentifier, size: 16)
            }
            Text(label)
                .lineLimit(1)
                .frame(width: 140, alignment: .leading)
            GeometryReader { geometry in
                RoundedRectangle(cornerRadius: LeiseRadius.control, style: .continuous)
                    .fill(LeiseColor.tint.opacity(0.75))
                    .frame(width: max(2, geometry.size.width * min(max(fraction, 0), 1)))
            }
            .frame(height: 12)
            Text(value)
                .font(.callout.monospacedDigit())
                .frame(minWidth: 48, alignment: .trailing)
            if action != nil {
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
    }
}

private struct StatCard: View {
    let title: String
    let value: String
    let systemImage: String
    var trend: Double?
    var subtitle: String?

    var body: some View {
        VStack(spacing: LeiseSpacing.xs) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(LeiseColor.tint)
                .accessibilityHidden(true)
            Text(value)
                .font(.title2.bold())
                .fontDesign(.rounded)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .contentTransition(.numericText())
            if let trend { trendLabel(trend) }
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .top)
        .padding(.vertical, LeiseSpacing.m)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: LeiseRadius.group, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: "\(title), \(value)"))
    }

    /// Direction as symbol and number; no color, because neither direction
    /// is good or bad on its own.
    private func trendLabel(_ percent: Double) -> some View {
        HStack(spacing: 2) {
            Image(systemName: percent >= 0 ? "arrow.up.right" : "arrow.down.right")
            Text((abs(percent) / 100).formatted(.percent.precision(.fractionLength(0))))
                .monospacedDigit()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}
