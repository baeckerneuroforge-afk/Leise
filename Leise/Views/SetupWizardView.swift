import AppKit
import Combine
import LeiseCore
import ParakeetEngine
import SwiftUI

// The setup window: four steps (Willkommen, Zugriff, Tastenkürzel,
// Ausprobieren) in a native window that follows the system appearance. The
// language model downloads in the background from the first step on; the
// footer chip reports it. Step views live in SetupSteps.swift.

// MARK: - Steps

enum SetupWizardStep: Int, CaseIterable, Identifiable {
    case welcome
    case access
    case shortcut
    case tryIt

    var id: Int { rawValue }
    var number: Int { rawValue + 1 }

    /// Restores a saved step, including one saved by the earlier five-step
    /// wizard: its "AI & Engine" and "Finish" steps both map to "Try it".
    static func restored(fromSavedIndex index: Int) -> SetupWizardStep {
        SetupWizardStep(rawValue: min(max(index, 0), allCases.count - 1)) ?? .welcome
    }

    var title: String {
        switch self {
        case .welcome: String(localized: "Welcome to Leise")
        case .access: String(localized: "Two permissions, then you’re ready")
        case .shortcut: String(localized: "Hold or tap")
        case .tryIt: String(localized: "Try it out")
        }
    }

    var previous: SetupWizardStep? { SetupWizardStep(rawValue: rawValue - 1) }
    var next: SetupWizardStep? { SetupWizardStep(rawValue: rawValue + 1) }
}

/// Which way the last step change went; steps slide in from that side.
enum SetupTravel: Equatable {
    case forward
    case backward
    case inPlace

    var edgeSign: CGFloat {
        switch self {
        case .forward: 1
        case .backward: -1
        case .inPlace: 0
        }
    }
}

/// The footer's main button. On "Zugriff" it follows the permissions: first
/// the microphone, then (with Bedienungshilfen still missing) a plain "Später"
/// while the row's "Freigeben …" becomes the primary action.
enum SetupPrimaryAction: Equatable {
    case begin
    case allowMicrophone
    case later
    case next
    case finish

    static func resolve(
        step: SetupWizardStep,
        microphoneGranted: Bool,
        accessibilityGranted: Bool
    ) -> SetupPrimaryAction {
        switch step {
        case .welcome:
            .begin
        case .access:
            if !microphoneGranted { .allowMicrophone } else if !accessibilityGranted { .later } else { .next }
        case .shortcut:
            .next
        case .tryIt:
            .finish
        }
    }

    var title: String {
        switch self {
        case .begin: String(localized: "Let’s Go")
        case .allowMicrophone: String(localized: "Allow Microphone")
        case .later: String(localized: "Later")
        case .next: String(localized: "Next")
        case .finish: String(localized: "Finish")
        }
    }

    var isProminent: Bool { self != .later }

    /// Whether the row's "Freigeben …" takes over the default action.
    static func accessibilityRowIsPrimary(microphoneGranted: Bool, accessibilityGranted: Bool) -> Bool {
        microphoneGranted && !accessibilityGranted
    }
}

// MARK: - Model chip

/// Short, human names for the two Parakeet models.
enum ParakeetModelNaming {
    static func shortName(forModelID modelID: String?) -> String? {
        switch modelID {
        case SetupWizardParakeetRecommendation.v3ModelId?: "Parakeet v3"
        case SetupWizardParakeetRecommendation.v2ModelId?: "Parakeet v2"
        default: nil
        }
    }

    static func isMultilingual(modelID: String?) -> Bool {
        modelID == SetupWizardParakeetRecommendation.v3ModelId
    }
}

/// The footer chip that reports the background model download.
struct SetupModelChip: Equatable {
    enum Phase: Equatable {
        /// Nothing reported yet (the first instant after setup opens).
        case starting
        /// Transferring files, with the fraction of all bytes.
        case downloading(fractionCompleted: Double)
        /// Files are on disk; Core ML loads and warms the model up.
        case preparing
        case ready
        case failed
        case unsupported
    }

    var phase: Phase
    var modelID: String?

    static func resolve(
        isSupported: Bool,
        engineReady: Bool,
        selectedModelID: String?,
        status: ModelPreparationStatus?,
        activity: ParakeetModelActivity?,
        didFail: Bool
    ) -> SetupModelChip {
        guard isSupported else { return SetupModelChip(phase: .unsupported, modelID: selectedModelID) }
        if engineReady { return SetupModelChip(phase: .ready, modelID: selectedModelID) }

        switch activity {
        case let .downloading(modelID, fraction)?:
            return SetupModelChip(phase: .downloading(fractionCompleted: min(max(fraction, 0), 1)), modelID: modelID)
        case let .loading(modelID)?:
            return SetupModelChip(phase: .preparing, modelID: modelID)
        case nil:
            break
        }

        switch status {
        case .preparing?:
            return SetupModelChip(phase: .preparing, modelID: selectedModelID)
        case .failed?:
            return SetupModelChip(phase: .failed, modelID: selectedModelID)
        case .ready?:
            return SetupModelChip(phase: .ready, modelID: selectedModelID)
        case .idle?, nil:
            return SetupModelChip(phase: didFail ? .failed : .starting, modelID: selectedModelID)
        }
    }

    var isReady: Bool { phase == .ready }

    /// The bar's fill, or nil when there is no bar (ready, failed) or no
    /// fraction yet (indeterminate).
    var barFraction: Double? {
        if case let .downloading(fraction) = phase { return fraction }
        return nil
    }

    var showsBar: Bool {
        switch phase {
        case .starting, .downloading, .preparing: true
        case .ready, .failed, .unsupported: false
        }
    }

    var text: String {
        let multilingual = ParakeetModelNaming.isMultilingual(modelID: modelID)
        switch phase {
        case .starting, .preparing:
            return multilingual
                ? String(localized: "Preparing the multilingual model…")
                : String(localized: "Preparing the language model…")
        case let .downloading(fraction):
            let percent = fraction.formatted(.percent.precision(.fractionLength(0)))
            return multilingual
                ? String(localized: "Multilingual model loading · \(percent)")
                : String(localized: "English model loading · \(percent)")
        case .ready:
            let name = ParakeetModelNaming.shortName(forModelID: modelID) ?? "Parakeet"
            return String(localized: "Language model ready · \(name)")
        case .failed:
            return String(localized: "The language model couldn’t load")
        case .unsupported:
            return SetupWizardRecommendationUnavailableReason.appleSiliconOnly.message
        }
    }
}

/// Which model setup prepares. New installs get the language default; an
/// existing English-only choice is upgraded only when the user's languages
/// need the multilingual model, and a working multilingual setup is kept.
enum SetupModelChoice {
    static func targetModelID(currentModelID: String?, recommendedModelID: String) -> String {
        guard let currentModelID else { return recommendedModelID }
        if currentModelID == SetupWizardParakeetRecommendation.v2ModelId,
           recommendedModelID == SetupWizardParakeetRecommendation.v3ModelId {
            return recommendedModelID
        }
        return currentModelID
    }
}

// MARK: - Shortcut

/// The dictation shortcut as setup shows it, including the fn default that
/// setup saves when you continue past the shortcut step.
struct SetupShortcutDisplay: Equatable {
    var label: String
    var isFn: Bool
    /// Hybrid and push-to-talk shortcuts are held; toggle shortcuts are pressed.
    var isHeld: Bool
    /// fn is shown but not saved yet.
    var isPending: Bool
    var isConfigured: Bool

    static let fnLabel = "fn"

    static func resolve(
        hotkeys: [HotkeySlotType: [UnifiedHotkey]],
        recommendedApplies: Bool
    ) -> SetupShortcutDisplay {
        for slot in SetupWizardDefaultHotkey.triggerSlots {
            guard let hotkey = hotkeys[slot]?.first else { continue }
            return SetupShortcutDisplay(
                label: displayLabel(for: hotkey),
                isFn: hotkey.isFn,
                isHeld: slot != .toggle,
                isPending: false,
                isConfigured: true
            )
        }
        if recommendedApplies {
            return SetupShortcutDisplay(label: fnLabel, isFn: true, isHeld: true, isPending: true, isConfigured: true)
        }
        return SetupShortcutDisplay(
            label: String(localized: "Not set"),
            isFn: false,
            isHeld: true,
            isPending: false,
            isConfigured: false
        )
    }

    /// Apple prints a lowercase "fn" on the key, so plain fn reads that way.
    static func displayLabel(for hotkey: UnifiedHotkey) -> String {
        if hotkey.isFn, !hotkey.isDoubleTap { return fnLabel }
        return HotkeyService.displayName(for: hotkey)
    }

    /// The instruction under "Probier es aus".
    var tryItInstruction: String {
        guard isConfigured else { return String(localized: "Set a dictation shortcut first, then come back here.") }
        return isHeld
            ? String(localized: "Hold \(label) and say a sentence.")
            : String(localized: "Press \(label), say a sentence, then press it again.")
    }
}

// MARK: - Model

/// Drives the setup window. Main-actor confined; it observes only the
/// published values it needs, so the window does not redraw at audio-level rate.
@MainActor
final class SetupWizardModel: ObservableObject {
    @Published private(set) var step: SetupWizardStep
    @Published private(set) var travel: SetupTravel = .forward
    @Published private(set) var microphoneGranted: Bool
    @Published private(set) var accessibilityGranted: Bool
    @Published private(set) var modelChip: SetupModelChip
    @Published private(set) var shortcut: SetupShortcutDisplay
    @Published private(set) var isDictating = false
    @Published private(set) var trialSucceeded = false
    @Published var trialText = "" {
        didSet { evaluateTrial() }
    }

    private let dictation: DictationViewModel
    private let modelManager: ModelManagerService
    private let homeViewModel: HomeViewModel
    private let announcer: AccessibilityAnnouncementService
    private let defaults: UserDefaults
    private var cancellables = Set<AnyCancellable>()
    private var permissionPollTask: Task<Void, Never>?
    private var modelPreparationTask: Task<Void, Never>?
    private var trialSuccessTask: Task<Void, Never>?
    private var modelPreparationFailed = false
    private var transcriptsSinceTrialStarted = 0
    private var isStarted = false

    private static let permissionPollInterval: Duration = .seconds(1)
    /// Lets the inserted text land before the title changes.
    private static let trialSuccessDelay: Duration = .milliseconds(600)

    init(
        dictation: DictationViewModel = ServiceContainer.shared.dictationViewModel,
        modelManager: ModelManagerService = ServiceContainer.shared.modelManagerService,
        homeViewModel: HomeViewModel = ServiceContainer.shared.homeViewModel,
        announcer: AccessibilityAnnouncementService = ServiceContainer.shared.accessibilityAnnouncementService,
        defaults: UserDefaults = .standard
    ) {
        self.dictation = dictation
        self.modelManager = modelManager
        self.homeViewModel = homeViewModel
        self.announcer = announcer
        self.defaults = defaults
        step = SetupWizardStep.restored(fromSavedIndex: defaults.integer(forKey: UserDefaultsKeys.setupWizardCurrentStep))
        microphoneGranted = !dictation.needsMicPermission
        accessibilityGranted = !dictation.needsAccessibilityPermission
        modelChip = SetupModelChip(phase: .starting, modelID: nil)
        shortcut = SetupShortcutDisplay(label: SetupShortcutDisplay.fnLabel, isFn: true, isHeld: true, isPending: true, isConfigured: true)
        refreshModelChip()
        refreshShortcut()
    }

    var primaryAction: SetupPrimaryAction {
        SetupPrimaryAction.resolve(step: step, microphoneGranted: microphoneGranted, accessibilityGranted: accessibilityGranted)
    }

    var accessibilityRowIsPrimary: Bool {
        step == .access && SetupPrimaryAction.accessibilityRowIsPrimary(
            microphoneGranted: microphoneGranted,
            accessibilityGranted: accessibilityGranted
        )
    }

    /// The globe notice treats a pending fn as saved: it will be once you continue.
    var assumesFnShortcut: Bool { shortcut.isFn && shortcut.isPending }

    // MARK: Lifecycle

    func start() {
        guard !isStarted else { return }
        isStarted = true
        observe()
        refreshPermissions()
        prepareModelIfNeeded()
        updatePermissionPolling()
        announceStep()
    }

    func stop() {
        isStarted = false
        cancellables.removeAll()
        permissionPollTask?.cancel()
        permissionPollTask = nil
        trialSuccessTask?.cancel()
        trialSuccessTask = nil
        // The model download keeps running: it belongs to the engine, and
        // dictation needs the model whether or not setup stays open.
    }

    func restartFromBeginning() {
        trialSuccessTask?.cancel()
        trialSuccessTask = nil
        trialSucceeded = false
        trialText = ""
        transcriptsSinceTrialStarted = 0
        modelPreparationFailed = false
        move(to: .welcome, travel: .backward)
        prepareModelIfNeeded()
    }

    private func observe() {
        modelManager.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshModelChip() }
            }
            .store(in: &cancellables)

        dictation.$state
            .map { $0 != .idle }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] active in
                MainActor.assumeIsolated { self?.isDictating = active }
            }
            .store(in: &cancellables)

        dictation.$lastTranscribedText
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.noteTranscript() }
            }
            .store(in: &cancellables)

        dictation.$hotkeyLabelsVersion
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshShortcut() }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshPermissions() }
            }
            .store(in: &cancellables)
    }

    // MARK: Navigation

    func performPrimaryAction() -> SetupPrimaryAction {
        let action = primaryAction
        switch action {
        case .begin, .later, .next:
            advance()
        case .allowMicrophone:
            requestMicrophone()
        case .finish:
            break // The view finishes, because it owns dismissal.
        }
        return action
    }

    func advance() {
        guard let next = step.next else { return }
        if step == .shortcut { applyRecommendedHotkeyIfNeeded() }
        move(to: next, travel: .forward)
    }

    func goBack() {
        guard let previous = step.previous else { return }
        move(to: previous, travel: .backward)
    }

    /// Finishes or skips setup. fn becomes the shortcut if none exists, so
    /// dictation works either way.
    func complete() {
        applyRecommendedHotkeyIfNeeded()
        homeViewModel.completeSetupWizard()
        announcer.announce(String(localized: "Setup complete"))
    }

    private func move(to newStep: SetupWizardStep, travel newTravel: SetupTravel) {
        guard newStep != step else { return }
        travel = newTravel
        withLeiseAnimation(LeiseMotion.ui) {
            step = newStep
        }
        defaults.set(newStep.rawValue, forKey: UserDefaultsKeys.setupWizardCurrentStep)
        if newStep == .tryIt {
            transcriptsSinceTrialStarted = 0
        }
        refreshPermissions()
        updatePermissionPolling()
        announceStep()
    }

    private func announceStep() {
        let total = SetupWizardStep.allCases.count
        announcer.announce(String(localized: "\(step.title). Step \(step.number) of \(total). \(stepAnnouncementDetail)"))
    }

    private var stepAnnouncementDetail: String {
        switch step {
        case .welcome: String(localized: "Speak, and the text is there. In any app, without an account, and everything stays on your Mac.")
        case .access: String(localized: "Leise only listens while you dictate or record.")
        case .shortcut: String(localized: "Hold: Leise listens until you let go. Tap: once starts, again stops.")
        case .tryIt: shortcut.tryItInstruction
        }
    }

    // MARK: Permissions

    func requestMicrophone() {
        dictation.requestMicPermission()
    }

    func requestAccessibility() {
        dictation.requestAccessibilityPermission()
    }

    private func updatePermissionPolling() {
        permissionPollTask?.cancel()
        permissionPollTask = nil
        guard isStarted, step == .access else { return }
        permissionPollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.permissionPollInterval)
                guard !Task.isCancelled else { return }
                self?.refreshPermissions()
            }
        }
    }

    private func refreshPermissions() {
        let microphone = !dictation.needsMicPermission
        let accessibility = !dictation.needsAccessibilityPermission
        if microphone != microphoneGranted {
            withLeiseAnimation(LeiseMotion.moment) { microphoneGranted = microphone }
            if microphone { announcer.announce(String(localized: "Microphone allowed")) }
        }
        if accessibility != accessibilityGranted {
            withLeiseAnimation(LeiseMotion.moment) { accessibilityGranted = accessibility }
            if accessibility { announcer.announce(String(localized: "Accessibility allowed")) }
        }
    }

    // MARK: Shortcut

    func recordShortcut(_ hotkey: UnifiedHotkey) {
        if let conflict = dictation.isHotkeyAssigned(hotkey, excluding: .hybrid) {
            dictation.clearHotkey(for: conflict)
        }
        dictation.setHotkey(hotkey, for: .hybrid)
        refreshShortcut()
    }

    func clearShortcut() {
        dictation.clearHotkey(for: .hybrid)
        refreshShortcut()
    }

    var hybridShortcutLabel: String { dictation.hybridHotkeyLabel }

    private var recommendedHotkeyResolution: SetupWizardDefaultHotkey.Resolution {
        SetupWizardDefaultHotkey.resolve(
            existingTriggerHotkeys: currentTriggerHotkeys,
            conflictingSlot: dictation.isHotkeyAssigned(SetupWizardDefaultHotkey.recommendedHybridHotkey, excluding: .hybrid)
        )
    }

    private var currentTriggerHotkeys: [HotkeySlotType: [UnifiedHotkey]] {
        SetupWizardDefaultHotkey.triggerSlots.reduce(into: [:]) { result, slot in
            result[slot] = dictation.hotkeys(for: slot)
        }
    }

    private func applyRecommendedHotkeyIfNeeded() {
        guard recommendedHotkeyResolution.shouldApply else { return }
        dictation.setHotkey(SetupWizardDefaultHotkey.recommendedHybridHotkey, for: .hybrid)
        refreshShortcut()
    }

    private func refreshShortcut() {
        let resolved = SetupShortcutDisplay.resolve(
            hotkeys: currentTriggerHotkeys,
            recommendedApplies: recommendedHotkeyResolution.shouldApply
        )
        if resolved != shortcut { shortcut = resolved }
    }

    // MARK: Model

    private var engine: (any TranscriptionEngine)? {
        modelManager.engine(for: SetupWizardParakeetRecommendation.providerId)
    }

    private var isParakeetSupported: Bool {
        SetupWizardRecommendationAvailability.resolve(
            manifestId: SetupWizardParakeetRecommendation.manifestId,
            isInstalled: engine != nil,
            isReady: engine?.isReady ?? false,
            hasBundledModels: engine?.usesBundledModels ?? false
        ) != .unavailable(.appleSiliconOnly)
    }

    func retryModel() {
        modelPreparationFailed = false
        prepareModelIfNeeded()
        refreshModelChip()
    }

    /// Starts the download in the background on the first step. Choosing
    /// v3 for non-English languages keeps German from turning into English
    /// gibberish, which is what plain v2 did as the default.
    private func prepareModelIfNeeded() {
        guard modelPreparationTask == nil, isParakeetSupported, let engine else {
            refreshModelChip()
            return
        }
        let target = SetupModelChoice.targetModelID(
            currentModelID: engine.selectedModelID,
            recommendedModelID: ParakeetDefaultModel.modelID(forPreferredLanguages: Locale.preferredLanguages)
        )
        modelManager.selectProvider(engine.id)
        if engine.isReady, engine.selectedModelID == target {
            refreshModelChip()
            return
        }
        if case .preparing = engine.preparationStatus, engine.selectedModelID == target {
            refreshModelChip()
            return
        }

        let allowsDownloads = !engine.usesBundledModels
        modelPreparationTask = Task { [weak self] in
            do {
                try await engine.prepareModel(id: target, allowDownloads: allowsDownloads)
            } catch {
                self?.modelPreparationFailed = true
            }
            self?.modelPreparationTask = nil
            self?.refreshModelChip()
        }
        refreshModelChip()
    }

    private func refreshModelChip() {
        let engine = engine
        let resolved = SetupModelChip.resolve(
            isSupported: isParakeetSupported,
            engineReady: engine?.isReady ?? false,
            selectedModelID: engine?.selectedModelID,
            status: engine?.preparationStatus,
            activity: (engine as? any ParakeetModelActivityReporting)?.modelActivity,
            didFail: modelPreparationFailed
        )
        guard resolved != modelChip else { return }
        let becameReady = resolved.isReady && !modelChip.isReady
        withLeiseAnimation(LeiseMotion.ui) {
            modelChip = resolved
        }
        if becameReady {
            announcer.announce(resolved.text)
        }
    }

    // MARK: Try it

    private func noteTranscript() {
        guard step == .tryIt else { return }
        transcriptsSinceTrialStarted += 1
        evaluateTrial()
    }

    /// Success needs both a finished dictation and its text in the field, so
    /// typing alone does not count and a paste that missed the field does not either.
    private func evaluateTrial() {
        guard step == .tryIt,
              !trialSucceeded,
              trialSuccessTask == nil,
              transcriptsSinceTrialStarted > 0,
              !trialText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        trialSuccessTask = Task { [weak self] in
            try? await Task.sleep(for: Self.trialSuccessDelay)
            guard !Task.isCancelled, let self else { return }
            self.trialSuccessTask = nil
            withLeiseAnimation(LeiseMotion.moment) {
                self.trialSucceeded = true
            }
            self.announcer.announce(String(localized: "Set up and ready"))
        }
    }
}

// MARK: - View

struct SetupWizardView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var model = SetupWizardModel()

    static let windowSize = CGSize(width: 720, height: 540)
    /// The titlebar band when SwiftUI reports no safe area for it.
    private static let fallbackTitlebarHeight: CGFloat = 28
    /// How far a step travels while it fades in, like the preview's 14 px.
    private static let stepTravelDistance: CGFloat = 14

    var body: some View {
        GeometryReader { proxy in
            let titlebarHeight = max(proxy.safeAreaInsets.top, Self.fallbackTitlebarHeight)
            VStack(spacing: 0) {
                titlebar
                    .frame(height: titlebarHeight)
                stage
                Divider()
                footer
            }
            .ignoresSafeArea(.container, edges: .top)
        }
        .frame(width: Self.windowSize.width, height: Self.windowSize.height)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { model.start() }
        .onDisappear { model.stop() }
        .onReceive(NotificationCenter.default.publisher(for: .resetSetupWizardWindow)) { _ in
            model.restartFromBeginning()
        }
    }

    // MARK: Titlebar

    private var titlebar: some View {
        ZStack {
            SetupStepDots(current: model.step)

            HStack {
                Spacer()
                Button(String(localized: "Skip Setup")) {
                    finish()
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .keyboardShortcut(model.isDictating ? nil : .cancelAction)
                .help(String(localized: "Finish setup later. fn becomes the dictation shortcut if none is set."))
            }
            .padding(.horizontal, LeiseSpacing.l)
        }
    }

    // MARK: Stage

    private var stage: some View {
        GeometryReader { proxy in
            ScrollView {
                ZStack {
                    stepView
                        .id(model.step)
                        .transition(stepTransition)
                }
                .padding(.horizontal, LeiseSpacing.xxxl)
                .padding(.vertical, LeiseSpacing.xxl)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.automatic)
        }
    }

    @ViewBuilder
    private var stepView: some View {
        switch model.step {
        case .welcome:
            SetupWelcomeStep()
        case .access:
            SetupAccessStep(
                microphoneGranted: model.microphoneGranted,
                accessibilityGranted: model.accessibilityGranted,
                accessibilityIsPrimary: model.accessibilityRowIsPrimary,
                requestMicrophone: model.requestMicrophone,
                requestAccessibility: model.requestAccessibility
            )
        case .shortcut:
            SetupShortcutStep(
                shortcut: model.shortcut,
                assumesFnShortcut: model.assumesFnShortcut,
                recorderLabel: model.hybridShortcutLabel,
                onRecord: model.recordShortcut,
                onClear: model.clearShortcut
            )
        case .tryIt:
            SetupTryItStep(
                text: $model.trialText,
                isModelReady: model.modelChip.isReady,
                succeeded: model.trialSucceeded,
                instruction: model.shortcut.tryItInstruction
            )
        }
    }

    private var stepTransition: AnyTransition {
        let distance = Self.stepTravelDistance * model.travel.edgeSign
        guard !reduceMotion, distance != 0 else { return .opacity }
        return .asymmetric(
            insertion: .offset(x: distance).combined(with: .opacity),
            removal: .opacity
        )
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: LeiseSpacing.m) {
            SetupModelChipView(chip: model.modelChip, retry: model.retryModel)

            Spacer(minLength: LeiseSpacing.l)

            Button(String(localized: "Back")) {
                model.goBack()
            }
            .keyboardShortcut(.leftArrow, modifiers: [.command])
            .opacity(model.step == .welcome ? 0 : 1)
            .disabled(model.step == .welcome)
            .accessibilityHidden(model.step == .welcome)

            primaryButton
        }
        .controlSize(.large)
        .padding(.horizontal, LeiseSpacing.xl)
        .padding(.vertical, LeiseSpacing.m)
    }

    @ViewBuilder
    private var primaryButton: some View {
        let action = model.primaryAction
        let button = Button(action.title) {
            if model.performPrimaryAction() == .finish {
                finish()
            }
        }
        .keyboardShortcut(primaryShortcut(for: action))
        .accessibilityHint(primaryHint(for: action))

        if action.isProminent {
            button
                .buttonStyle(.borderedProminent)
                .tint(LeiseColor.tintFill)
        } else {
            button
                .buttonStyle(.bordered)
        }
    }

    private func primaryShortcut(for action: SetupPrimaryAction) -> KeyboardShortcut? {
        switch action {
        case .finish:
            KeyboardShortcut(.return, modifiers: [.command])
        case .later:
            // "Freigeben …" in the row owns Return while it is the primary action.
            nil
        case .begin, .allowMicrophone, .next:
            .defaultAction
        }
    }

    private func primaryHint(for action: SetupPrimaryAction) -> String {
        action == .finish
            ? String(localized: "Press Command Return to complete setup.")
            : String(localized: "Press Return to continue.")
    }

    private func finish() {
        model.complete()
        dismiss()
        DispatchQueue.main.async {
            LeiseWindowNavigator.openOverview()
        }
    }
}

// MARK: - Shared setup decisions (kept for the wizard's existing tests)

enum SetupWizardDefaultHotkey {
    enum BlockedReason: Equatable {
        case existingTriggerHotkey
        case conflictingSlot(HotkeySlotType)
    }

    struct Resolution: Equatable {
        let shouldApply: Bool
        let blockedReason: BlockedReason?
    }

    static let triggerSlots: [HotkeySlotType] = [.hybrid, .pushToTalk, .toggle]
    static let recommendedHybridHotkey = UnifiedHotkey(keyCode: 0, modifierFlags: 0, isFn: true)

    static func resolve(
        existingTriggerHotkeys: [HotkeySlotType: [UnifiedHotkey]],
        conflictingSlot: HotkeySlotType?
    ) -> Resolution {
        if triggerSlots.contains(where: { !(existingTriggerHotkeys[$0] ?? []).isEmpty }) {
            return Resolution(shouldApply: false, blockedReason: .existingTriggerHotkey)
        }

        if let conflictingSlot {
            return Resolution(shouldApply: false, blockedReason: .conflictingSlot(conflictingSlot))
        }

        return Resolution(shouldApply: true, blockedReason: nil)
    }
}

enum SetupWizardEngineSelection {
    static func preferredProviderId(
        selectedProviderId: String?,
        selectedEngineReady: Bool,
        parakeetReady: Bool
    ) -> String? {
        if selectedEngineReady {
            return selectedProviderId
        }

        if parakeetReady {
            return SetupWizardParakeetRecommendation.providerId
        }

        return nil
    }
}

enum SetupWizardHotkeyRecorderVisibility {
    static func shouldShow(
        mode: HotkeySlotType,
        selectedMode: HotkeySlotType,
        hasRecordedHotkey: Bool
    ) -> Bool {
        mode == selectedMode && !hasRecordedHotkey
    }
}

// MARK: - Recommendation Availability (user-facing copy for LeiseCore resolvers)

extension SetupWizardRecommendationUnavailableReason {
    var title: String {
        switch self {
        case .appleSiliconOnly:
            String(localized: "Apple Silicon only")
        case .builtInUnavailable:
            String(localized: "Unavailable")
        }
    }

    var message: String {
        switch self {
        case .appleSiliconOnly:
            String(localized: "Parakeet requires a Mac with Apple Silicon.")
        case .builtInUnavailable:
            String(localized: "The built-in engine could not be loaded. Restart Leise and try again.")
        }
    }
}
