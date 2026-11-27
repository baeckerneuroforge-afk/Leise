import SwiftUI

/// Erweitert › Diagnose › Fehlerprotokoll: the recorded errors, newest first,
/// inside a disclosure row.
struct ErrorLogDisclosure: View {
    @ObservedObject var errorLogService: ErrorLogService

    @State private var isExpanded = false
    @State private var showsClearConfirmation = false
    @Environment(\.settingsHighlightedRow) private var highlightedRow

    /// More rows than this belong in the exported diagnostics.
    private static let visibleEntryLimit = 50

    private var entries: [ErrorLogEntry] { errorLogService.entries }

    private var countText: String {
        switch entries.count {
        case 0: String(localized: "None")
        case 1: String(localized: "1 entry")
        default: String(localized: "\(entries.count) entries")
        }
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            if entries.isEmpty {
                Label(String(localized: "No errors recorded."), systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(entries.prefix(Self.visibleEntryLimit)) { entry in
                    ErrorLogRow(entry: entry)
                }
                if entries.count > Self.visibleEntryLimit {
                    Text(String(localized: "\(entries.count - Self.visibleEntryLimit) older entries are in the exported diagnostics."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Spacer()
                    Button(String(localized: "Clear Log…"), role: .destructive) {
                        showsClearConfirmation = true
                    }
                }
            }
        } label: {
            HStack {
                Text(SettingsRow.errorLog.title)
                Spacer()
                Text(countText)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        }
        .settingsRow(.errorLog)
        .onChange(of: highlightedRow) { _, row in
            if row == .errorLog {
                withLeiseAnimation(LeiseMotion.shape) { isExpanded = true }
            }
        }
        .confirmationDialog(
            String(localized: "Clear Error Log?"),
            isPresented: $showsClearConfirmation
        ) {
            Button(String(localized: "Clear All"), role: .destructive) {
                withLeiseAnimation(LeiseMotion.ui) {
                    errorLogService.clearAll()
                }
            }
        } message: {
            Text(String(localized: "This will permanently delete all recorded errors."))
        }
    }
}

private struct ErrorLogRow: View {
    let entry: ErrorLogEntry

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: LeiseSpacing.m) {
            Image(systemName: entry.categoryIcon)
                .foregroundStyle(LeiseColor.record)
                .frame(width: 16)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.message)
                    .lineLimit(3)
                    .textSelection(.enabled)
                Text(verbatim: "\(entry.categoryDisplayName) · \(entry.timestamp.formatted(date: .abbreviated, time: .shortened))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
