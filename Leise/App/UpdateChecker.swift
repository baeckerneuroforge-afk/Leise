@preconcurrency import Sparkle

/// Sparkle behind closures, so views can check for updates without importing
/// Sparkle. Sparkle's updater is main-actor bound, and so are the closures.
struct UpdateChecker: Sendable {
    let canCheckForUpdates: @MainActor @Sendable () -> Bool
    let checkForUpdates: @MainActor @Sendable () -> Void
    let resetUpdateCycleAfterSettingsChange: @MainActor @Sendable () -> Void

    @MainActor
    static func sparkle(_ updater: SPUUpdater) -> UpdateChecker {
        UpdateChecker(
            canCheckForUpdates: { updater.canCheckForUpdates },
            checkForUpdates: { updater.checkForUpdates() },
            resetUpdateCycleAfterSettingsChange: { updater.resetUpdateCycleAfterShortDelay() }
        )
    }

    nonisolated(unsafe) static var shared: UpdateChecker?
}
