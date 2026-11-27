import SwiftUI
import AVFoundation
import Combine
import ParakeetEngine
@preconcurrency import Sparkle

extension UserDefaults {
    @objc dynamic var showMenuBarIcon: Bool {
        bool(forKey: UserDefaultsKeys.showMenuBarIcon)
    }

    @objc dynamic var dockIconBehaviorWhenMenuBarHidden: String {
        string(forKey: UserDefaultsKeys.dockIconBehaviorWhenMenuBarHidden)
            ?? DockIconBehavior.keepVisible.rawValue
    }
}

extension Notification.Name {
    static let openManagedAppWindow = Notification.Name("openManagedAppWindow")
    static let resetSetupWizardWindow = Notification.Name("resetSetupWizardWindow")
}

enum DockIconBehavior: String, CaseIterable {
    case keepVisible
    case onlyWhileWindowOpen
}

enum DockIconVisibility {
    static func shouldShowDockIcon(
        showMenuBarIcon: Bool,
        dockIconBehavior: DockIconBehavior,
        hasVisibleManagedWindow: Bool,
        hasInteractiveForegroundContent: Bool = false
    ) -> Bool {
        if hasVisibleManagedWindow || hasInteractiveForegroundContent {
            return true
        }

        guard !showMenuBarIcon else { return false }
        return dockIconBehavior == .keepVisible
    }
}

/// What the menu bar glyph shows. Every state changes the shape, never only
/// the color: moving bars while dictating, a wave while writing, and a dot
/// while the recorder runs.
struct MenuBarGlyphStyle: Equatable {
    enum Bars: Equatable {
        case resting
        /// Bars follow the voice level.
        case live
        /// A crest travels across the bars.
        case wave
        /// Reduce Motion: a distinct still shape for listening.
        case listeningStill
        /// Reduce Motion: a distinct still shape for writing.
        case waveStill
    }

    enum Tint: Equatable {
        /// A template image in the menu bar's own color.
        case template
        /// Microphone Orange: dictation is listening.
        case live
        /// Record Red: the recorder is running.
        case record
    }

    var bars: Bars
    var tint: Tint
    var showsRecordingDot: Bool

    static let idle = MenuBarGlyphStyle(bars: .resting, tint: .template, showsRecordingDot: false)

    static func resolve(
        dictationState: DictationViewModel.State,
        recorderState: AudioRecorderViewModel.RecorderState,
        reduceMotion: Bool
    ) -> MenuBarGlyphStyle {
        let recorderRunning = recorderState == .recording
        let quietTint: Tint = recorderRunning ? .record : .template
        switch dictationState {
        case .recording:
            return MenuBarGlyphStyle(bars: reduceMotion ? .listeningStill : .live, tint: .live, showsRecordingDot: recorderRunning)
        case .processing:
            return MenuBarGlyphStyle(bars: reduceMotion ? .waveStill : .wave, tint: quietTint, showsRecordingDot: recorderRunning)
        case .idle, .inserting, .error:
            return MenuBarGlyphStyle(bars: .resting, tint: quietTint, showsRecordingDot: recorderRunning)
        }
    }

    /// Only these tick; everything else is a still image.
    var animates: Bool {
        bars == .live || bars == .wave
    }

    var isTemplate: Bool {
        tint == .template && !showsRecordingDot
    }

    /// Heights for the still states, or the starting frame of a moving one.
    var stillHeights: [CGFloat] {
        switch bars {
        case .resting, .live: LeiseMarkShape.restingHeights
        case .listeningStill: LeiseMarkShape.listeningHeights
        case .wave: LeiseMarkShape.waveHeights(time: 0)
        case .waveStill: MenuBarLogoMarkImage.writingStillHeights
        }
    }
}

/// Draws the menu bar glyph from the Leise mark's geometry.
enum MenuBarLogoMarkImage {
    /// The mark's slot. 1.37 × the 14 pt mark is about 19 pt wide.
    static let markSize = CGSize(width: 20, height: 18)
    static let dotDiameter: CGFloat = 5
    static let dotSpacing: CGFloat = 2
    /// Keeps the bars clear of the menu bar's edges, as LeiseMarkShape.image does.
    private static let verticalInsetRatio: CGFloat = 0.11
    /// Even, mid-height bars: "writing" without motion.
    static let writingStillHeights: [CGFloat] = Array(repeating: 0.6, count: LeiseMarkShape.barCount)

    static func size(showsRecordingDot: Bool) -> CGSize {
        guard showsRecordingDot else { return markSize }
        return CGSize(width: markSize.width + dotSpacing + dotDiameter, height: markSize.height)
    }

    static func barRects(in rect: CGRect, heights: [CGFloat] = LeiseMarkShape.restingHeights) -> [CGRect] {
        LeiseMarkShape.barRects(in: rect.insetBy(dx: 0, dy: rect.height * verticalInsetRatio), heights: heights)
    }

    static func image(style: MenuBarGlyphStyle, heights: [CGFloat]? = nil) -> NSImage {
        let heights = heights ?? style.stillHeights
        let barColor: NSColor = switch style.tint {
        case .template: .black
        case .live: LeiseColor.liveNS
        case .record: LeiseColor.recordNS
        }
        let showsDot = style.showsRecordingDot
        let image = NSImage(size: size(showsRecordingDot: showsDot), flipped: false) { bounds in
            barColor.setFill()
            let markRect = CGRect(x: bounds.minX, y: bounds.minY, width: markSize.width, height: bounds.height)
            for bar in barRects(in: markRect, heights: heights) {
                NSBezierPath(roundedRect: bar, xRadius: bar.width / 2, yRadius: bar.width / 2).fill()
            }
            if showsDot {
                LeiseColor.recordNS.setFill()
                NSBezierPath(ovalIn: CGRect(
                    x: markRect.maxX + dotSpacing,
                    y: bounds.midY - dotDiameter / 2,
                    width: dotDiameter,
                    height: dotDiameter
                )).fill()
            }
            return true
        }
        image.isTemplate = style.isTemplate
        return image
    }
}

/// Feeds the menu bar label. It ticks at most 20 times a second and only
/// while the bars move; idle, it holds one still image.
@MainActor
final class MenuBarGlyphModel: ObservableObject {
    @Published private(set) var image: NSImage
    @Published private(set) var isTemplate: Bool
    @Published private(set) var stateDescription: String

    private let dictation: DictationViewModel
    private let announcer: AccessibilityAnnouncementService
    private var dictationState: DictationViewModel.State
    private var recorderState: AudioRecorderViewModel.RecorderState
    private var reduceMotion: Bool
    private var style: MenuBarGlyphStyle
    private var timer: Timer?
    private var smoothedLevel = 0.0
    private var lastHeights: [CGFloat] = []
    private var cancellables = Set<AnyCancellable>()

    static let frameInterval: TimeInterval = 1.0 / 20
    /// The level rises quickly and falls slowly, like a VU meter.
    private static let attack = 0.55
    private static let release = 0.18
    /// Height changes below this are not worth a new image.
    private static let heightResolution: CGFloat = 0.02

    init(
        dictation: DictationViewModel = ServiceContainer.shared.dictationViewModel,
        recorder: AudioRecorderViewModel = ServiceContainer.shared.audioRecorderViewModel,
        announcer: AccessibilityAnnouncementService = ServiceContainer.shared.accessibilityAnnouncementService
    ) {
        self.dictation = dictation
        self.announcer = announcer
        dictationState = dictation.state
        recorderState = recorder.state
        reduceMotion = LeiseMotion.systemReduceMotion
        style = MenuBarGlyphStyle.resolve(
            dictationState: dictation.state,
            recorderState: recorder.state,
            reduceMotion: LeiseMotion.systemReduceMotion
        )
        image = MenuBarLogoMarkImage.image(style: style)
        isTemplate = style.isTemplate
        stateDescription = Self.describe(dictationState: dictation.state, recorderState: recorder.state)

        dictation.$state
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                MainActor.assumeIsolated {
                    self?.dictationState = state
                    self?.update()
                }
            }
            .store(in: &cancellables)

        recorder.$state
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                MainActor.assumeIsolated {
                    self?.recorderStateDidChange(to: state)
                }
            }
            .store(in: &cancellables)

        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.reduceMotion = LeiseMotion.systemReduceMotion
                    self?.update()
                }
            }
            .store(in: &cancellables)

        update()
    }

    isolated deinit {
        timer?.invalidate()
    }

    private func recorderStateDidChange(to state: AudioRecorderViewModel.RecorderState) {
        let wasRunning = recorderState == .recording
        recorderState = state
        let isRunning = state == .recording
        if isRunning != wasRunning {
            announcer.announce(isRunning ? String(localized: "Recorder running") : String(localized: "Recorder stopped"))
        }
        update()
    }

    private func update() {
        let newStyle = MenuBarGlyphStyle.resolve(
            dictationState: dictationState,
            recorderState: recorderState,
            reduceMotion: reduceMotion
        )
        let styleChanged = newStyle != style
        style = newStyle
        let description = Self.describe(dictationState: dictationState, recorderState: recorderState)
        if description != stateDescription { stateDescription = description }

        if style.animates {
            startTicking()
            if styleChanged { render(heights: style.stillHeights, force: true) }
        } else {
            stopTicking()
            render(heights: style.stillHeights, force: styleChanged)
        }
    }

    private func startTicking() {
        guard timer == nil else { return }
        smoothedLevel = 0
        let timer = Timer(timeInterval: Self.frameInterval, repeats: true) { [weak self] _ in
            // Scheduled on the main run loop below.
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopTicking() {
        timer?.invalidate()
        timer = nil
        smoothedLevel = 0
    }

    private func tick() {
        let time = Date.timeIntervalSinceReferenceDate
        switch style.bars {
        case .live:
            let level = Double(dictation.audioLevel)
            let rate = level > smoothedLevel ? Self.attack : Self.release
            smoothedLevel += (level - smoothedLevel) * rate
            render(heights: LeiseMarkShape.liveHeights(level: smoothedLevel, time: time))
        case .wave:
            render(heights: LeiseMarkShape.waveHeights(time: time))
        case .resting, .listeningStill, .waveStill:
            stopTicking()
        }
    }

    /// Publishes a new image only when the bars visibly moved or the style
    /// changed, so a quiet voice does not cost a redraw every frame.
    private func render(heights: [CGFloat], force: Bool = false) {
        let quantized = heights.map { ($0 / Self.heightResolution).rounded() * Self.heightResolution }
        guard force || quantized != lastHeights else { return }
        lastHeights = quantized
        image = MenuBarLogoMarkImage.image(style: style, heights: quantized)
        if style.isTemplate != isTemplate { isTemplate = style.isTemplate }
    }

    static func describe(
        dictationState: DictationViewModel.State,
        recorderState: AudioRecorderViewModel.RecorderState
    ) -> String {
        var parts: [String] = []
        switch dictationState {
        case .recording: parts.append(String(localized: "Listening…"))
        case .processing: parts.append(String(localized: "Writing…"))
        case .idle, .inserting, .error: break
        }
        if recorderState == .recording {
            parts.append(String(localized: "Recorder running"))
        }
        return parts.isEmpty ? String(localized: "Idle") : parts.joined(separator: ", ")
    }
}

private struct MenuBarExtraLabel: View {
    @Environment(\.openWindow) private var openWindow
    @StateObject private var glyph = MenuBarGlyphModel()

    private var title: String {
        AppConstants.isDevelopment ? "Leise Dev" : "Leise"
    }

    var body: some View {
        Image(nsImage: glyph.image)
            .renderingMode(glyph.isTemplate ? .template : .original)
            .accessibilityLabel(Text(verbatim: title))
            .accessibilityValue(Text(glyph.stateDescription))
            .onAppear {
                ManagedAppWindowOpener.shared.openWindow = openWindow
            }
            .onReceive(NotificationCenter.default.publisher(for: .openManagedAppWindow)) { notification in
                guard let id = notification.userInfo?["id"] as? String else { return }
                ManagedAppWindowOpener.shared.openWindow = openWindow
                openWindow(id: id)
            }
    }
}

private struct ManagedWindowOpenerRegistrar: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        EmptyView()
            .onAppear {
                ManagedAppWindowOpener.shared.openWindow = openWindow
            }
    }
}

/// Opens the main window on a page. Callers name the destination; the
/// coordinator maps it to the window's pages.
@MainActor
enum LeiseWindowNavigator {
    /// The main window keeps its original identifier, so saved frames and
    /// AppKit lookups still match.
    static let mainWindowID = "settings"
    static let setupWindowID = "setup"

    /// "Leise öffnen": the overview.
    static func openOverview() {
        SettingsNavigationCoordinator.shared.showOverview()
        openMainWindow()
    }

    /// "Einstellungen …" (⌘,): straight to Diktat.
    static func openDictationSettings() {
        SettingsNavigationCoordinator.shared.showDictationSettings()
        openMainWindow()
    }

    static func openHistory() {
        SettingsNavigationCoordinator.shared.showHistory()
        openMainWindow()
    }

    static func openRecovery() {
        SettingsNavigationCoordinator.shared.showRecovery()
        openMainWindow()
    }

    static func openMainWindow() {
        ManagedAppWindowOpener.shared.open(id: mainWindowID)
    }
}

struct LeiseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @AppStorage(UserDefaultsKeys.showMenuBarIcon) private var showMenuBarIcon = true

    var body: some Scene {
        MenuBarExtra(isInserted: $showMenuBarIcon) {
            menuBarContent
        } label: {
            if AppConstants.isRunningTests {
                EmptyView()
            } else {
                MenuBarExtraLabel()
            }
        }
        .menuBarExtraStyle(.menu)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button(String(localized: "About Leise")) {
                    LeiseAboutPanel.show()
                }
                ManagedWindowOpenerRegistrar()
            }
            CommandGroup(replacing: .appSettings) {
                Button(String(localized: "Settings…")) {
                    LeiseWindowNavigator.openDictationSettings()
                }
                .keyboardShortcut(",")
            }
        }

        mainWindowScene

        Window(String(localized: "Leise Setup"), id: LeiseWindowNavigator.setupWindowID) {
            setupContent
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(SetupWizardView.windowSize)
    }

    /// The app's one window. History, recovery and settings are pages in it.
    private var mainWindowScene: some Scene {
        Window(String(localized: "Leise"), id: LeiseWindowNavigator.mainWindowID) {
            settingsContent
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1050, height: 600)
    }

    @ViewBuilder
    private var menuBarContent: some View {
        if AppConstants.isRunningTests {
            EmptyView()
        } else {
            MenuBarView()
        }
    }

    @ViewBuilder
    private var settingsContent: some View {
        if AppConstants.isRunningTests {
            EmptyView()
        } else {
            SettingsView()
        }
    }

    @ViewBuilder
    private var setupContent: some View {
        if AppConstants.isRunningTests {
            EmptyView()
        } else {
            SetupWizardView()
        }
    }

    init() {
        guard !AppConstants.isRunningTests else { return }
        let performanceToken = PerformanceMilestones.begin(.appInitialization)
        defer { PerformanceMilestones.end(performanceToken) }

        // Trigger ServiceContainer initialization
        _ = ServiceContainer.shared

        Task { @MainActor in
            await ServiceContainer.shared.initialize()
        }
    }

}

@MainActor
final class ActivationSourceTracker {
    static let shared = ActivationSourceTracker()

    private(set) var lastExternalApplication: NSRunningApplication?

    func recordActivation(_ application: NSRunningApplication?) {
        guard let application else { return }
        if application.processIdentifier == NSRunningApplication.current.processIdentifier {
            return
        }
        lastExternalApplication = application
    }
}

@MainActor
final class ManagedAppWindowOpener {
    static let shared = ManagedAppWindowOpener()

    var openWindow: OpenWindowAction?

    func open(id: String) {
        open(id: id, remainingAttempts: 10)
    }

    private func open(id: String, remainingAttempts: Int) {
        let sourceApplication = sourceApplicationForActivation()
        NSApp.setActivationPolicy(.regular)

        if let existingWindow = managedWindow(id: id) {
            reopenExistingWindow(existingWindow, sourceApplication: sourceApplication)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                self.reopenExistingWindow(existingWindow, sourceApplication: sourceApplication)
            }
            return
        }

        if let openWindow {
            openWindow(id: id)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                guard let window = self.managedWindow(id: id) else { return }
                self.reopenExistingWindow(window, sourceApplication: sourceApplication)
            }
        } else {
            NotificationCenter.default.post(
                name: .openManagedAppWindow,
                object: nil,
                userInfo: ["id": id]
            )
            // The retry re-fronts the window itself; scheduling the deferred
            // re-front here too would double-activate it.
            if remainingAttempts > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    self.open(id: id, remainingAttempts: remainingAttempts - 1)
                }
            }
        }
    }

    private func sourceApplicationForActivation() -> NSRunningApplication? {
        ActivationSourceTracker.shared.lastExternalApplication
            ?? NSWorkspace.shared.frontmostApplication
    }

    private func managedWindow(id: String) -> NSWindow? {
        NSApp.windows.first(where: {
            $0.identifier?.rawValue.localizedCaseInsensitiveContains(id) == true
        })
    }

    private func reopenExistingWindow(_ window: NSWindow, sourceApplication: NSRunningApplication?) {
        NSApp.unhide(nil)
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        requestActivation(from: sourceApplication)
    }

    private func requestActivation(from sourceApplication: NSRunningApplication?) {
        let currentApplication = NSRunningApplication.current

        guard let sourceApplication,
              sourceApplication.processIdentifier != currentApplication.processIdentifier else {
            forceActivateCurrentApplication(currentApplication)
            return
        }

        let activated = currentApplication.activate(from: sourceApplication)
        if !activated {
            forceActivateCurrentApplication(currentApplication)
        }
    }

    private func forceActivateCurrentApplication(_ application: NSRunningApplication) {
        _ = application.activate()
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - App Delegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, SPUUpdaterDelegate {
    private var indicatorCoordinator: IndicatorCoordinator?
    private var recordingReminderService: RecordingReminderService?
    private var menuBarIconObserver: NSKeyValueObservation?
    private var dockIconBehaviorObserver: NSKeyValueObservation?
    private var appActivationObserver: NSObjectProtocol?
    private var workspaceWakeObserver: NSObjectProtocol?
    private var hasInteractiveForegroundContent = false
    private lazy var updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)

    var updateChecker: UpdateChecker {
        .sparkle(updaterController.updater)
    }

    private var showMenuBarIconPreference: Bool {
        UserDefaults.standard.object(forKey: UserDefaultsKeys.showMenuBarIcon) as? Bool ?? true
    }

    private var dockIconBehaviorPreference: DockIconBehavior {
        DockIconBehavior(rawValue: UserDefaults.standard.dockIconBehaviorWhenMenuBarHidden) ?? .keepVisible
    }

    private var shouldShowDockIcon: Bool {
        DockIconVisibility.shouldShowDockIcon(
            showMenuBarIcon: showMenuBarIconPreference,
            dockIconBehavior: dockIconBehaviorPreference,
            hasVisibleManagedWindow: hasVisibleManagedWindow,
            hasInteractiveForegroundContent: hasInteractiveForegroundContent
        )
    }

    static func registerDefaultUserDefaults(_ defaults: UserDefaults = .standard) {
        defaults.register(defaults: [
            UserDefaultsKeys.showMenuBarIcon: true,
            UserDefaultsKeys.dockIconBehaviorWhenMenuBarHidden: DockIconBehavior.keepVisible.rawValue,
            UserDefaultsKeys.updateChannel: AppConstants.defaultReleaseChannel.rawValue,
            UserDefaultsKeys.appFormattingEnabled: true,
            UserDefaultsKeys.transcriptionNumberNormalizationEnabled: true
        ])
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.registerDefaultUserDefaults()

        guard !AppConstants.isRunningTests else {
            return
        }

        UpdateChecker.shared = updateChecker
        applyActivationPolicy()

        let coordinator = IndicatorCoordinator()
        coordinator.startObserving()
        indicatorCoordinator = coordinator

        let reminderService = RecordingReminderService(recorder: ServiceContainer.shared.audioRecorderViewModel)
        reminderService.startObserving()
        recordingReminderService = reminderService

        ServiceContainer.shared.hotkeyService.onRecentTranscriptionsToggle = {
            ServiceContainer.shared.dictationViewModel.triggerRecentTranscriptionsPalette()
        }
        ServiceContainer.shared.hotkeyService.onCopyLastTranscription = {
            ServiceContainer.shared.dictationViewModel.copyLastTranscriptionToClipboard()
        }
        ServiceContainer.shared.hotkeyService.onRecorderToggle = {
            ServiceContainer.shared.audioRecorderViewModel.toggleRecording()
        }

        // Auto-open the standalone setup assistant while first-run setup is incomplete.
        if ServiceContainer.shared.homeViewModel.showSetupWizard {
            UserDefaults.standard.set(false, forKey: UserDefaultsKeys.setupWizardCompleted)
            NSApp.setActivationPolicy(.regular)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.openSetupWindow()
            }
        }

        // Observe appearance preference changes
        menuBarIconObserver = UserDefaults.standard.observe(\.showMenuBarIcon, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in
                self?.applyActivationPolicy()
            }
        }
        dockIconBehaviorObserver = UserDefaults.standard.observe(\.dockIconBehaviorWhenMenuBarHidden, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in
                self?.applyActivationPolicy()
            }
        }

        appActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { notification in
            let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            Task { @MainActor in
                ActivationSourceTracker.shared.recordActivation(application)
            }
        }

        workspaceWakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { _ in
            ParakeetRuntimeRecovery.resetNetworkingAfterWake()
        }

        // Observe settings window lifecycle
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeKey(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: nil
        )

        DispatchQueue.main.async {
            PerformanceMilestones.uiReady()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleManagedWindow {
            if ServiceContainer.shared.homeViewModel.showSetupWizard {
                openSetupWindow()
            } else {
                openSettingsWindow()
            }
        }
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            handleIncomingURL(url)
        }
    }

    private func openSettingsWindow() {
        LeiseWindowNavigator.openMainWindow()
    }

    private func openSetupWindow() {
        ManagedAppWindowOpener.shared.open(id: LeiseWindowNavigator.setupWindowID)
    }

    private func handleIncomingURL(_ url: URL) {
        _ = url
    }

    private func isManagedWindow(_ window: NSWindow) -> Bool {
        if let identifier = window.identifier?.rawValue.lowercased() {
            if identifier.contains(LeiseWindowNavigator.mainWindowID)
                || identifier.contains(LeiseWindowNavigator.setupWindowID) {
                return true
            }
        }

        let title = window.title
        return title == String(localized: "Leise")
            || title == String(localized: "Leise Setup")
    }

    private var hasVisibleManagedWindow: Bool {
        NSApp.windows.contains { isManagedWindow($0) && $0.isVisible }
    }

    private func applyActivationPolicy(activate: Bool = false) {
        let targetPolicy: NSApplication.ActivationPolicy = shouldShowDockIcon ? .regular : .accessory
        if NSApp.activationPolicy() != targetPolicy {
            NSApp.setActivationPolicy(targetPolicy)
        }

        if activate {
            NSApp.activate()
        }
    }

    @objc nonisolated private func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isManagedWindow(window), window.isVisible else { return }
            self.applyActivationPolicy(activate: true)
        }
    }

    @objc nonisolated private func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isManagedWindow(window) else { return }
            self.applyActivationPolicy()
        }
    }

    nonisolated func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        AppConstants.effectiveUpdateChannel.sparkleChannels
    }
}
