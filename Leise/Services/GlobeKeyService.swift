import AppKit
import Combine
import CoreFoundation
import Foundation

/// What the 🌐/fn key does when pressed on its own: System Settings ›
/// Keyboard › "Press 🌐 key to". When fn is also Leise's dictation shortcut,
/// anything but "Do Nothing" fires alongside every dictation.
enum GlobeKeyAction: Equatable, Sendable {
    case doNothing
    case changeInputSource
    case showEmojiAndSymbols
    case startDictation
    /// A value macOS added after this was written. Treated as a conflict.
    case other(Int)

    /// The `AppleFnUsageType` value that turns the action off.
    static let doNothingRawValue = 0

    /// Maps `AppleFnUsageType`. An absent value means the system default,
    /// which opens Emoji & Symbols on current Macs, so it counts as a conflict.
    init(fnUsageType: Int?) {
        switch fnUsageType {
        case nil, 2: self = .showEmojiAndSymbols
        case 0: self = .doNothing
        case 1: self = .changeInputSource
        case 3: self = .startDictation
        case let value?: self = .other(value)
        }
    }

    /// Whether pressing fn alone also triggers a system action.
    var interferesWithFnShortcut: Bool {
        self != .doNothing
    }
}

/// Reads and writes `AppleFnUsageType`. Injected so tests never touch the
/// real preferences of the machine running them.
@MainActor
protocol GlobeKeyPreferencesStoring: AnyObject {
    /// `nil` when the key is absent.
    func readFnUsageType() -> Int?
    /// Returns whether the preferences daemon confirmed the write.
    func writeFnUsageType(_ value: Int) -> Bool
}

/// The real store: the `com.apple.HIToolbox` domain of the current user, as
/// `defaults read com.apple.HIToolbox AppleFnUsageType` sees it.
@MainActor
final class SystemGlobeKeyPreferences: GlobeKeyPreferencesStoring {
    private static let domain = "com.apple.HIToolbox" as CFString
    private static let key = "AppleFnUsageType" as CFString

    func readFnUsageType() -> Int? {
        // Pick up a change System Settings made since the last read.
        CFPreferencesSynchronize(Self.domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        guard let value = CFPreferencesCopyValue(
            Self.key,
            Self.domain,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost
        ) else {
            return nil
        }
        return (value as? NSNumber)?.intValue
    }

    func writeFnUsageType(_ value: Int) -> Bool {
        CFPreferencesSetValue(
            Self.key,
            NSNumber(value: value),
            Self.domain,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost
        )
        return CFPreferencesSynchronize(Self.domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }
}

/// Detects when the 🌐 key's own system action collides with an fn-based
/// dictation shortcut, and turns that action off when the user asks for it.
///
/// Main-actor confined: it is driven by SwiftUI views and notification
/// callbacks delivered on the main queue.
@MainActor
final class GlobeKeyService: ObservableObject {
    enum FixResult: Equatable {
        case fixed
        case failed
    }

    /// Posted after Leise changed the 🌐 key setting, so every notice re-reads it.
    static let didChangeNotification = Notification.Name("GlobeKeyServiceDidChange")

    /// System Settings › Keyboard, where "Press 🌐 key to" lives.
    static let keyboardSettingsURL = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!

    /// Shortcut slots that start a dictation.
    static let dictationSlots: [HotkeySlotType] = [.hybrid, .pushToTalk, .toggle]

    @Published private(set) var action: GlobeKeyAction
    @Published private(set) var usesFnForDictation: Bool

    private let store: any GlobeKeyPreferencesStoring
    private let loadHotkeys: @MainActor (HotkeySlotType) -> [UnifiedHotkey]
    private let openURL: (URL) -> Void
    private let notificationCenter: NotificationCenter
    private var cancellables = Set<AnyCancellable>()

    init(
        store: (any GlobeKeyPreferencesStoring)? = nil,
        loadHotkeys: @escaping @MainActor (HotkeySlotType) -> [UnifiedHotkey] = DictationSettingsHandler.loadHotkeys(for:),
        openURL: @escaping (URL) -> Void = { NSWorkspace.shared.open($0) },
        notificationCenter: NotificationCenter = .default
    ) {
        let store = store ?? SystemGlobeKeyPreferences()
        self.store = store
        self.loadHotkeys = loadHotkeys
        self.openURL = openURL
        self.notificationCenter = notificationCenter
        action = GlobeKeyAction(fnUsageType: store.readFnUsageType())
        usesFnForDictation = Self.usesFnForDictation(loadHotkeys)
    }

    /// Re-reads both sides whenever they may have changed: the user returns
    /// from System Settings, a shortcut is recorded, or another notice fixed it.
    func startObserving() {
        guard cancellables.isEmpty else { return }
        Publishers.Merge3(
            notificationCenter.publisher(for: NSApplication.didBecomeActiveNotification).map { _ in () },
            notificationCenter.publisher(for: UserDefaults.didChangeNotification).map { _ in () },
            notificationCenter.publisher(for: Self.didChangeNotification).map { _ in () }
        )
        // UserDefaults posts on the writing thread; coalesce bursts on main.
        .debounce(for: .milliseconds(150), scheduler: DispatchQueue.main)
        .sink { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refresh()
            }
        }
        .store(in: &cancellables)
    }

    func refresh() {
        let newAction = GlobeKeyAction(fnUsageType: store.readFnUsageType())
        if newAction != action { action = newAction }
        let newUsesFn = Self.usesFnForDictation(loadHotkeys)
        if newUsesFn != usesFnForDictation { usesFnForDictation = newUsesFn }
    }

    /// The 🌐 key action that fires alongside dictation, if any.
    /// - Parameter assumingFnShortcut: Setup has not saved fn yet but will.
    func conflict(assumingFnShortcut: Bool = false) -> GlobeKeyAction? {
        guard usesFnForDictation || assumingFnShortcut, action.interferesWithFnShortcut else { return nil }
        return action
    }

    /// "Abstellen": sets "Press 🌐 key to" to "Do Nothing". Only ever called
    /// from an explicit user action; the result comes from re-reading the value.
    @discardableResult
    func turnOffGlobeKeyAction() -> FixResult {
        let synchronized = store.writeFnUsageType(GlobeKeyAction.doNothingRawValue)
        refresh()
        guard synchronized, action == .doNothing else { return .failed }
        notificationCenter.post(name: Self.didChangeNotification, object: self)
        return .fixed
    }

    func openKeyboardSettings() {
        openURL(Self.keyboardSettingsURL)
    }

    static func usesFnForDictation(_ loadHotkeys: (HotkeySlotType) -> [UnifiedHotkey]) -> Bool {
        dictationSlots.contains { slot in
            loadHotkeys(slot).contains { $0.isFn && $0.mouseButton == nil }
        }
    }
}

extension GlobeKeyAction {
    /// One sentence for the notice, naming what fn triggers besides Leise.
    var conflictMessage: String {
        switch self {
        case .doNothing:
            ""
        case .showEmojiAndSymbols:
            String(localized: "The 🌐 key also opens emoji right now.")
        case .changeInputSource:
            String(localized: "The 🌐 key also switches the input source right now.")
        case .startDictation:
            String(localized: "The 🌐 key also starts macOS Dictation right now.")
        case .other:
            String(localized: "The 🌐 key also triggers a system action right now.")
        }
    }

    /// How to fix it by hand, for when Leise cannot change the setting itself.
    static var settingsInstruction: String {
        String(localized: "Set “Press 🌐 key to” to “Do Nothing”.")
    }
}
