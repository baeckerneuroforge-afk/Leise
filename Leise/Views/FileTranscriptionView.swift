import LeiseCore
import SwiftUI
import UniformTypeIdentifiers

/// Transkribieren › Datei: drop audio or video files, transcribe them with
/// the dictation model, copy or export the text.
struct FileTranscriptionView: View {
    @ObservedObject private var viewModel = ServiceContainer.shared.fileTranscriptionViewModel
    @ObservedObject private var settings = ServiceContainer.shared.settingsViewModel

    @State private var isDropTargeted = false
    @State private var showsFilePicker = false
    @State private var expandedFileID: UUID?

    private var isProcessing: Bool { viewModel.batchState == .processing }

    var body: some View {
        SettingsPage(.transcribe) {
            if !viewModel.files.isEmpty {
                Section {
                    ForEach(viewModel.files) { item in
                        FileRow(
                            item: item,
                            isExpanded: expandedFileID == item.id,
                            canRemove: !isProcessing,
                            viewModel: viewModel,
                            toggleExpanded: {
                                withLeiseAnimation(LeiseMotion.shape) {
                                    expandedFileID = expandedFileID == item.id ? nil : item.id
                                }
                            }
                        )
                    }
                } header: {
                    VStack(spacing: LeiseSpacing.xxl) {
                        dropZone
                        Text(String(localized: "Files"))
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .textCase(nil)
                } footer: {
                    actions
                        .padding(.top, LeiseSpacing.s)
                }
            }

            Section {
                SpokenLanguagePicker(
                    selection: $viewModel.languageSelection,
                    languages: settings.availableLanguages,
                    inheritTitle: String(localized: "Same as Dictation")
                ) {
                    Text(String(localized: "Language"))
                }
                .disabled(isProcessing)
            } header: {
                if viewModel.files.isEmpty {
                    dropZone
                        .textCase(nil)
                        .padding(.bottom, LeiseSpacing.l)
                        .settingsRow(.fileTranscription)
                }
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted, perform: handleDrop)
        .fileImporter(
            isPresented: $showsFilePicker,
            allowedContentTypes: FileTranscriptionViewModel.allowedContentTypes,
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                withLeiseAnimation(LeiseMotion.ui) { viewModel.addFiles(urls) }
            }
        }
        .onAppear {
            if viewModel.showFilePickerFromMenu {
                viewModel.showFilePickerFromMenu = false
                showsFilePicker = true
            }
        }
    }

    // MARK: Drop zone

    private var dropZone: some View {
        DropZone(isTargeted: isDropTargeted) {
            showsFilePicker = true
        }
    }

    // MARK: Actions

    private var actions: some View {
        HStack(spacing: LeiseSpacing.s) {
            Button(String(localized: "Add Files…")) {
                showsFilePicker = true
            }
            .disabled(isProcessing)

            Button(String(localized: "Clear List"), role: .destructive) {
                withLeiseAnimation(LeiseMotion.ui) { viewModel.reset() }
            }
            .disabled(isProcessing)

            Spacer()

            if viewModel.hasResults {
                Menu(String(localized: "Export All")) {
                    Button(String(localized: "Copy All Text")) { viewModel.copyAllText() }
                    Divider()
                    Button(String(localized: "Export All as SRT")) { viewModel.exportAllSubtitles(format: .srt) }
                    Button(String(localized: "Export All as VTT")) { viewModel.exportAllSubtitles(format: .vtt) }
                }
                .fixedSize()
            }

            if isProcessing {
                Text(String(localized: "\(viewModel.processedFiles) of \(viewModel.totalFiles)"))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Button(String(localized: "Stop")) {
                    viewModel.cancelTranscription()
                }
            } else {
                Button(String(localized: "Transcribe All")) {
                    viewModel.transcribeAll()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canTranscribe)
            }
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            handled = true
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                guard let data = data as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil),
                      AudioFileService.supportedExtensions.contains(url.pathExtension.lowercased()) else { return }
                Task { @MainActor in
                    withLeiseAnimation(LeiseMotion.ui) { viewModel.addFiles([url]) }
                }
            }
        }
        return handled
    }
}

// MARK: - Drop zone

private struct DropZone: View {
    let isTargeted: Bool
    let chooseFiles: () -> Void

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        VStack(spacing: LeiseSpacing.s) {
            Image(systemName: "square.and.arrow.down")
                .font(.title)
                .foregroundStyle(LeiseColor.tint)
                .accessibilityHidden(true)
            Text(String(localized: "Drop an audio or video file here"))
                .font(.headline)
                .foregroundStyle(.primary)
            Text(String(localized: "MP3, M4A, WAV, MP4 and more"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button(String(localized: "Choose File…"), action: chooseFiles)
                .padding(.top, LeiseSpacing.xs)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, LeiseSpacing.xxxl)
        .padding(.horizontal, LeiseSpacing.l)
        .background {
            RoundedRectangle(cornerRadius: LeiseRadius.panel, style: .continuous)
                .fill(LeiseColor.tint.opacity(isTargeted ? 0.12 : 0))
        }
        .overlay {
            RoundedRectangle(cornerRadius: LeiseRadius.panel, style: .continuous)
                .strokeBorder(
                    isTargeted ? AnyShapeStyle(LeiseColor.tint) : AnyShapeStyle(Color.primary.opacity(contrast == .increased ? 0.45 : 0.2)),
                    style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                )
        }
        .leiseAnimation(LeiseMotion.micro, value: isTargeted)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Drop zone for audio and video files"))
    }
}

// MARK: - File row

private struct FileRow: View {
    let item: FileTranscriptionViewModel.FileItem
    let isExpanded: Bool
    let canRemove: Bool
    @ObservedObject var viewModel: FileTranscriptionViewModel
    let toggleExpanded: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: LeiseSpacing.s) {
            HStack(spacing: LeiseSpacing.m) {
                statusSymbol
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.fileName)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    subtitle
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    if item.state == .done { toggleExpanded() }
                }

                if item.state == .done {
                    Button {
                        viewModel.copyText(for: item)
                        AccessibilityNotification.Announcement(String(localized: "Copied")).post()
                    } label: {
                        Label(String(localized: "Copy"), systemImage: "doc.on.doc")
                    }

                    if let result = item.result, !result.segments.isEmpty {
                        Menu(String(localized: "Export")) {
                            Button(String(localized: "As SRT")) { viewModel.exportSubtitles(for: item, format: .srt) }
                            Button(String(localized: "As VTT")) { viewModel.exportSubtitles(for: item, format: .vtt) }
                        }
                        .fixedSize()
                    }
                }

                if canRemove {
                    Button {
                        withLeiseAnimation(LeiseMotion.ui) { viewModel.removeFile(item) }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.borderless)
                    .help(String(localized: "Remove \(item.fileName)"))
                    .accessibilityLabel(String(localized: "Remove \(item.fileName)"))
                }
            }

            if item.state == .loading || item.state == .transcribing {
                if let progress = item.progressFraction {
                    ProgressView(value: progress)
                        .controlSize(.small)
                }
                if let progressText = item.progressText, !progressText.isEmpty {
                    Text(progressText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            if isExpanded, let result = item.result {
                Text(result.text)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var statusSymbol: some View {
        switch item.state {
        case .pending:
            Image(systemName: "circle.dashed")
                .foregroundStyle(.secondary)
                .accessibilityLabel(String(localized: "Pending"))
        case .loading, .transcribing:
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel(String(localized: "Transcribing"))
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(LeiseColor.ready)
                .accessibilityLabel(String(localized: "Done"))
        case .error:
            Image(systemName: "xmark.octagon.fill")
                .foregroundStyle(LeiseColor.record)
                .accessibilityLabel(String(localized: "Error"))
        case .cancelled:
            Image(systemName: "stop.circle")
                .foregroundStyle(.secondary)
                .accessibilityLabel(String(localized: "Cancelled"))
        }
    }

    @ViewBuilder
    private var subtitle: some View {
        Group {
            if let error = item.errorMessage {
                Text(error)
            } else if let result = item.result {
                Text(String(localized: "\(HistoryDuration.format(result.duration)) · done"))
            } else if let phase = item.phaseDescription {
                Text(phase)
            } else if item.state == .cancelled {
                Text(String(localized: "Stopped"))
            } else {
                Text(String(localized: "Ready to transcribe"))
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .monospacedDigit()
        .lineLimit(2)
    }
}
