import AppKit
import Combine
import LeiseCore
import ParakeetEngine
import SwiftUI

// MARK: - Status header

/// The dictation shortcut as the status header phrases it.
struct MenuBarShortcutHint: Equatable {
    var label: String
    var isHeld: Bool

    /// The first configured trigger, in the order dictation resolves them.
    static func resolve(loadHotkeys: (HotkeySlotType) -> [UnifiedHotkey]) -> MenuBarShortcutHint? {
        for slot in SetupWizardDefaultHotkey.triggerSlots {
            guard let hotkey = loadHotkeys(slot).first else { continue }
            return MenuBarShortcutHint(label: SetupShortcutDisplay.displayLabel(for: hotkey), isHeld: slot != .toggle)
        }
        return nil
    }

    var text: String {
        isHeld
            ? String(localized: "Hold \(label) to talk")
            : String(localized: "Press \(label) to talk")
    }
}

/// What the status header needs to know about the language model.
struct MenuBarModelSnapshot: Equatable {
    var isReady: Bool
    var isPreparing: Bool
    var downloadFraction: Double?
    /// A model was loaded before and stays on disk, so dictation loads it
    /// on demand (after an auto-unload, for example).
    var loadsOnDemand: Bool
    var modelID: String?
    var displayName: String?

    var shortName: String {
        ParakeetModelNaming.shortName(forModelID: modelID) ?? displayName ?? "Parakeet"
    }

    @MainActor
    static func current(modelManager: ModelManagerService) -> MenuBarModelSnapshot {
        let engine = modelManager.engine(for: modelManager.selectedProviderId)
        var downloadFraction: Double?
        if case let .downloading(_, fraction)? = (engine as? any ParakeetModelActivityReporting)?.modelActivity {
            downloadFraction = fraction
        }
        var isPreparing = false
        var didFail = false
        switch engine?.preparationStatus {
        case .preparing?: isPreparing = true
        case .failed?: didFail = true
        case .idle?, .ready?, nil: break
        }
        // The engine keeps the last loaded model's ID until it is unloaded on purpose.
        let persistedModel = ComponentSettingsStore(namespace: SetupWizardParakeetRecommendation.providerId)
            .userDefault(forKey: "loadedModel") as? String
        return MenuBarModelSnapshot(
            isReady: modelManager.isModelReady,
            isPreparing: isPreparing,
            downloadFraction: downloadFraction,
            loadsOnDemand: engine != nil && !didFail && !(persistedModel ?? "").isEmpty,
            modelID: engine?.selectedModelID,
            displayName: modelManager.activeModelName
        )
    }
}

/// The first row of the menu: what Leise is doing and how to start.
struct MenuBarStatus: Equatable {
    enum Kind: Equatable {
        case ready
        case loading
        case noModel
        case paused
        case listening
        case writing
    }

    var kind: Kind
    var title: String
    var subtitle: String

    static func resolve(
        hotkeysPaused: Bool,
        dictationState: DictationViewModel.State,
        model: MenuBarModelSnapshot,
        shortcut: MenuBarShortcutHint?
    ) -> MenuBarStatus {
        switch dictationState {
        case .recording:
            return MenuBarStatus(kind: .listening, title: String(localized: "Listening…"), subtitle: model.shortName)
        case .processing:
            return MenuBarStatus(kind: .writing, title: String(localized: "Writing…"), subtitle: model.shortName)
        case .idle, .inserting, .error:
            break
        }

        if hotkeysPaused {
            return MenuBarStatus(kind: .paused, title: String(localized: "Dictation paused"), subtitle: String(localized: "Shortcuts are off"))
        }

        let shortcutText = shortcut?.text ?? String(localized: "No dictation shortcut set")
        if model.isReady {
            return MenuBarStatus(kind: .ready, title: String(localized: "Ready · \(model.shortName)"), subtitle: shortcutText)
        }
        if model.isPreparing {
            let detail: String
            if let fraction = model.downloadFraction {
                let percent = fraction.formatted(.percent.precision(.fractionLength(0)))
                detail = "\(model.shortName) · \(percent)"
            } else {
                detail = model.shortName
            }
            return MenuBarStatus(kind: .loading, title: String(localized: "Loading…"), subtitle: detail)
        }
        if model.loadsOnDemand {
            return MenuBarStatus(kind: .ready, title: String(localized: "Ready · \(model.shortName)"), subtitle: shortcutText)
        }
        return MenuBarStatus(kind: .noModel, title: String(localized: "No model"), subtitle: String(localized: "Open Leise to load one"))
    }
}

/// Lightweight state tracker for MenuBarView that only re-publishes
/// on menu-relevant changes, avoiding high-frequency audioLevel updates.
@MainActor
private final class MenuBarState: ObservableObject {
    @Published private(set) var status: MenuBarStatus
    @Published private(set) var canTranscribeFiles: Bool
    @Published private(set) var hasRecentTranscriptions: Bool
    @Published private(set) var hasRecoverableRecording: Bool
    @Published private(set) var recorderState: AudioRecorderViewModel.RecorderState
    @Published private(set) var canToggleRecorder: Bool
    @Published private(set) var dictationHotkeysPaused: Bool
    @Published private(set) var recentTranscriptionsMenuShortcut: HotkeyService.MenuShortcutDescriptor?
    @Published private(set) var copyLastTranscriptionMenuShortcut: HotkeyService.MenuShortcutDescriptor?
    @Published private(set) var recorderToggleMenuShortcut: HotkeyService.MenuShortcutDescriptor?

    private var dictationState: DictationViewModel.State
    private var model: MenuBarModelSnapshot
    private var shortcut: MenuBarShortcutHint?
    private var cancellables = Set<AnyCancellable>()

    init() {
        let container = ServiceContainer.shared
        let dictation = container.dictationViewModel
        let modelManager = container.modelManagerService
        let recorder = container.audioRecorderViewModel
        let hotkeyService = container.hotkeyService

        dictationState = dictation.state
        model = MenuBarModelSnapshot.current(modelManager: modelManager)
        shortcut = MenuBarShortcutHint.resolve(loadHotkeys: DictationSettingsHandler.loadHotkeys)
        dictationHotkeysPaused = hotkeyService.dictationHotkeysPaused
        status = MenuBarStatus.resolve(
            hotkeysPaused: hotkeyService.dictationHotkeysPaused,
            dictationState: dictation.state,
            model: model,
            shortcut: shortcut
        )
        canTranscribeFiles = model.isReady || model.loadsOnDemand
        hasRecentTranscriptions = Self.hasRecentTranscriptions()
        hasRecoverableRecording = container.audioRecordingService.latestRecoveryRecordingURL != nil
        recorderState = recorder.state
        canToggleRecorder = recorder.canToggleRecording
        recentTranscriptionsMenuShortcut = DictationSettingsHandler.loadMenuShortcutDescriptor(for: .recentTranscriptions)
        copyLastTranscriptionMenuShortcut = DictationSettingsHandler.loadMenuShortcutDescriptor(for: .copyLastTranscription)
        recorderToggleMenuShortcut = DictationSettingsHandler.loadMenuShortcutDescriptor(for: .recorderToggle)

        dictation.$state
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                MainActor.assumeIsolated {
                    self?.dictationState = state
                    self?.refreshStatus()
                }
            }
            .store(in: &cancellables)

        modelManager.objectWillChange
            .debounce(for: .milliseconds(100), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.model = MenuBarModelSnapshot.current(modelManager: modelManager)
                    self.canTranscribeFiles = self.model.isReady || self.model.loadsOnDemand
                    self.refreshStatus()
                }
            }
            .store(in: &cancellables)

        Publishers.Merge(
            container.recentTranscriptionStore.$sessionEntries.map { _ in () },
            container.historyService.$records.map { _ in () }
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in
            MainActor.assumeIsolated {
                self?.hasRecentTranscriptions = Self.hasRecentTranscriptions()
            }
        }
        .store(in: &cancellables)

        container.audioRecordingService.$recoverableRecordingURL
            .receive(on: DispatchQueue.main)
            .sink { [weak self] url in
                MainActor.assumeIsolated {
                    self?.hasRecoverableRecording = url != nil
                }
            }
            .store(in: &cancellables)

        Publishers.CombineLatest3(
            recorder.$state.removeDuplicates(),
            recorder.$micEnabled.removeDuplicates(),
            recorder.$systemAudioEnabled.removeDuplicates()
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] state, micEnabled, systemAudioEnabled in
            MainActor.assumeIsolated {
                self?.recorderState = state
                self?.canToggleRecorder = AudioRecorderViewModel.canToggleRecording(
                    state: state,
                    micEnabled: micEnabled,
                    systemAudioEnabled: systemAudioEnabled
                )
            }
        }
        .store(in: &cancellables)

        dictation.$hotkeyLabelsVersion
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.refreshShortcuts()
                }
            }
            .store(in: &cancellables)

        hotkeyService.$dictationHotkeysPaused
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] paused in
                MainActor.assumeIsolated {
                    self?.dictationHotkeysPaused = paused
                    self?.refreshStatus()
                }
            }
            .store(in: &cancellables)
    }

    private func refreshStatus() {
        let resolved = MenuBarStatus.resolve(
            hotkeysPaused: dictationHotkeysPaused,
            dictationState: dictationState,
            model: model,
            shortcut: shortcut
        )
        if resolved != status { status = resolved }
    }

    private func refreshShortcuts() {
        shortcut = MenuBarShortcutHint.resolve(loadHotkeys: DictationSettingsHandler.loadHotkeys)
        recentTranscriptionsMenuShortcut = DictationSettingsHandler.loadMenuShortcutDescriptor(for: .recentTranscriptions)
        copyLastTranscriptionMenuShortcut = DictationSettingsHandler.loadMenuShortcutDescriptor(for: .copyLastTranscription)
        recorderToggleMenuShortcut = DictationSettingsHandler.loadMenuShortcutDescriptor(for: .recorderToggle)
        refreshStatus()
    }

    private static func hasRecentTranscriptions() -> Bool {
        let container = ServiceContainer.shared
        return container.recentTranscriptionStore.latestEntry(historyRecords: container.historyService.records) != nil
    }
}

// MARK: - Layout

enum MenuBarMenuItem: Hashable {
    case status
    case recoverLastRecording
    case toggleRecorder
    case transcribeFile
    case recentTranscriptions
    case copyLastTranscription
    case toggleDictationPause
    case openLeise
    case settings
    case checkForUpdates
    case about
    case quit
}

enum MenuBarMenuEntry: Hashable, Identifiable {
    case item(MenuBarMenuItem)
    /// Numbered so every divider has its own identity.
    case divider(Int)

    var id: Self { self }
}

/// The menu, top to bottom: status first, then everything by how often it
/// is used. Groups are separated by lines only, without section headers.
enum MenuBarMenuLayout {
    static func entries(hasRecoverableRecording: Bool) -> [MenuBarMenuEntry] {
        var entries: [MenuBarMenuEntry] = [.item(.status)]
        if hasRecoverableRecording {
            entries.append(.item(.recoverLastRecording))
        }
        entries += [
            .divider(1),
            .item(.toggleRecorder),
            .item(.transcribeFile),
            .item(.recentTranscriptions),
            .item(.copyLastTranscription),
            .divider(2),
            .item(.toggleDictationPause),
            .divider(3),
            .item(.openLeise),
            .item(.settings),
            .divider(4),
            .item(.checkForUpdates),
            .item(.about),
            .item(.quit),
        ]
        return entries
    }

    static func items(hasRecoverableRecording: Bool) -> [MenuBarMenuItem] {
        entries(hasRecoverableRecording: hasRecoverableRecording).compactMap { entry in
            if case let .item(item) = entry { return item }
            return nil
        }
    }
}

// MARK: - Images

/// Every item gets the same symbol slot, so titles line up whether an item
/// has a symbol or not (the last group has none).
@MainActor
enum MenuItemSymbol {
    static let slotSize = CGSize(width: 18, height: 16)
    private static var cache: [String: NSImage] = [:]

    static func image(_ systemName: String?) -> NSImage {
        let key = systemName ?? ""
        if let cached = cache[key] { return cached }

        let symbol = systemName.flatMap { name in
            NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: NSFont.systemFontSize, weight: .regular))
        }
        let image = NSImage(size: slotSize, flipped: false) { rect in
            guard let symbol else { return true }
            let size = symbol.size
            symbol.draw(in: CGRect(
                x: rect.midX - size.width / 2,
                y: rect.midY - size.height / 2,
                width: size.width,
                height: size.height
            ))
            return true
        }
        image.isTemplate = true
        cache[key] = image
        return image
    }
}

/// The status header's icon: the mark in a Petrol tile, with a status dot
/// in the free corner under the short bars.
@MainActor
enum MenuBarStatusTile {
    static let size = CGSize(width: 26, height: 26)
    private static let markHeightRatio: CGFloat = 0.5
    private static let dotDiameter: CGFloat = 6
    private static let dotInset: CGFloat = 2
    private static let washOpacity: CGFloat = 0.14

    static func image(for kind: MenuBarStatus.Kind) -> NSImage {
        let dotColor = dotColor(for: kind)
        let image = NSImage(size: size, flipped: false) { rect in
            let tint = NSColor(named: "AccentColor") ?? .controlAccentColor
            tint.withAlphaComponent(washOpacity).setFill()
            NSBezierPath(roundedRect: rect, xRadius: LeiseRadius.control, yRadius: LeiseRadius.control).fill()

            tint.setFill()
            let markHeight = rect.height * markHeightRatio
            let markRect = CGRect(x: rect.minX, y: rect.midY - markHeight / 2, width: rect.width, height: markHeight)
            for bar in LeiseMarkShape.barRects(in: markRect) {
                NSBezierPath(roundedRect: bar, xRadius: bar.width / 2, yRadius: bar.width / 2).fill()
            }

            dotColor.setFill()
            NSBezierPath(ovalIn: CGRect(
                x: rect.maxX - dotDiameter - dotInset,
                y: rect.minY + dotInset,
                width: dotDiameter,
                height: dotDiameter
            )).fill()
            return true
        }
        image.isTemplate = false
        return image
    }

    private static func dotColor(for kind: MenuBarStatus.Kind) -> NSColor {
        switch kind {
        case .ready: LeiseColor.readyNS
        case .loading, .writing: NSColor(named: "AccentColor") ?? .controlAccentColor
        case .noModel: LeiseColor.recordNS
        case .paused: .secondaryLabelColor
        case .listening: LeiseColor.liveNS
        }
    }
}

// MARK: - About

@MainActor
enum LeiseAboutPanel {
    static var credits: String {
        String(localized: "Free software under GPL-3.0. A community fork of TypeWhisper for Mac, not affiliated with that project.")
    }

    static func show() {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributedCredits = NSAttributedString(
            string: credits,
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: paragraph,
            ]
        )
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: [.credits: attributedCredits])
    }
}

// MARK: - Menu

struct MenuBarView: View {
    @Environment(\.openWindow) private var openWindow
    @StateObject private var status = MenuBarState()

    var body: some View {
        Group {
            // Deliberate body side effect: a MenuBarExtra's content receives
            // onAppear only when the menu opens, but AppKit-side callers need
            // the environment's openWindow action from the first body
            // evaluation at launch (setup-wizard auto-open). Idempotent.
            let _ = { ManagedAppWindowOpener.shared.openWindow = openWindow }()

            ForEach(MenuBarMenuLayout.entries(hasRecoverableRecording: status.hasRecoverableRecording)) { entry in
                switch entry {
                case .divider:
                    Divider()
                case let .item(item):
                    menuItem(for: item)
                }
            }
        }
        .labelStyle(.titleAndIcon)
        .onReceive(NotificationCenter.default.publisher(for: .openManagedAppWindow)) { notification in
            guard let id = notification.userInfo?["id"] as? String else { return }
            openWindow(id: id)
        }
    }

    @ViewBuilder
    private func menuItem(for item: MenuBarMenuItem) -> some View {
        switch item {
        case .status:
            Button {
                LeiseWindowNavigator.openOverview()
            } label: {
                Label {
                    Text(status.status.title)
                } icon: {
                    Image(nsImage: MenuBarStatusTile.image(for: status.status.kind))
                        .renderingMode(.original)
                }
                Text(status.status.subtitle)
            }

        case .recoverLastRecording:
            Button {
                LeiseWindowNavigator.openRecovery()
            } label: {
                itemLabel(String(localized: "Recover Last Recording"), symbol: "arrow.counterclockwise")
            }

        case .toggleRecorder:
            Button {
                ServiceContainer.shared.audioRecorderViewModel.toggleRecording()
            } label: {
                itemLabel(recorderToggleTitle, symbol: recorderToggleSymbol)
            }
            .keyboardShortcut(keyboardShortcut(from: status.recorderToggleMenuShortcut))
            .disabled(!status.canToggleRecorder)

        case .transcribeFile:
            Button {
                ManagedAppWindowOpener.shared.open(id: LeiseWindowNavigator.mainWindowID)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    ServiceContainer.shared.fileTranscriptionViewModel.showFilePickerFromMenu = true
                }
            } label: {
                itemLabel(String(localized: "Transcribe File…"), symbol: "doc.text")
            }
            .disabled(!status.canTranscribeFiles)

        case .recentTranscriptions:
            Button {
                ServiceContainer.shared.dictationViewModel.triggerRecentTranscriptionsPalette()
            } label: {
                itemLabel(String(localized: "Recent Transcriptions…"), symbol: "clock.arrow.circlepath")
            }
            .keyboardShortcut(keyboardShortcut(from: status.recentTranscriptionsMenuShortcut))
            .disabled(!status.hasRecentTranscriptions)

        case .copyLastTranscription:
            Button {
                ServiceContainer.shared.dictationViewModel.copyLastTranscriptionToClipboard()
            } label: {
                itemLabel(String(localized: "Copy Last Transcription"), symbol: "doc.on.doc")
            }
            .keyboardShortcut(keyboardShortcut(from: status.copyLastTranscriptionMenuShortcut))
            .disabled(!status.hasRecentTranscriptions)

        case .toggleDictationPause:
            Button {
                ServiceContainer.shared.hotkeyService.dictationHotkeysPaused.toggle()
            } label: {
                itemLabel(
                    status.dictationHotkeysPaused ? String(localized: "Resume Dictation") : String(localized: "Pause Dictation"),
                    symbol: status.dictationHotkeysPaused ? "play.circle" : "pause.circle"
                )
            }

        case .openLeise:
            Button {
                LeiseWindowNavigator.openOverview()
            } label: {
                itemLabel(String(localized: "Open Leise"), symbol: "house")
            }

        case .settings:
            Button {
                LeiseWindowNavigator.openDictationSettings()
            } label: {
                itemLabel(String(localized: "Settings…"), symbol: "gearshape")
            }
            .keyboardShortcut(",")

        case .checkForUpdates:
            Button {
                UpdateChecker.shared?.checkForUpdates()
            } label: {
                itemLabel(String(localized: "Check for Updates…"), symbol: nil)
            }
            .disabled(UpdateChecker.shared?.canCheckForUpdates() != true)

        case .about:
            Button {
                LeiseAboutPanel.show()
            } label: {
                itemLabel(String(localized: "About Leise"), symbol: nil)
            }

        case .quit:
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                itemLabel(String(localized: "Quit"), symbol: nil)
            }
            .keyboardShortcut("q")
        }
    }

    private func itemLabel(_ title: String, symbol: String?) -> some View {
        Label {
            Text(title)
        } icon: {
            Image(nsImage: MenuItemSymbol.image(symbol))
                .renderingMode(.template)
        }
    }

    private var recorderToggleTitle: String {
        switch status.recorderState {
        case .idle:
            String(localized: "recorder.startRecording")
        case .recording:
            String(localized: "recorder.stopRecording")
        case .finalizing:
            String(localized: "Finishing Recording…")
        }
    }

    private var recorderToggleSymbol: String {
        switch status.recorderState {
        case .idle:
            "record.circle"
        case .recording:
            "stop.circle"
        case .finalizing:
            "hourglass"
        }
    }

    private func keyboardShortcut(
        from descriptor: HotkeyService.MenuShortcutDescriptor?
    ) -> KeyboardShortcut? {
        guard let descriptor else { return nil }
        return KeyboardShortcut(
            KeyEquivalent(descriptor.keyEquivalent),
            modifiers: eventModifiers(from: descriptor.modifiers)
        )
    }

    private func eventModifiers(from flags: NSEvent.ModifierFlags) -> EventModifiers {
        var modifiers: EventModifiers = []
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.function) { modifiers.insert(EventModifiers(rawValue: 1 << 23)) }
        return modifiers
    }
}
