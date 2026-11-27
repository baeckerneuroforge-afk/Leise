import AppKit
import SwiftUI

/// Transkribieren › Aufnahme: a large clock, the record button and the level,
/// then where the recording goes and whether it gets a transcript.
struct AudioRecorderView: View {
    @ObservedObject var viewModel: AudioRecorderViewModel
    /// Called after a recording was handed to file transcription.
    var showFiles: () -> Void = {}

    @ObservedObject private var settings = ServiceContainer.shared.settingsViewModel
    @ObservedObject private var audioDevice = ServiceContainer.shared.audioDeviceService
    @ObservedObject private var modelManager = ServiceContainer.shared.modelManagerService
    @ObservedObject private var dictation = ServiceContainer.shared.dictationViewModel

    private var isEditingLocked: Bool {
        viewModel.state != .idle
    }

    var body: some View {
        SettingsPage(.transcribe) {
            Section {
                micToggle

                Toggle(isOn: $viewModel.systemAudioEnabled) {
                    SettingsRowLabel(
                        title: SettingsRow.systemAudio.title,
                        subtitle: String(localized: "For calls: also records the other participants."),
                        info: String(localized: "recorder.systemAudioPermission")
                    )
                }
                .settingsRow(.systemAudio)
                .disabled(isEditingLocked)

                if viewModel.micEnabled && viewModel.systemAudioEnabled {
                    Picker(String(localized: "Tracks"), selection: $viewModel.trackMode) {
                        ForEach(AudioRecorderService.TrackMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .disabled(isEditingLocked)

                    Picker(selection: $viewModel.micDuckingMode) {
                        ForEach(AudioRecorderService.MicDuckingMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    } label: {
                        SettingsRowLabel(
                            title: String(localized: "Echo Handling"),
                            info: String(localized: "Affects only Leise recordings and transcriptions, not your live meeting microphone.")
                        )
                    }
                    .disabled(isEditingLocked || viewModel.trackMode == .separate)
                }

                saveLocationRow

                Picker(String(localized: "Format"), selection: $viewModel.outputFormat) {
                    Text(verbatim: "M4A (AAC)").tag(AudioRecorderService.OutputFormat.m4a)
                    Text(verbatim: "WAV").tag(AudioRecorderService.OutputFormat.wav)
                }
                .disabled(isEditingLocked)
            } header: {
                VStack(spacing: LeiseSpacing.xxl) {
                    RecorderHero(viewModel: viewModel)
                    Text(String(localized: "Source"))
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .textCase(nil)
            }

            Section {
                Toggle(String(localized: "Create transcript"), isOn: $viewModel.transcriptionEnabled)
                    .disabled(isEditingLocked)

                SpokenLanguagePicker(
                    selection: $viewModel.languageSelection,
                    languages: settings.availableLanguages,
                    inheritTitle: String(localized: "Same as Dictation")
                ) {
                    Text(String(localized: "Language"))
                }
                .disabled(isEditingLocked || !viewModel.transcriptionEnabled)

                Toggle(isOn: $viewModel.livePreviewEnabled) {
                    SettingsRowLabel(
                        title: String(localized: "Live transcript while recording"),
                        info: String(localized: "Shows the recognized words while you record. Uses a lighter, faster pass; the saved transcript is made at the end.")
                    )
                }
                .disabled(isEditingLocked || !viewModel.transcriptionEnabled)
            } header: {
                Text(String(localized: "Transcript"))
            }

            Section {
                if viewModel.recordings.isEmpty {
                    Text(emptyRecordingsText)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(viewModel.recordings) { item in
                        RecordingRow(item: item, viewModel: viewModel, showFiles: showFiles)
                    }
                }
            } header: {
                Text(String(localized: "Recordings"))
            } footer: {
                if !viewModel.recordings.isEmpty {
                    Button(String(localized: "Open Recordings Folder")) {
                        viewModel.openRecordingsFolder()
                    }
                    .buttonStyle(.link)
                }
            }
        }
        .onAppear {
            modelManager.restoreProviderSelection()
            viewModel.reconcileSelectionWithAvailableEngines()
            viewModel.loadRecordings()
        }
    }

    private var micToggle: some View {
        Toggle(isOn: $viewModel.micEnabled) {
            SettingsRowLabel(
                title: String(localized: "Microphone"),
                subtitle: audioDevice.selectedDevice.map { audioDevice.displayName(for: $0) }
                    ?? String(localized: "System Default")
            )
        }
        .disabled(isEditingLocked)
    }

    private var emptyRecordingsText: String {
        _ = dictation.hotkeyLabelsVersion
        let shortcut = dictation.hotkeys(for: .recorderToggle).first.map(HotkeyService.displayName(for:))
        if let shortcut {
            return String(localized: "No recordings yet. The red button above starts one, or press \(shortcut) in any app.")
        }
        return String(localized: "No recordings yet. The red button above starts one.")
    }

    private var saveLocationRow: some View {
        LabeledContent {
            HStack(spacing: LeiseSpacing.s) {
                Text(viewModel.outputDirectoryDisplayPath)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(viewModel.outputDirectory.path)
                Button(String(localized: "Change…"), action: chooseOutputFolder)
                if viewModel.selectedOutputDirectory != nil {
                    Button {
                        viewModel.useDefaultOutputDirectory()
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .buttonStyle(.borderless)
                    .help(String(localized: "recorder.useDefaultOutputFolder"))
                    .accessibilityLabel(String(localized: "recorder.useDefaultOutputFolder"))
                }
            }
        } label: {
            Text(SettingsRow.recordingsFolder.title)
        }
        .settingsRow(.recordingsFolder)
        .disabled(isEditingLocked)
    }

    private func chooseOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = String(localized: "Choose Folder")
        panel.message = String(localized: "recorder.outputFolder.pickerMessage")

        let currentDirectory = viewModel.outputDirectory
        panel.directoryURL = FileManager.default.fileExists(atPath: currentDirectory.path)
            ? currentDirectory
            : currentDirectory.deletingLastPathComponent()

        panel.begin { response in
            guard response == .OK, let directory = panel.url else { return }
            Task { @MainActor in
                viewModel.setOutputDirectory(directory)
            }
        }
    }
}

// MARK: - Hero

private struct RecorderHero: View {
    @ObservedObject var viewModel: AudioRecorderViewModel

    @ScaledMetric(relativeTo: .largeTitle) private var clockSize: CGFloat = 52

    private var isRecording: Bool { viewModel.state == .recording }

    var body: some View {
        VStack(spacing: LeiseSpacing.l) {
            Text(Self.clock(viewModel.duration))
                .font(.system(size: clockSize, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(isRecording ? .primary : .secondary)
                .accessibilityLabel(String(localized: "Recording time"))
                .accessibilityValue(Self.clock(viewModel.duration))

            RecordButton(isRecording: isRecording) {
                viewModel.toggleRecording()
                AccessibilityNotification.Announcement(isRecording
                    ? String(localized: "Recording stopped")
                    : String(localized: "Recording started")).post()
            }
            .disabled(!viewModel.canToggleRecording)

            LevelMeter(
                level: max(viewModel.micLevel, viewModel.systemLevel),
                isActive: isRecording,
                tint: LeiseColor.record,
                barCount: 24
            )

            status
        }
        .frame(maxWidth: .infinity)
        .padding(.top, LeiseSpacing.s)
    }

    @ViewBuilder
    private var status: some View {
        if viewModel.state == .finalizing {
            StatusLabel(kind: .working, text: String(localized: "Transcribing…"))
        } else if let error = viewModel.errorMessage {
            StatusLabel(kind: .error, text: error)
        } else if !viewModel.micEnabled && !viewModel.systemAudioEnabled {
            Text(String(localized: "Turn on the microphone or system audio to record."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        if let warning = viewModel.systemAudioWarningMessage {
            Label(warning, systemImage: "speaker.slash")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    /// "00:00", or "1:02:10" past an hour.
    static func clock(_ duration: TimeInterval) -> String {
        let total = max(Int(duration), 0)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

/// The record button: a red circle that becomes a rounded square while
/// recording.
private struct RecordButton: View {
    let isRecording: Bool
    let action: () -> Void

    private static let restingSize: CGFloat = 22
    private static let recordingSize: CGFloat = 18

    var body: some View {
        Button(action: action) {
            RoundedRectangle(
                cornerRadius: isRecording ? LeiseRadius.control : Self.restingSize / 2,
                style: .continuous
            )
            .fill(LeiseColor.record)
            .frame(
                width: isRecording ? Self.recordingSize : Self.restingSize,
                height: isRecording ? Self.recordingSize : Self.restingSize
            )
        }
        .buttonStyle(RecordButtonStyle())
        .leiseAnimation(LeiseMotion.ui, value: isRecording)
        .accessibilityLabel(isRecording ? String(localized: "Stop Recording") : String(localized: "Start Recording"))
        .help(isRecording ? String(localized: "Stop Recording") : String(localized: "Start Recording"))
    }
}

private struct RecordButtonStyle: ButtonStyle {
    private static let diameter: CGFloat = 56

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: Self.diameter, height: Self.diameter)
            .background(Circle().fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(
                Circle().strokeBorder(Color.primary.opacity(contrast == .increased ? 0.35 : 0.12), lineWidth: 1)
            )
            .contentShape(Circle())
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.95 : 1)
            .opacity(isEnabled ? 1 : 0.45)
            .animation(LeiseMotion.adaptive(LeiseMotion.micro, reduceMotion: reduceMotion), value: configuration.isPressed)
    }
}

// MARK: - Recordings

private struct RecordingRow: View {
    let item: AudioRecorderViewModel.RecordingItem
    @ObservedObject var viewModel: AudioRecorderViewModel
    let showFiles: () -> Void

    @State private var showsTranscript = false

    private var subtitle: String {
        [
            item.date.formatted(date: .abbreviated, time: .shortened),
            viewModel.formattedDuration(item.duration),
            viewModel.formattedFileSize(item.fileSize),
        ].joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LeiseSpacing.s) {
            HStack(spacing: LeiseSpacing.s) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.fileName)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Spacer(minLength: LeiseSpacing.s)

                Button {
                    NSWorkspace.shared.open(item.url)
                } label: {
                    Image(systemName: "play.fill")
                }
                .help(String(localized: "Play"))
                .accessibilityLabel(String(localized: "Play"))

                if item.transcript != nil {
                    Button {
                        withLeiseAnimation(LeiseMotion.shape) { showsTranscript.toggle() }
                    } label: {
                        Image(systemName: "text.quote")
                            .foregroundStyle(showsTranscript ? LeiseColor.tint : .secondary)
                    }
                    .help(String(localized: "recorder.showTranscript"))
                    .accessibilityLabel(String(localized: "recorder.showTranscript"))
                    .accessibilityValue(showsTranscript ? String(localized: "Expanded") : String(localized: "Collapsed"))
                } else {
                    Button {
                        viewModel.transcribeRecording(item)
                        showFiles()
                    } label: {
                        Image(systemName: "text.viewfinder")
                    }
                    .help(String(localized: "recorder.transcribe"))
                    .accessibilityLabel(String(localized: "recorder.transcribe"))
                }

                Button {
                    viewModel.revealInFinder(item)
                } label: {
                    Image(systemName: "folder")
                }
                .help(String(localized: "Show in Finder"))
                .accessibilityLabel(String(localized: "Show in Finder"))
            }
            .buttonStyle(.borderless)

            if let failureSummary = viewModel.transcriptionFailureSummary(for: item) {
                StatusLabel(kind: .error, text: failureSummary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if showsTranscript, let transcript = item.transcript {
                VStack(alignment: .leading, spacing: LeiseSpacing.xs) {
                    Text(transcript)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(String(localized: "recorder.copyTranscript")) {
                        viewModel.copyTranscript(transcript)
                        AccessibilityNotification.Announcement(String(localized: "Copied")).post()
                    }
                    .buttonStyle(.link)
                }
                .transition(.opacity)
            }
        }
        .contextMenu {
            if let transcript = item.transcript {
                Button(String(localized: "recorder.copyTranscript")) {
                    viewModel.copyTranscript(transcript)
                }
                Divider()
            }
            Button(String(localized: "recorder.transcribe")) {
                viewModel.transcribeRecording(item)
                showFiles()
            }
            Button(String(localized: "Show in Finder")) {
                viewModel.revealInFinder(item)
            }
            Divider()
            Button(String(localized: "recorder.delete"), role: .destructive) {
                withLeiseAnimation(LeiseMotion.ui) { viewModel.deleteRecording(item) }
            }
        }
    }
}
