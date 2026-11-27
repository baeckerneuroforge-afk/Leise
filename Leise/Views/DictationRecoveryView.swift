import AppKit
import SwiftUI

// Failed dictations live in Verlauf as entries of their own: the audio was
// kept, so they can be transcribed again with the dictation model.

/// "Nicht transkribiert" in the history list.
struct RecoveryListRow: View {
    let item: DictationRecoveryViewModel.RecoveryItem

    var body: some View {
        HStack(alignment: .top, spacing: LeiseSpacing.m) {
            Group {
                if item.isProcessing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(LeiseColor.record)
                }
            }
            .frame(width: 20, height: 20)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "Not transcribed"))
                    .fontWeight(.semibold)
                Text(RecoveryText.meta(for: item))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

/// The detail of a failed dictation: what happened and what to do.
struct RecoveryDetailView: View {
    let item: DictationRecoveryViewModel.RecoveryItem
    @ObservedObject var recovery: DictationRecoveryViewModel
    @ObservedObject var modelManager: ModelManagerService

    @State private var showsDiscardConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: LeiseSpacing.l) {
            Label {
                Text(String(localized: "Not transcribed"))
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(LeiseColor.record)
            }
            .font(.title3.weight(.semibold))

            Text(RecoveryText.explanation(for: item))
                .font(.title3)
                .lineSpacing(LeiseSpacing.xs)
                .fixedSize(horizontal: false, vertical: true)

            if let errorMessage = item.errorMessage, !item.isProcessing {
                StatusLabel(kind: .error, text: String(localized: "Last attempt: \(errorMessage)"))
            }

            if item.isProcessing {
                StatusLabel(kind: .working, text: String(localized: "Transcribing…"))
            } else if !recovery.canTranscribe {
                HStack(spacing: LeiseSpacing.m) {
                    ModelStatusLabel(modelManager: modelManager, includesModelName: true)
                    Button(String(localized: "Open Dictation Settings")) {
                        SettingsNavigationCoordinator.shared.show(.model)
                    }
                    .buttonStyle(.link)
                }
            }

            HStack(spacing: LeiseSpacing.s) {
                Button {
                    recovery.retranscribe(item)
                } label: {
                    Label(String(localized: "Transcribe Again"), systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!recovery.canTranscribe || item.isProcessing)

                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([item.url])
                } label: {
                    Label(String(localized: "Show in Finder"), systemImage: "folder")
                }

                Button(role: .destructive) {
                    showsDiscardConfirmation = true
                } label: {
                    Text(String(localized: "Discard…"))
                }
                .disabled(item.isProcessing)
            }
        }
        .frame(maxWidth: 560, alignment: .leading)
        .confirmationDialog(
            String(localized: "Discard This Recording?"),
            isPresented: $showsDiscardConfirmation
        ) {
            Button(String(localized: "Discard"), role: .destructive) {
                withLeiseAnimation(LeiseMotion.ui) {
                    recovery.discardRecovery(item)
                }
            }
        } message: {
            Text(String(localized: "The audio of this recording is deleted. This can’t be undone."))
        }
    }
}

enum RecoveryText {
    static func time(of item: DictationRecoveryViewModel.RecoveryItem) -> String {
        item.recordedAt.formatted(date: .omitted, time: .shortened)
    }

    static func duration(of item: DictationRecoveryViewModel.RecoveryItem) -> String? {
        item.duration.map(HistoryDuration.format)
    }

    /// "09:58 · 0:48 · Keine Sprache erkannt"
    static func meta(for item: DictationRecoveryViewModel.RecoveryItem) -> String {
        if item.isProcessing {
            return String(localized: "Transcribing…")
        }
        return [time(of: item), duration(of: item), item.errorMessage]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    static func explanation(for item: DictationRecoveryViewModel.RecoveryItem) -> String {
        let time = time(of: item)
        if let duration = duration(of: item) {
            return String(localized: "This recording from \(time) (\(duration)) was not transcribed. The audio is safe.")
        }
        return String(localized: "This recording from \(time) was not transcribed. The audio is safe.")
    }
}

/// "0:48", "12:04", "1:02:10".
enum HistoryDuration {
    static func format(_ seconds: TimeInterval) -> String {
        let total = max(Int(seconds.rounded()), 0)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let remainder = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainder)
        }
        return String(format: "%d:%02d", minutes, remainder)
    }
}
