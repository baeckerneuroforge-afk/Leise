import Combine
import Foundation
import LeiseCore

@MainActor
final class DictationRecoveryViewModel: ObservableObject {
    typealias AudioSamplesLoader = @MainActor (URL) async throws -> [Float]
    typealias TranscriptionRunner = @MainActor (
        [Float],
        LanguageSelection,
        TranscriptionTask,
        String?,
        String?
    ) async throws -> TranscriptionResult
    typealias EngineReadinessChecker = @MainActor (String?) -> Bool

    enum RecoveryState: Equatable {
        case idle
        case loading
        case transcribing
        case error
    }

    struct RecoveryItem: Identifiable {
        let url: URL
        var state: RecoveryState = .idle
        var errorMessage: String?
        /// When the recording was kept, from the file's modification date.
        let recordedAt: Date
        /// The audio's length, read from the WAV size; nil if unreadable.
        let duration: TimeInterval?

        init(url: URL, state: RecoveryState = .idle, errorMessage: String? = nil) {
            self.url = url
            self.state = state
            self.errorMessage = errorMessage
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
            self.recordedAt = attributes?[.modificationDate] as? Date ?? Date()
            self.duration = (attributes?[.size] as? NSNumber).map { Self.duration(ofRecoveryWAVBytes: $0.intValue) }
        }

        var id: String { url.path }
        var fileName: String { url.lastPathComponent }

        var isProcessing: Bool {
            state == .loading || state == .transcribing
        }

        /// Recovery files are 16 kHz mono 16-bit PCM WAV with a 44-byte header
        /// (`DictationRecoveryAudioStore`), so the size gives the length
        /// without decoding the audio.
        static func duration(ofRecoveryWAVBytes byteCount: Int) -> TimeInterval {
            let headerBytes = 44
            let bytesPerSecond = 16_000 * 2
            return TimeInterval(max(byteCount - headerBytes, 0)) / TimeInterval(bytesPerSecond)
        }
    }

    @Published private(set) var recoveries: [RecoveryItem]
    @Published var selectedRecoveryID: RecoveryItem.ID?
    @Published private(set) var lastSavedRecoveryFileName: String?
    @Published private(set) var lastSavedHistoryRecordID: UUID?
    /// `.inheritGlobal` uses the dictation language, which is what the
    /// history page offers ("Erneut transkribieren").
    @Published var languageSelection: LanguageSelection = .inheritGlobal {
        didSet {
            defaults.set(
                languageSelection.storedValue(nilBehavior: .inheritGlobal),
                forKey: UserDefaultsKeys.dictationRecoveryLanguage
            )
        }
    }
    @Published var selectedEngine: String? {
        didSet {
            defaults.set(selectedEngine, forKey: UserDefaultsKeys.dictationRecoveryEngine)
            guard isInitialized, oldValue != selectedEngine else { return }
            selectedModel = nil
            normalizeLanguageSelectionForResolvedEngine()
        }
    }
    @Published var selectedModel: String? {
        didSet { defaults.set(selectedModel, forKey: UserDefaultsKeys.dictationRecoveryModel) }
    }
    private let audioRecordingService: AudioRecordingService
    private let modelManager: ModelManagerService
    private let historyService: HistoryService
    private let usageStatisticsRecorder: UsageStatisticsRecording?
    private let audioSamplesLoader: AudioSamplesLoader
    private let transcriptionRunner: TranscriptionRunner
    private let engineReadinessChecker: EngineReadinessChecker?
    private let defaults: UserDefaults
    private var cancellables = Set<AnyCancellable>()
    private var isInitialized = false

    init(
        audioRecordingService: AudioRecordingService,
        modelManager: ModelManagerService,
        historyService: HistoryService,
        audioFileService: AudioFileService,
        usageStatisticsRecorder: UsageStatisticsRecording? = nil,
        defaults: UserDefaults = .standard,
        audioSamplesLoader: AudioSamplesLoader? = nil,
        transcriptionRunner: TranscriptionRunner? = nil,
        engineReadinessChecker: EngineReadinessChecker? = nil
    ) {
        self.audioRecordingService = audioRecordingService
        self.modelManager = modelManager
        self.historyService = historyService
        self.usageStatisticsRecorder = usageStatisticsRecorder
        self.defaults = defaults
        self.audioSamplesLoader = audioSamplesLoader ?? { [audioFileService] url in
            try await audioFileService.loadAudioSamples(from: url)
        }
        self.transcriptionRunner = transcriptionRunner ?? { [modelManager] samples, languageSelection, task, engineOverrideId, cloudModelOverride in
            try await modelManager.transcribe(
                audioSamples: samples,
                languageSelection: languageSelection,
                task: task,
                engineOverrideId: engineOverrideId,
                cloudModelOverride: cloudModelOverride
            )
        }
        self.engineReadinessChecker = engineReadinessChecker
        let initialRecoveryURLs = audioRecordingService.recoveryRecordingURLs
        self.recoveries = initialRecoveryURLs.map { RecoveryItem(url: $0) }
        self.selectedRecoveryID = initialRecoveryURLs.first?.path
        // Recovery now uses the dictation model and language (Diktat ›
        // Sprache & Modell); the separate pickers are gone, so settings saved
        // by older versions would silently win. Drop them.
        defaults.removeObject(forKey: UserDefaultsKeys.dictationRecoveryLanguage)
        defaults.removeObject(forKey: UserDefaultsKeys.dictationRecoveryEngine)
        defaults.removeObject(forKey: UserDefaultsKeys.dictationRecoveryModel)
        self.languageSelection = .inheritGlobal
        self.selectedEngine = nil
        self.selectedModel = nil
        self.isInitialized = true

        audioRecordingService.$recoverableRecordingURLs
            .receive(on: DispatchQueue.main)
            .sink { [weak self] urls in
                self?.updateRecoveryURLs(urls)
            }
            .store(in: &cancellables)

        reconcileSelectionWithAvailableEngines()
    }

    var hasRecovery: Bool {
        !recoveries.isEmpty
    }

    var hasRecoveryContent: Bool {
        hasRecovery || lastSavedHistoryRecordID != nil
    }

    var selectedRecovery: RecoveryItem? {
        if let selectedRecoveryID,
           let selectedRecovery = recoveries.first(where: { $0.id == selectedRecoveryID }) {
            return selectedRecovery
        }
        return recoveries.first
    }

    var recoveryURL: URL? {
        selectedRecovery?.url
    }

    var state: RecoveryState {
        selectedRecovery?.state ?? .idle
    }

    var errorMessage: String? {
        selectedRecovery?.errorMessage
    }

    var fileName: String {
        selectedRecovery?.fileName ?? String(localized: "No recording")
    }

    var isProcessing: Bool {
        recoveries.contains { $0.isProcessing }
    }

    var canTranscribe: Bool {
        selectedRecovery != nil && selectedEngineIsReady && !isProcessing
    }

    var availableEngines: [any TranscriptionEngine] {
        modelManager.availableEngines
    }

    var resolvedEngine: (any TranscriptionEngine)? {
        let engineId = selectedEngine ?? modelManager.selectedProviderId
        return modelManager.engine(for: engineId)
    }

    var selectedEngineSupportedLanguages: [String] {
        resolvedEngine?.capabilities.supportedLanguages.sorted() ?? []
    }

    func canUseForTranscription(_ engine: any TranscriptionEngine) -> Bool {
        modelManager.canUseForTranscription(engine)
    }

    /// The language a transcription actually uses: `.inheritGlobal` resolves
    /// to the dictation language.
    var effectiveLanguageSelection: LanguageSelection {
        guard languageSelection == .inheritGlobal else { return languageSelection }
        return LanguageSelection(
            storedValue: defaults.string(forKey: UserDefaultsKeys.selectedLanguage),
            nilBehavior: .auto
        )
    }

    /// Verlauf › „Erneut transkribieren“ for one failed recording.
    func retranscribe(_ recovery: RecoveryItem) {
        selectedRecoveryID = recovery.id
        transcribe()
    }

    func transcribe() {
        guard canTranscribe, let recovery = selectedRecovery else { return }

        let recoveryID = recovery.id
        let url = recovery.url
        let languageSelection = effectiveLanguageSelection
        updateRecovery(id: recoveryID) { item in
            item.state = .loading
            item.errorMessage = nil
        }

        Task {
            do {
                let samples = try await audioSamplesLoader(url)
                updateRecovery(id: recoveryID) { item in
                    item.state = .transcribing
                }
                let result = try await transcriptionRunner(
                    samples,
                    languageSelection,
                    .transcribe,
                    selectedEngine,
                    selectedModel
                )

                let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else {
                    updateRecovery(id: recoveryID) { item in
                        item.state = .error
                        item.errorMessage = String(localized: "No speech recognized")
                    }
                    return
                }

                usageStatisticsRecorder?.recordTranscription(
                    timestamp: Date(),
                    wordsCount: text.split(separator: " ").count,
                    durationSeconds: result.duration,
                    appName: String(localized: "Dictation Recovery"),
                    appBundleIdentifier: Bundle.main.bundleIdentifier,
                    language: result.detectedLanguage ?? languageSelection.requestedLanguage,
                    engine: result.engineUsed,
                    model: historyModelDisplayName(result: result),
                    rawText: result.text,
                    processedText: text,
                    pipelineSteps: [String(localized: "Recovered recording")]
                )

                let historyID = UUID()
                historyService.addRecord(
                    id: historyID,
                    rawText: result.text,
                    finalText: text,
                    appName: String(localized: "Dictation Recovery"),
                    appBundleIdentifier: Bundle.main.bundleIdentifier,
                    durationSeconds: result.duration,
                    language: result.detectedLanguage ?? languageSelection.requestedLanguage,
                    engineUsed: result.engineUsed,
                    modelUsed: historyModelDisplayName(result: result),
                    audioSamples: samples,
                    pipelineSteps: [String(localized: "Recovered recording")]
                )
                lastSavedRecoveryFileName = url.lastPathComponent
                lastSavedHistoryRecordID = historyID
                audioRecordingService.discardRecoveryRecording(at: url)
                updateRecoveryURLs(audioRecordingService.recoveryRecordingURLs)
            } catch {
                updateRecovery(id: recoveryID) { item in
                    item.state = .error
                    item.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func discardRecovery() {
        discardSelectedRecovery()
    }

    func discardSelectedRecovery() {
        guard let recovery = selectedRecovery else { return }
        discardRecovery(recovery)
    }

    func discardRecovery(_ recovery: RecoveryItem) {
        audioRecordingService.discardRecoveryRecording(at: recovery.url)
        updateRecoveryURLs(audioRecordingService.recoveryRecordingURLs)
    }

    private func updateRecoveryURLs(_ urls: [URL]) {
        let previousRecoveries = Dictionary(uniqueKeysWithValues: recoveries.map { ($0.id, $0) })
        let updatedRecoveries = urls.map { url in
            previousRecoveries[url.path] ?? RecoveryItem(url: url)
        }
        let selectedID = selectedRecoveryID

        recoveries = updatedRecoveries

        if let selectedID,
           recoveries.contains(where: { $0.id == selectedID }) {
            selectedRecoveryID = selectedID
        } else {
            selectedRecoveryID = recoveries.first?.id
        }
    }

    private func updateRecovery(id: RecoveryItem.ID, _ update: (inout RecoveryItem) -> Void) {
        guard let index = recoveries.firstIndex(where: { $0.id == id }) else { return }
        update(&recoveries[index])
    }

    private func historyModelDisplayName(result: TranscriptionResult) -> String {
        return modelManager.resolvedModelDisplayName(
            engineOverrideId: selectedEngine,
            cloudModelOverride: selectedModel
        ) ?? selectedModel ?? selectedEngine ?? result.engineUsed
    }

    private var selectedEngineIsReady: Bool {
        if let engineReadinessChecker {
            return engineReadinessChecker(selectedEngine)
        }

        guard let engine = resolvedEngine else { return false }
        guard modelManager.canUseForTranscription(engine) else { return false }
        return engine.isReady
    }

    private func reconcileSelectionWithAvailableEngines() {
        if let selectedEngine,
           modelManager.engine(for: selectedEngine) == nil {
            self.selectedEngine = nil
            selectedModel = nil
        }
        normalizeLanguageSelectionForResolvedEngine()
    }

    private func normalizeLanguageSelectionForResolvedEngine() {
        guard let engine = resolvedEngine else { return }
        let normalized = languageSelection.normalizedForSupportedLanguages(engine.capabilities.supportedLanguages)
        if normalized != languageSelection {
            languageSelection = normalized
        }
    }
}
