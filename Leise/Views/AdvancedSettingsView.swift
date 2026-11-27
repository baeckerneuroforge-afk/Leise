import SwiftUI
import UniformTypeIdentifiers

/// Erweitert: backups, diagnostics, fine-tuning, spoken punctuation, updates.
struct AdvancedSettingsView: View {
    @ObservedObject private var modelManager = ServiceContainer.shared.modelManagerService
    @ObservedObject private var dictation = ServiceContainer.shared.dictationViewModel
    @ObservedObject private var errorLogService = ServiceContainer.shared.errorLogService
    @AppStorage(UserDefaultsKeys.updateChannel)
    private var updateChannelRawValue = AppConstants.defaultReleaseChannel.rawValue

    @State private var showsImportConfirmation = false
    @State private var pendingImportURL: URL?
    @State private var pendingImportSummary: UserDataBackupSummary?
    @State private var notice: SettingsNotice?
    @State private var showsUsageData = false

    private let backupService = ServiceContainer.shared.userDataBackupService

    var body: some View {
        SettingsPage(.advanced) {
            Section {
                LabeledContent {
                    Button(String(localized: "Export…"), action: exportUserData)
                } label: {
                    SettingsRowLabel(
                        title: SettingsRow.backup.title,
                        subtitle: String(localized: "Saves Leise’s data in one file."),
                        info: String(localized: "Contains settings, dictionary, app rules and history. Downloaded models, audio recordings and your own sounds are not included.")
                    )
                }
                .settingsRow(.backup)

                LabeledContent {
                    Button(String(localized: "Import…"), action: chooseBackupToImport)
                } label: {
                    Text(String(localized: "Import backup"))
                }
            } header: {
                Text(String(localized: "Data"))
            }

            Section {
                ErrorLogDisclosure(errorLogService: errorLogService)

                LabeledContent {
                    Button(String(localized: "Export…"), action: exportDiagnostics)
                } label: {
                    SettingsRowLabel(
                        title: SettingsRow.exportDiagnostics.title,
                        subtitle: String(localized: "For bug reports."),
                        info: String(localized: "A JSON report with app, system, permission, settings and audio-device details, plus the error log.")
                    )
                }
                .settingsRow(.exportDiagnostics)

                LabeledContent {
                    Button(String(localized: "Show…")) { showsUsageData = true }
                } label: {
                    SettingsRowLabel(
                        title: SettingsRow.usageData.title,
                        subtitle: String(localized: "Quality, corrections, models.")
                    )
                }
                .settingsRow(.usageData)
            } header: {
                Text(String(localized: "Diagnostics"))
            }

            Section {
                Picker(selection: $modelManager.autoUnloadSeconds) {
                    Text(String(localized: "Never")).tag(0)
                    Divider()
                    Text(String(localized: "Immediate")).tag(-1)
                    Text(String(localized: "After 2 minutes")).tag(120)
                    Text(String(localized: "After 5 minutes")).tag(300)
                    Text(String(localized: "After 10 minutes")).tag(600)
                    Text(String(localized: "After 30 minutes")).tag(1800)
                    Text(String(localized: "After 1 hour")).tag(3600)
                } label: {
                    SettingsRowLabel(
                        title: SettingsRow.modelUnload.title,
                        info: String(localized: "By default the model stays in memory so dictation starts at once. With unloading, Leise loads it again when you start the next dictation.")
                    )
                }
                .settingsRow(.modelUnload)

                Toggle(isOn: Binding(
                    get: { !dictation.transcribeShortQuietClipsAggressively },
                    set: { dictation.transcribeShortQuietClipsAggressively = !$0 }
                )) {
                    SettingsRowLabel(
                        title: SettingsRow.shortQuietClips.title,
                        info: String(localized: "When off, Leise also transcribes very short or quiet recordings instead of treating them as silence. Accidental taps are always discarded.")
                    )
                }
                .settingsRow(.shortQuietClips)

                Toggle(isOn: $dictation.microphoneBoostEnabled) {
                    SettingsRowLabel(
                        title: SettingsRow.whisperMode.title,
                        subtitle: String(localized: "Raises quiet voices automatically."),
                        info: String(localized: "Adjusts the level so whispered sentences are recognized too. In loud rooms the noise gets louder as well.")
                    )
                }
                .settingsRow(.whisperMode)
            } header: {
                Text(String(localized: "Fine-Tuning"))
            }

            SpokenPunctuationSettingsSection()

            Section {
                Picker(selection: updateChannel) {
                    ForEach(AppConstants.ReleaseChannel.allCases, id: \.self) { channel in
                        Text(channel.selectionDisplayName).tag(channel)
                    }
                } label: {
                    SettingsRowLabel(
                        title: SettingsRow.updateChannel.title,
                        info: selectedUpdateChannel.updateDescription
                    )
                }
                .settingsRow(.updateChannel)

                LabeledContent {
                    Button(String(localized: "Check Now")) {
                        UpdateChecker.shared?.checkForUpdates()
                    }
                    .disabled(UpdateChecker.shared?.canCheckForUpdates() != true)
                } label: {
                    Text(String(localized: "Check for updates"))
                }
            } header: {
                Text(String(localized: "Updates"))
            }

            Section {
                LabeledContent {
                    Button(String(localized: "Open Again…"), action: openSetup)
                } label: {
                    SettingsRowLabel(
                        title: SettingsRow.setupAssistant.title,
                        subtitle: String(localized: "Walks you through the first steps again. Your settings stay as they are.")
                    )
                }
                .settingsRow(.setupAssistant)
            }
        }
        .sheet(isPresented: $showsUsageData) {
            UsageAnalyticsSheet()
        }
        .confirmationDialog(
            String(localized: "Import Backup?"),
            isPresented: $showsImportConfirmation
        ) {
            Button(String(localized: "Replace Current Data"), role: .destructive) {
                importPendingBackup()
            }
            Button(String(localized: "Cancel"), role: .cancel) {
                pendingImportURL = nil
                pendingImportSummary = nil
            }
        } message: {
            if let summary = pendingImportSummary {
                Text(String(localized: "This replaces current settings and user data with \(summary.dictionaryEntryCount) dictionary entries, \(summary.profileCount) profiles, and \(summary.historyRecordCount) history records. This cannot be undone unless you export a backup first."))
            }
        }
        .alert(item: $notice) { notice in
            Alert(
                title: Text(notice.title),
                message: Text(notice.message),
                dismissButton: .default(Text(String(localized: "OK")))
            )
        }
    }

    // MARK: Updates

    private var selectedUpdateChannel: AppConstants.ReleaseChannel {
        AppConstants.ReleaseChannel(rawValue: updateChannelRawValue) ?? AppConstants.defaultReleaseChannel
    }

    private var updateChannel: Binding<AppConstants.ReleaseChannel> {
        Binding(
            get: { selectedUpdateChannel },
            set: { newChannel in
                guard selectedUpdateChannel != newChannel else { return }
                updateChannelRawValue = newChannel.rawValue
                UpdateChecker.shared?.resetUpdateCycleAfterSettingsChange()
            }
        )
    }

    // MARK: Setup

    /// The setup flow again, from the first step, with every setting kept.
    private func openSetup() {
        UserDefaults.standard.set(0, forKey: UserDefaultsKeys.setupWizardCurrentStep)
        NotificationCenter.default.post(name: .resetSetupWizardWindow, object: nil)
        ManagedAppWindowOpener.shared.open(id: "setup")
    }

    // MARK: Backup

    private func exportUserData() {
        let panel = NSSavePanel()
        panel.title = String(localized: "Export Backup")
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = backupFilename()

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let summary = try backupService.exportBackup(to: url)
                notice = SettingsNotice(
                    title: String(localized: "Backup Exported"),
                    message: String(localized: "Exported \(summary.preferenceCount) settings, \(summary.dictionaryEntryCount) dictionary entries, \(summary.profileCount) profiles, and \(summary.historyRecordCount) history records.")
                )
            } catch {
                notice = SettingsNotice(
                    title: String(localized: "Export Failed"),
                    message: error.localizedDescription
                )
            }
        }
    }

    private func chooseBackupToImport() {
        let panel = NSOpenPanel()
        panel.title = String(localized: "Import Backup")
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                pendingImportSummary = try backupService.inspectBackup(at: url)
                pendingImportURL = url
                showsImportConfirmation = true
            } catch {
                notice = SettingsNotice(
                    title: String(localized: "Invalid Backup"),
                    message: error.localizedDescription
                )
            }
        }
    }

    private func importPendingBackup() {
        guard let url = pendingImportURL else { return }
        defer {
            pendingImportURL = nil
            pendingImportSummary = nil
        }

        do {
            let summary = try backupService.importBackup(from: url)
            notice = SettingsNotice(
                title: String(localized: "Backup Imported"),
                message: String(localized: "Restored \(summary.preferenceCount) settings, \(summary.dictionaryEntryCount) dictionary entries, \(summary.profileCount) profiles, and \(summary.historyRecordCount) history records. Quit and reopen Leise to apply every restored setting.")
            )
        } catch {
            notice = SettingsNotice(
                title: String(localized: "Import Failed"),
                message: error.localizedDescription
            )
        }
    }

    private func backupFilename() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return "leise-backup-\(formatter.string(from: Date())).json"
    }

    // MARK: Diagnostics

    private func exportDiagnostics() {
        let panel = NSSavePanel()
        panel.title = String(localized: "Export Diagnostics")
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = diagnosticsFilename()

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                do {
                    try await errorLogService.exportDiagnostics(to: url)
                } catch {
                    notice = SettingsNotice(
                        title: String(localized: "Export Failed"),
                        message: error.localizedDescription
                    )
                }
            }
        }
    }

    private func diagnosticsFilename() -> String {
        let timestamp = ISO8601DateFormatter()
            .string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        return "leise-diagnostics-\(timestamp).json"
    }
}

private struct SettingsNotice: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}
