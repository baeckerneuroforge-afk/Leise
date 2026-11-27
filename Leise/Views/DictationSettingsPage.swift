import SwiftUI

/// Settings of the Diktat › Text group that have no home in a service yet.
enum DictationTextSettings {
    /// "Füllwörter entfernen". Default on, which is what Leise always did.
    /// Until the post-processing pipeline reads this key the filler-word
    /// cleanup keeps running (see the window workstream's report).
    static let fillerWordRemovalKey = "fillerWordRemovalEnabled"
}

/// Diktat: the shortcut, language and model, what happens to the text, and
/// how it is inserted.
struct DictationSettingsPage: View {
    @ObservedObject private var dictation = ServiceContainer.shared.dictationViewModel
    @ObservedObject private var settings = ServiceContainer.shared.settingsViewModel
    @ObservedObject private var modelManager = ServiceContainer.shared.modelManagerService
    @AppStorage(DictationTextSettings.fillerWordRemovalKey) private var removesFillerWords = true
    @AppStorage(UserDefaultsKeys.appFormattingEnabled) private var adaptsToApp = false
    @State private var secureInput = SecureInputDiagnosticsProvider.snapshot()

    /// How often the Secure Input notice checks whether another app still holds it.
    private static let secureInputRefresh: Duration = .seconds(3)

    var body: some View {
        SettingsPage(.dictation) {
            PermissionsSection(dictation: dictation)

            Section {
                DictationShortcutRow(dictation: dictation)
                GlobeKeyNotice()
                if secureInput.isActive {
                    SecureInputNotice(owner: secureInput.userFacingOwner)
                }
                MoreShortcutsGroup(dictation: dictation)
            } header: {
                Text(String(localized: "Keyboard Shortcuts"))
            }

            Section {
                SpokenLanguagePicker(
                    selection: $settings.languageSelection,
                    languages: settings.availableLanguages
                ) {
                    Text(SettingsRow.spokenLanguage.title)
                }
                .settingsRow(.spokenLanguage)

                SpeechModelRow(modelManager: modelManager)

                if let mismatch = languageModelMismatch {
                    LabeledContent {
                        Button(String(localized: "Use \(mismatch.suggestedModelName)")) {
                            modelManager.selectModel(mismatch.engineID, modelId: mismatch.suggestedModelID)
                        }
                    } label: {
                        StatusLabel(kind: .error, text: mismatch.message)
                    }
                }
            } header: {
                Text(String(localized: "Language & Model"))
            } footer: {
                Text(String(localized: "Runs entirely on this Mac. No audio leaves the device."))
            }

            Section {
                Toggle(isOn: $removesFillerWords) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(SettingsRow.removeFillerWords.title)
                        Text(fillerWordsSubtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .tint(LeiseColor.tint)
                    }
                }
                .settingsRow(.removeFillerWords)
                .environment(\.openURL, OpenURLAction { _ in
                    MainActor.assumeIsolated {
                        SettingsNavigationCoordinator.shared.show(.fillerWordList)
                    }
                    return .handled
                })

                SpokenPunctuationToggle()

                Toggle(isOn: Binding(
                    get: { TranscriptionNormalizationService.numberNormalizationEnabled() },
                    set: { UserDefaults.standard.set($0, forKey: UserDefaultsKeys.transcriptionNumberNormalizationEnabled) }
                )) {
                    SettingsRowLabel(
                        title: SettingsRow.numbersAsDigits.title,
                        subtitle: String(localized: "“forty-two” becomes 42")
                    )
                }
                .settingsRow(.numbersAsDigits)

                Toggle(isOn: $adaptsToApp) {
                    SettingsRowLabel(
                        title: SettingsRow.appAwareFormatting.title,
                        subtitle: String(localized: "Formatting that fits the target app"),
                        info: String(localized: "Leise uses the target app’s rules and the text around the cursor. An app rule’s output format still decides the format for that app.")
                    )
                }
                .settingsRow(.appAwareFormatting)
            } header: {
                Text(String(localized: "Text"))
            }

            Section {
                Toggle(isOn: $dictation.preserveClipboard) {
                    SettingsRowLabel(
                        title: SettingsRow.restoreClipboard.title,
                        subtitle: String(localized: "Afterwards it holds what you had copied before.")
                    )
                }
                .settingsRow(.restoreClipboard)
            } header: {
                Text(String(localized: "Insertion"))
            }
        }
        .task {
            while !Task.isCancelled {
                secureInput = SecureInputDiagnosticsProvider.snapshot()
                try? await Task.sleep(for: Self.secureInputRefresh)
            }
        }
    }

    private var fillerWordsSubtitle: AttributedString {
        AttributedString(localized: "um, uh, like … [The list is in the Dictionary.](leise-settings://dictionary/filler-words)")
    }

    // MARK: Language and model

    private struct LanguageModelMismatch {
        let engineID: String
        let suggestedModelID: String
        let suggestedModelName: String
        let message: String
    }

    /// An English-only model with another language chosen: German would come
    /// out as English gibberish, so say so and offer the multilingual model.
    private var languageModelMismatch: LanguageModelMismatch? {
        guard let engine = modelManager.engine(for: modelManager.selectedProviderId),
              let selectedID = engine.selectedModelID,
              let selected = engine.models.first(where: { $0.id == selectedID }),
              let selectedLanguages = SpeechModelFacts.facts(for: selected).languages,
              let language = settings.languageSelection.requestedLanguage,
              !selectedLanguages.contains(language),
              let alternative = engine.models.first(where: { model in
                  model.id != selectedID && SpeechModelFacts.facts(for: model).languages == nil
              }) else {
            return nil
        }
        let modelName = SpeechModelFacts.facts(for: selected).shortName
        return LanguageModelMismatch(
            engineID: engine.id,
            suggestedModelID: alternative.id,
            suggestedModelName: SpeechModelFacts.facts(for: alternative).shortName,
            message: String(localized: "\(modelName) only understands English.")
        )
    }
}
