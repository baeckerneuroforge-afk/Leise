import Combine
import Foundation

struct SettingsNavigationRequest: Identifiable, Equatable {
    let id = UUID()
    let tab: SettingsTab
    /// A row on `tab` to scroll to and flash, or `nil` for the top of the page.
    var row: SettingsRow?
}

@MainActor
final class SettingsNavigationCoordinator: ObservableObject {
    static let shared = SettingsNavigationCoordinator()

    @Published private(set) var request: SettingsNavigationRequest?

    func navigate(to tab: SettingsTab, row: SettingsRow? = nil) {
        request = SettingsNavigationRequest(tab: tab, row: row)
    }

    /// Opens the page that owns `row` and flashes the row.
    func show(_ row: SettingsRow) {
        navigate(to: row.page, row: row)
    }

    /// Called by the window once it has shown `request`, so reopening the
    /// window later does not replay it.
    func didHandle(_ request: SettingsNavigationRequest) {
        if self.request?.id == request.id {
            self.request = nil
        }
    }
}

/// Semantic destinations, so callers (menu bar, setup) don't depend on the
/// sidebar's layout.
extension SettingsNavigationCoordinator {
    /// "Leise öffnen": the overview page.
    func showOverview() { navigate(to: .overview) }
    /// "Einstellungen …" (⌘,): the dictation settings.
    func showDictationSettings() { navigate(to: .dictation) }
    /// The history, including failed recordings that can be recovered.
    func showHistory() { navigate(to: .history) }
    /// The history with the newest failed recording selected.
    func showRecovery() { navigate(to: .history, row: .recovery) }
}
