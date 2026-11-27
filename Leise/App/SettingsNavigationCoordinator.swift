import Combine
import Foundation

struct SettingsNavigationRequest: Identifiable, Equatable {
    let id = UUID()
    let tab: SettingsTab
}

@MainActor
final class SettingsNavigationCoordinator: ObservableObject {
    static let shared = SettingsNavigationCoordinator()

    @Published private(set) var request: SettingsNavigationRequest?

    func navigate(to tab: SettingsTab) {
        request = SettingsNavigationRequest(tab: tab)
    }
}

/// Semantic destinations, so callers (menu bar, setup) don't depend on the
/// sidebar's tab layout. The window workstream maps them to the new pages.
extension SettingsNavigationCoordinator {
    /// "Leise öffnen": the overview page.
    func showOverview() { navigate(to: .home) }
    /// "Einstellungen …" (⌘,): the dictation settings.
    func showDictationSettings() { navigate(to: .general) }
    /// The history, including failed recordings that can be recovered.
    func showHistory() { navigate(to: .history) }
    /// Failed recordings to recover.
    func showRecovery() { navigate(to: .dictationRecovery) }
}
