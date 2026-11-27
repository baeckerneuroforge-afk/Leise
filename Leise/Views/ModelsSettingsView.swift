import LeiseCore
import SwiftUI

// MARK: - Model facts

/// What the window says about a speech model.
///
/// `TranscriptionModel` only carries an ID and a display name, so the size and
/// language facts live here for the two Parakeet models. Once ParakeetEngine
/// publishes them, this table should read them from the engine instead.
enum SpeechModelFacts {
    struct Facts: Equatable {
        /// "Parakeet v3": the name in status lines.
        let shortName: String
        /// The menu title in Diktat › Sprache & Modell.
        let menuTitle: String
        /// "Mehrsprachig, 25 Sprachen, 460 MB".
        let summary: String?
        /// Language codes the model understands, when known.
        let languages: [String]?
    }

    static func facts(for model: TranscriptionModel) -> Facts {
        switch model.id {
        case "parakeet-tdt-0.6b-v3":
            Facts(
                shortName: "Parakeet v3",
                menuTitle: "Parakeet v3",
                summary: String(localized: "Multilingual, 25 languages, 460 MB"),
                languages: nil
            )
        case "parakeet-tdt-0.6b-v2":
            Facts(
                shortName: "Parakeet v2",
                menuTitle: String(localized: "Parakeet v2 (English only)"),
                summary: String(localized: "English only, 440 MB"),
                languages: ["en"]
            )
        default:
            Facts(shortName: model.displayName, menuTitle: model.displayName, summary: nil, languages: nil)
        }
    }
}

// MARK: - Status

/// The selected model's state as symbol plus words: ready, loading, failed,
/// or not loaded yet.
struct ModelStatusLabel: View {
    @ObservedObject var modelManager: ModelManagerService
    /// "Parakeet v3 · bereit" instead of "bereit".
    var includesModelName = false

    private var engine: (any TranscriptionEngine)? {
        modelManager.engine(for: modelManager.selectedProviderId)
    }

    private var modelName: String? {
        guard let engine,
              let id = engine.selectedModelID,
              let model = engine.models.first(where: { $0.id == id }) else { return nil }
        return SpeechModelFacts.facts(for: model).shortName
    }

    var body: some View {
        switch engine?.preparationStatus ?? .idle {
        case .ready:
            StatusLabel(kind: .ready, text: readyText)
        case .preparing(_, let progress):
            StatusLabel(kind: .working, text: loadingText(progress: progress))
                .contentTransition(.numericText())
        case .failed(let message):
            StatusLabel(kind: .error, text: String(localized: "Could not load"))
                .help(message)
        case .idle:
            Label {
                Text(String(localized: "Not loaded"))
                    .foregroundStyle(.secondary)
            } icon: {
                Image(systemName: "arrow.down.circle")
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
            .labelStyle(.titleAndIcon)
        }
    }

    private var readyText: String {
        if includesModelName, let modelName {
            return String(localized: "\(modelName) · ready")
        }
        return String(localized: "Ready")
    }

    private func loadingText(progress: Double?) -> String {
        guard let progress, progress > 0 else { return String(localized: "Loading…") }
        let percent = (progress.clamped(to: 0...1)).formatted(.percent.precision(.fractionLength(0)))
        return String(localized: "Loading… \(percent)")
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

// MARK: - Diktat › Sprache & Modell › Modell

/// "Modell": the only place to choose the speech model.
struct SpeechModelRow: View {
    @ObservedObject var modelManager: ModelManagerService

    private var engine: (any TranscriptionEngine)? {
        modelManager.engine(for: modelManager.selectedProviderId) ?? modelManager.availableEngines.first
    }

    private var selectedModel: TranscriptionModel? {
        guard let engine, let id = engine.selectedModelID else { return nil }
        return engine.models.first { $0.id == id }
    }

    var body: some View {
        if let engine, !engine.models.isEmpty {
            LabeledContent {
                HStack(spacing: LeiseSpacing.m) {
                    ModelStatusLabel(modelManager: modelManager)
                    statusAction(for: engine)
                    if engine.models.count > 1 {
                        Picker(SettingsRow.model.title, selection: modelSelection(for: engine)) {
                            ForEach(engine.models) { model in
                                Text(SpeechModelFacts.facts(for: model).menuTitle)
                                    .tag(model.id as String?)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                }
            } label: {
                SettingsRowLabel(
                    title: SettingsRow.model.title,
                    subtitle: selectedModel.flatMap { SpeechModelFacts.facts(for: $0).summary }
                )
            }
            .settingsRow(.model)
        } else {
            LabeledContent {
                StatusLabel(kind: .error, text: String(localized: "No speech model available"))
            } label: {
                Text(SettingsRow.model.title)
            }
            .settingsRow(.model)
        }
    }

    private func modelSelection(for engine: any TranscriptionEngine) -> Binding<String?> {
        Binding(
            get: { engine.selectedModelID },
            set: { newValue in
                guard let newValue, newValue != engine.selectedModelID else { return }
                modelManager.selectModel(engine.id, modelId: newValue)
            }
        )
    }

    @ViewBuilder
    private func statusAction(for engine: any TranscriptionEngine) -> some View {
        switch engine.preparationStatus {
        case .idle:
            Button(String(localized: "Load")) { prepare(engine) }
                .help(String(localized: "Loads the model now, downloading it once if needed."))
        case .failed:
            Button(String(localized: "Try Again")) { prepare(engine) }
        case .ready, .preparing:
            EmptyView()
        }
    }

    private func prepare(_ engine: any TranscriptionEngine) {
        let modelID = engine.selectedModelID
        Task { @MainActor in
            try? await engine.prepareModel(id: modelID, allowDownloads: true)
        }
    }
}

// MARK: - Engine settings

/// The speech engine's own settings (model downloads, vocabulary boosting) in
/// a sheet. Reached from Wörterbuch › Begriffe until ParakeetEngine offers a
/// public switch for vocabulary boosting.
struct EngineSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                ServiceContainer.shared.builtInComponents.parakeetSettingsView
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            Divider()
            HStack {
                Spacer()
                Button(String(localized: "Done")) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(LeiseSpacing.l)
        }
        .frame(width: 560, height: 600)
    }
}

// MARK: - Engine settings › Spoken language

/// The spoken-language row inside the engine settings sheet. Diktat ›
/// Sprache & Modell shows the same setting.
struct SpokenLanguageSettingsSection: View {
    @ObservedObject private var settings = ServiceContainer.shared.settingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: LeiseSpacing.s) {
            SpokenLanguagePicker(
                selection: $settings.languageSelection,
                languages: settings.availableLanguages
            ) {
                Text(SettingsRow.spokenLanguage.title)
            }
            .fixedSize()

            Text(String(localized: "Used for dictation and for app rules without their own language."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}
