import Combine
import Foundation

/// Apps › Regeln pro App. A rule is a `Profile`: it applies when one of its
/// apps (or websites) is in front.
@MainActor
final class ProfilesViewModel: ObservableObject {
    @Published var profiles: [Profile] = []
    @Published var showingEditor = false
    @Published var editingProfile: Profile?
    @Published var editorName = ""
    @Published var editorEnabled = true
    /// Bundle identifiers, in the order they were added.
    @Published var editorApps: [String] = []
    /// Website domains, one per line.
    @Published var editorURLPatterns = ""
    @Published var editorLanguage: LanguageSelection = .inheritGlobal
    @Published var editorOutputFormat = ""
    @Published var editorAutoEnterEnabled = false
    @Published var editorHotkey: UnifiedHotkey?

    private let profileService: ProfileService
    private var cancellables = Set<AnyCancellable>()

    init(
        profileService: ProfileService,
        historyService _: HistoryService,
        settingsViewModel _: SettingsViewModel,
        textInsertionService _: TextInsertionService
    ) {
        self.profileService = profileService
        profiles = profileService.profiles
        profileService.$profiles
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.profiles = $0 }
            .store(in: &cancellables)
    }

    var isEditorValid: Bool {
        !editorName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Opens the editor for a new rule, optionally for an app picked from the
    /// "App hinzufügen …" menu.
    func prepareNewProfile(app bundleIdentifier: String? = nil, name: String = "") {
        editingProfile = nil
        editorName = name
        editorEnabled = true
        editorApps = bundleIdentifier.map { [$0] } ?? []
        editorURLPatterns = ""
        editorLanguage = .inheritGlobal
        editorOutputFormat = ""
        editorAutoEnterEnabled = false
        editorHotkey = nil
        showingEditor = true
    }

    func startEditing(_ profile: Profile) {
        editingProfile = profile
        editorName = profile.name
        editorEnabled = profile.isEnabled
        editorApps = profile.bundleIdentifiers
        editorURLPatterns = profile.urlPatterns.joined(separator: "\n")
        editorLanguage = profile.inputLanguageSelection
        editorOutputFormat = profile.outputFormat ?? ""
        editorAutoEnterEnabled = profile.autoEnterEnabled
        editorHotkey = profile.hotkey
        showingEditor = true
    }

    func addEditorApp(_ bundleIdentifier: String, name: String) {
        guard !editorApps.contains(bundleIdentifier) else { return }
        editorApps.append(bundleIdentifier)
        if editorName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            editorName = name
        }
    }

    func removeEditorApp(_ bundleIdentifier: String) {
        editorApps.removeAll { $0 == bundleIdentifier }
    }

    func saveEditor() {
        let name = editorName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let urls = values(from: editorURLPatterns)
        let outputFormat = optionalValue(editorOutputFormat)
        let hotkeyData = editorHotkey.flatMap { try? JSONEncoder().encode($0) }

        if let profile = editingProfile {
            profile.name = name
            profile.isEnabled = editorEnabled
            profile.bundleIdentifiers = editorApps
            profile.urlPatterns = urls
            profile.inputLanguageSelection = editorLanguage
            profile.outputFormat = outputFormat
            profile.autoEnterEnabled = editorAutoEnterEnabled
            profile.hotkeyData = hotkeyData
            profileService.updateProfile(profile)
        } else {
            profileService.addProfile(
                name: name,
                isEnabled: editorEnabled,
                bundleIdentifiers: editorApps,
                urlPatterns: urls,
                inputLanguage: editorLanguage.storedValue(nilBehavior: .inheritGlobal),
                outputFormat: outputFormat,
                hotkeyData: hotkeyData,
                autoEnterEnabled: editorAutoEnterEnabled,
                priority: profileService.nextPriority()
            )
        }
        showingEditor = false
    }

    func deleteEditingProfile() {
        if let profile = editingProfile {
            profileService.deleteProfile(profile)
        }
        editingProfile = nil
        showingEditor = false
    }

    func setEnabled(_ enabled: Bool, for profile: Profile) {
        guard profile.isEnabled != enabled else { return }
        profileService.toggleProfile(profile)
    }

    func toggle(_ profile: Profile) { profileService.toggleProfile(profile) }
    func delete(_ profile: Profile) { profileService.deleteProfile(profile) }

    private func values(from text: String) -> [String] {
        text.split(whereSeparator: { $0 == "\n" || $0 == "," })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func optionalValue(_ text: String) -> String? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
