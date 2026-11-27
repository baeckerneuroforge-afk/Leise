import SwiftUI

// MARK: - Model

/// Spoken punctuation for the current engine, model and dictation language.
///
/// With one dictation language the setting applies to that language. With
/// automatic detection it applies to every language Leise has punctuation
/// rules for, so "Komma" works whichever language the model detects.
@MainActor
struct SpokenPunctuationSettings {
    struct Context: Identifiable, Equatable {
        let engineId: String
        let engineName: String
        let modelId: String?
        let modelName: String?
        let languageCode: String

        var id: String {
            DictationPunctuationProfile.makeID(engineId: engineId, modelId: modelId, languageCode: languageCode)
        }

        var languageName: String { localizedAppLanguageName(for: languageCode) }

        var summary: String {
            [engineName, modelName, languageName]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: " · ")
        }
    }

    let contexts: [Context]

    init(
        settings: SettingsViewModel = ServiceContainer.shared.settingsViewModel,
        modelManager: ModelManagerService = ServiceContainer.shared.modelManagerService,
        rulesLoader: PunctuationRulesLoader = ServiceContainer.shared.punctuationRulesLoader
    ) {
        guard let engineId = modelManager.selectedProviderId,
              let engine = modelManager.engine(for: engineId) else {
            contexts = []
            return
        }
        let modelId = modelManager.selectedModelId(for: engineId)
        let modelName = engine.models.first { $0.id == modelId }.map { SpeechModelFacts.facts(for: $0).shortName }

        let languages: [String]
        if let configured = PunctuationLanguageNormalizer.normalize(settings.languageSelection.selectedCodes.first) {
            languages = [configured]
        } else {
            let preferred = PunctuationLanguageNormalizer.normalize(preferredAppLanguageCode())
            languages = engine.capabilities.supportedLanguages
                .compactMap(PunctuationLanguageNormalizer.normalize)
                .filter { rulesLoader.ruleSet(for: $0) != nil }
                .sorted { lhs, rhs in
                    if lhs == preferred { return true }
                    if rhs == preferred { return false }
                    return lhs < rhs
                }
        }

        contexts = languages.map { code in
            Context(engineId: engineId, engineName: engine.displayName, modelId: modelId, modelName: modelName, languageCode: code)
        }
    }

    /// The language the strategy picker shows and the test sheet uses.
    var primary: Context? { contexts.first }

    var isAvailable: Bool { !contexts.isEmpty }

    func resolved(
        _ context: Context,
        resolver: PunctuationStrategyResolver = ServiceContainer.shared.punctuationStrategyResolver
    ) -> ResolvedPunctuationStrategy? {
        resolver.resolve(
            engineId: context.engineId,
            modelId: context.modelId,
            configuredLanguage: context.languageCode,
            detectedLanguage: nil
        )
    }

    /// On unless every language is left to the model alone.
    var isEnabled: Bool {
        contexts.contains { resolved($0)?.strategy != .nativeOnly }
    }

    var strategy: PunctuationStrategy {
        primary.flatMap { resolved($0)?.strategy } ?? .automatic
    }

    func setEnabled(_ enabled: Bool) {
        setStrategy(enabled ? .automatic : .nativeOnly)
    }

    func setStrategy(
        _ strategy: PunctuationStrategy,
        store: DictationPunctuationProfileStore = ServiceContainer.shared.dictationPunctuationProfileStore
    ) {
        for context in contexts {
            guard let resolved = resolved(context) else { continue }
            save(strategy, for: context, resolved: resolved, store: store)
        }
    }

    func save(
        _ strategy: PunctuationStrategy,
        for context: Context,
        resolved: ResolvedPunctuationStrategy,
        verificationState: PunctuationVerificationState? = nil,
        updateVerificationDate: Bool = false,
        store: DictationPunctuationProfileStore = ServiceContainer.shared.dictationPunctuationProfileStore
    ) {
        store.saveUserOverride(
            engineId: context.engineId,
            modelId: context.modelId,
            languageCode: context.languageCode,
            defaultStrategy: resolved.profile.defaultStrategy,
            strategy: strategy,
            verificationState: verificationState ?? Self.inferredVerificationState(for: strategy, fallback: resolved.profile.verificationState),
            updateVerificationDate: updateVerificationDate || strategy != .automatic
        )
    }

    private static func inferredVerificationState(
        for strategy: PunctuationStrategy,
        fallback: PunctuationVerificationState
    ) -> PunctuationVerificationState {
        switch strategy {
        case .nativeOnly: .userVerifiedGood
        case .fallbackOnly: .userVerifiedBad
        case .automatic: fallback
        }
    }
}

extension PunctuationStrategy {
    /// The menu title in Erweitert › Gesprochene Satzzeichen › Erkennung.
    var menuTitle: String {
        switch self {
        case .automatic: String(localized: "Automatic")
        case .nativeOnly: String(localized: "Model only")
        case .fallbackOnly: String(localized: "Leise rules only")
        }
    }

    var explanation: String {
        switch self {
        case .automatic:
            String(localized: "Keeps the model’s punctuation and only turns spoken commands it left as words into marks.")
        case .nativeOnly:
            String(localized: "Uses the model’s text unchanged. Spoken commands stay words.")
        case .fallbackOnly:
            String(localized: "Always applies Leise’s rules, for languages where the model leaves “comma” as a word.")
        }
    }
}

private extension PunctuationVerificationState {
    /// What the “Try it out” row says about the last test, in the user's words
    /// rather than the profile's internal verification state.
    var tryItOutSummary: String {
        switch self {
        case .unknown, .vendorHint:
            String(localized: "Speak a few test sentences and see which setting fits.")
        case .userVerifiedGood:
            String(localized: "Tested: the model sets the marks itself.")
        case .userVerifiedBad:
            String(localized: "Tested: Leise’s rules are needed.")
        }
    }
}

// MARK: - Diktat › Text › Gesprochene Satzzeichen

struct SpokenPunctuationToggle: View {
    @ObservedObject private var settings = ServiceContainer.shared.settingsViewModel
    @ObservedObject private var modelManager = ServiceContainer.shared.modelManagerService
    @ObservedObject private var profileStore = ServiceContainer.shared.dictationPunctuationProfileStore

    var body: some View {
        let punctuation = SpokenPunctuationSettings(settings: settings, modelManager: modelManager)
        Toggle(isOn: Binding(
            get: { punctuation.isEnabled },
            set: { punctuation.setEnabled($0) }
        )) {
            SettingsRowLabel(
                title: SettingsRow.spokenPunctuation.title,
                subtitle: String(localized: "“comma”, “period”, “question mark”"),
                info: String(localized: "Words like “comma” become punctuation marks. How Leise recognizes them is set under Advanced.")
            )
        }
        .disabled(!punctuation.isAvailable)
        .settingsRow(.spokenPunctuation)
    }
}

// MARK: - Erweitert › Gesprochene Satzzeichen

struct SpokenPunctuationSettingsSection: View {
    @ObservedObject private var settings = ServiceContainer.shared.settingsViewModel
    @ObservedObject private var modelManager = ServiceContainer.shared.modelManagerService
    @ObservedObject private var profileStore = ServiceContainer.shared.dictationPunctuationProfileStore
    @State private var testContext: SpokenPunctuationSettings.Context?

    private let verificationService = ServiceContainer.shared.punctuationVerificationService

    var body: some View {
        let punctuation = SpokenPunctuationSettings(settings: settings, modelManager: modelManager)
        Section {
            if let primary = punctuation.primary {
                Picker(selection: Binding(
                    get: { punctuation.strategy },
                    set: { punctuation.setStrategy($0) }
                )) {
                    ForEach(PunctuationStrategy.allCases) { strategy in
                        Text(strategy.menuTitle).tag(strategy)
                    }
                } label: {
                    SettingsRowLabel(
                        title: SettingsRow.punctuationStrategy.title,
                        subtitle: punctuation.contexts.count > 1
                            ? String(localized: "For \(languageList(punctuation.contexts))")
                            : nil,
                        info: punctuation.strategy.explanation
                    )
                }
                .settingsRow(.punctuationStrategy)

                LabeledContent {
                    Button(String(localized: "Test…")) {
                        testContext = primary
                    }
                } label: {
                    SettingsRowLabel(
                        title: String(localized: "Try it out"),
                        subtitle: (punctuation.resolved(primary)?.profile.verificationState ?? .unknown).tryItOutSummary
                    )
                }
            } else {
                Text(String(localized: "Load a speech model to set up spoken punctuation."))
                    .foregroundStyle(.secondary)
                    .settingsRow(.punctuationStrategy)
            }
        } header: {
            Text(String(localized: "Spoken Punctuation"))
        }
        .sheet(item: $testContext) { context in
            PunctuationVerificationSheet(
                context: context,
                scenarios: verificationService.scenarios(for: context.languageCode)
            ) { strategy, verificationState in
                let punctuation = SpokenPunctuationSettings(settings: settings, modelManager: modelManager)
                guard let resolved = punctuation.resolved(context) else { return }
                punctuation.save(
                    strategy,
                    for: context,
                    resolved: resolved,
                    verificationState: verificationState,
                    updateVerificationDate: true
                )
            }
        }
    }

    private func languageList(_ contexts: [SpokenPunctuationSettings.Context]) -> String {
        contexts.map(\.languageName).formatted(.list(type: .and))
    }
}

// MARK: - Test sheet

private struct PunctuationVerificationSheet: View {
    let context: SpokenPunctuationSettings.Context
    let scenarios: [PunctuationVerificationScenario]
    let onDecision: (PunctuationStrategy, PunctuationVerificationState) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: LeiseSpacing.l) {
            Text(String(localized: "Test Spoken Punctuation"))
                .font(.title3.bold())

            Text(String(localized: "Dictate these phrases into any text field (\(context.summary)). If the result already matches, the model is enough. Otherwise use Leise’s rules."))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if scenarios.isEmpty {
                Text(String(localized: "There are no test phrases for this language yet."))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                List(scenarios, id: \.self) { scenario in
                    VStack(alignment: .leading, spacing: LeiseSpacing.xs) {
                        Text(scenario.spoken)
                            .font(.body.monospaced())
                        Text(String(localized: "Expected: \(scenario.expected)"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, LeiseSpacing.xs)
                    .accessibilityElement(children: .combine)
                }
                .frame(minHeight: 220)
            }

            HStack {
                Button(String(localized: "Keep Automatic")) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Spacer()
                Button(String(localized: "Use Leise Rules")) {
                    onDecision(.fallbackOnly, .userVerifiedBad)
                    dismiss()
                }
                Button(String(localized: "The Model Is Enough")) {
                    onDecision(.nativeOnly, .userVerifiedGood)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(LeiseSpacing.xl)
        .frame(minWidth: 560, minHeight: 420)
    }
}
