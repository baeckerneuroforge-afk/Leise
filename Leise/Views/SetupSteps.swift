import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI

// The four setup steps, their shared parts, and the 🌐 key notice that the
// Diktat page reuses. Steps take plain values and closures; SetupWizardModel
// (SetupWizardView.swift) owns the state.

/// Layout values shared by the setup steps.
enum SetupLayout {
    /// Text column under the step titles: about 55 characters of 15 pt text.
    static let textWidth: CGFloat = 440
    /// Groups and fields: rows, the test field, the 🌐 key notice.
    static let contentWidth: CGFloat = 460
    /// Square tiles for the row symbols.
    static let tileSize: CGFloat = 28
    /// The Petrol wash behind tinted symbols, as in DESIGN.md's plain buttons.
    static let tintWashOpacity: Double = 0.12
}

// MARK: - Step dots

/// Four dots in the titlebar; the current one widens.
struct SetupStepDots: View {
    let current: SetupWizardStep

    private static let dotSize: CGFloat = 8
    private static let currentWidth: CGFloat = 24

    var body: some View {
        HStack(spacing: LeiseSpacing.s) {
            ForEach(SetupWizardStep.allCases) { step in
                Capsule(style: .continuous)
                    .fill(step.rawValue <= current.rawValue ? LeiseColor.tint : Color(nsColor: .tertiaryLabelColor))
                    .frame(width: step == current ? Self.currentWidth : Self.dotSize, height: Self.dotSize)
            }
        }
        .leiseAnimation(LeiseMotion.shape, value: current)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Setup progress"))
        .accessibilityValue(String(localized: "Step \(current.number) of \(SetupWizardStep.allCases.count)"))
    }
}

// MARK: - Shared parts

/// The headline and the sentence under it.
struct SetupStepHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: LeiseSpacing.s) {
            Text(title)
                .font(.largeTitle.bold())
                .fontDesign(.rounded)
                .multilineTextAlignment(.center)
                .contentTransition(.opacity)
                .accessibilityAddTraits(.isHeader)

            Text(subtitle)
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: SetupLayout.textWidth)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)
        }
    }
}

/// The Leise mark drawn bar by bar, so the bars can rise one after another
/// on the welcome step and ripple once when setup succeeds.
struct SetupRisingMark: View {
    var height: CGFloat
    /// Bars rise from almost flat when the view appears.
    var risesOnAppear: Bool
    /// Turning it on plays one ripple: the bars reach full height in turn.
    var rippleTrigger: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasRisen: Bool
    @State private var isRippling = false

    init(height: CGFloat, risesOnAppear: Bool = true, rippleTrigger: Bool = false) {
        self.height = height
        self.risesOnAppear = risesOnAppear
        self.rippleTrigger = rippleTrigger
        // Start risen when there is no entrance, so nothing animates on
        // appear (and nothing at all under Reduce Motion).
        _hasRisen = State(initialValue: !risesOnAppear || LeiseMotion.systemReduceMotion)
    }

    /// Delay between neighboring bars.
    private static let stagger = 0.06
    /// How long a bar stays up before it settles back.
    private static let rippleHold: Duration = .milliseconds(140)
    /// The flat starting point of the entrance.
    private static let collapsedScale: CGFloat = 0.06

    var body: some View {
        let barWidth = height * LeiseMarkShape.barWidthRatio
        HStack(alignment: .center, spacing: height * LeiseMarkShape.gapRatio) {
            ForEach(Array(LeiseMarkShape.restingHeights.enumerated()), id: \.offset) { index, relativeHeight in
                let barHeight = max(barWidth, height * relativeHeight)
                Capsule(style: .continuous)
                    .fill(LeiseColor.tint)
                    .frame(width: barWidth, height: barHeight)
                    .scaleEffect(y: scale(forBarHeight: barHeight), anchor: .center)
                    .animation(LeiseMotion.moment.delay(Double(index) * Self.stagger), value: hasRisen)
                    .animation(LeiseMotion.moment.delay(Double(index) * Self.stagger), value: isRippling)
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
        .onAppear {
            guard !hasRisen else { return }
            guard !reduceMotion else {
                hasRisen = true
                return
            }
            // Next run loop turn, so the collapsed bars render first.
            DispatchQueue.main.async { hasRisen = true }
        }
        .onChange(of: rippleTrigger) { _, isOn in
            guard isOn, !reduceMotion else { return }
            isRippling = true
            Task { @MainActor in
                try? await Task.sleep(for: Self.rippleHold)
                isRippling = false
            }
        }
    }

    private func scale(forBarHeight barHeight: CGFloat) -> CGFloat {
        guard hasRisen else { return Self.collapsedScale }
        guard isRippling, barHeight > 0 else { return 1 }
        return height / barHeight
    }
}

/// A rounded group like a grouped form section.
private struct SetupGroup<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0, content: content)
            .background(
                RoundedRectangle(cornerRadius: LeiseRadius.group, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: LeiseRadius.group, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
            )
            .frame(maxWidth: SetupLayout.contentWidth)
    }
}

/// A Petrol symbol on a light Petrol tile.
private struct SetupSymbolTile: View {
    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.body.weight(.medium))
            .foregroundStyle(LeiseColor.tint)
            .frame(width: SetupLayout.tileSize, height: SetupLayout.tileSize)
            .background(
                RoundedRectangle(cornerRadius: LeiseRadius.control, style: .continuous)
                    .fill(LeiseColor.tint.opacity(SetupLayout.tintWashOpacity))
            )
            .accessibilityHidden(true)
    }
}

// MARK: - Willkommen

struct SetupWelcomeStep: View {
    private static let markHeight: CGFloat = 88

    var body: some View {
        VStack(spacing: LeiseSpacing.l) {
            SetupRisingMark(height: Self.markHeight)
                .padding(.bottom, LeiseSpacing.s)

            SetupStepHeader(
                title: SetupWizardStep.welcome.title,
                subtitle: String(localized: "Speak, and the text is there. In any app, without an account, and everything stays on your Mac.")
            )
        }
    }
}

// MARK: - Zugriff

struct SetupAccessStep: View {
    let microphoneGranted: Bool
    let accessibilityGranted: Bool
    /// Bedienungshilfen is the one missing step, so its button is the primary action.
    let accessibilityIsPrimary: Bool
    let requestMicrophone: () -> Void
    let requestAccessibility: () -> Void

    var body: some View {
        VStack(spacing: LeiseSpacing.l) {
            SetupStepHeader(
                title: SetupWizardStep.access.title,
                subtitle: String(localized: "Leise only listens while you dictate or record.")
            )

            SetupGroup {
                SetupPermissionRow(
                    systemImage: "mic",
                    title: String(localized: "Microphone"),
                    detail: String(localized: "So Leise can hear you."),
                    isGranted: microphoneGranted,
                    actionTitle: String(localized: "Allow"),
                    isPrimary: false,
                    action: requestMicrophone
                )
                Divider()
                    .padding(.leading, LeiseSpacing.m + SetupLayout.tileSize + LeiseSpacing.m)
                SetupPermissionRow(
                    systemImage: "accessibility",
                    title: String(localized: "Accessibility"),
                    detail: String(localized: "So Leise can insert the text into other apps."),
                    isGranted: accessibilityGranted,
                    actionTitle: String(localized: "Grant Access…"),
                    isPrimary: accessibilityIsPrimary,
                    action: requestAccessibility
                )
            }

            if microphoneGranted && !accessibilityGranted {
                Text(String(localized: "Without Accessibility, the text only lands on the clipboard."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: SetupLayout.textWidth)
                    .transition(.opacity)
            }
        }
    }
}

private struct SetupPermissionRow: View {
    let systemImage: String
    let title: String
    let detail: String
    let isGranted: Bool
    let actionTitle: String
    let isPrimary: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: LeiseSpacing.m) {
            SetupSymbolTile(systemImage: systemImage)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ZStack(alignment: .trailing) {
                if isGranted {
                    Label {
                        Text(String(localized: "Allowed"))
                            .fontWeight(.medium)
                    } icon: {
                        Image(systemName: "checkmark")
                            .fontWeight(.semibold)
                            .foregroundStyle(LeiseColor.ready)
                    }
                    .transition(grantedTransition)
                } else {
                    grantButton
                        .transition(.opacity)
                }
            }
        }
        .padding(.horizontal, LeiseSpacing.m)
        .padding(.vertical, LeiseSpacing.m)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
        .accessibilityValue(isGranted ? String(localized: "Allowed") : String(localized: "Not allowed yet"))
    }

    @ViewBuilder
    private var grantButton: some View {
        if isPrimary {
            Button(actionTitle, action: action)
                .buttonStyle(.borderedProminent)
                .tint(LeiseColor.tintFill)
                .keyboardShortcut(.defaultAction)
        } else {
            Button(actionTitle, action: action)
                .buttonStyle(.bordered)
        }
    }

    private var grantedTransition: AnyTransition {
        reduceMotion ? .opacity : .scale(scale: 0.85).combined(with: .opacity)
    }
}

// MARK: - Tastenkürzel

struct SetupShortcutStep: View {
    let shortcut: SetupShortcutDisplay
    let assumesFnShortcut: Bool
    let recorderLabel: String
    let onRecord: (UnifiedHotkey) -> Void
    let onClear: () -> Void

    @StateObject private var fnKey = FnKeyPressObserver()
    @State private var isShowingRecorder = false

    private static let explanationWidth: CGFloat = 270
    private static let recorderPopoverWidth: CGFloat = 320

    var body: some View {
        VStack(spacing: LeiseSpacing.l) {
            SetupStepHeader(
                title: SetupWizardStep.shortcut.title,
                subtitle: String(localized: "Both work with the same key. Press \(shortcut.label), or click the key here.")
            )

            HStack(spacing: LeiseSpacing.xxl) {
                SetupPressableKey(shortcut: shortcut, isPhysicallyPressed: shortcut.isFn && fnKey.isPressed)

                VStack(alignment: .leading, spacing: LeiseSpacing.m) {
                    explanation(
                        title: String(localized: "Hold"),
                        detail: String(localized: "Leise listens until you let go.")
                    )
                    explanation(
                        title: String(localized: "Tap"),
                        detail: String(localized: "Once starts, again stops.")
                    )
                }
                .frame(maxWidth: Self.explanationWidth, alignment: .leading)
            }
            .padding(.vertical, LeiseSpacing.xs)

            Button(String(localized: "Other Shortcut…")) {
                isShowingRecorder = true
            }
            .buttonStyle(.borderless)
            .foregroundStyle(LeiseColor.tint)
            .popover(isPresented: $isShowingRecorder, arrowEdge: .bottom) {
                recorderPopover
            }

            GlobeKeyNotice(assumingFnShortcut: assumesFnShortcut)
        }
        .onAppear { fnKey.start() }
        .onDisappear { fnKey.stop() }
    }

    private func explanation(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.headline)
            Text(detail)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var recorderPopover: some View {
        VStack(alignment: .leading, spacing: LeiseSpacing.m) {
            Text(String(localized: "Dictation shortcut"))
                .font(.headline)
            Text(String(localized: "Press the keys you want to hold or tap."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HotkeyRecorderView(
                label: recorderLabel,
                title: String(localized: "Shortcut"),
                onRecord: { hotkey in
                    onRecord(hotkey)
                    isShowingRecorder = false
                },
                onClear: onClear
            )
        }
        .padding(LeiseSpacing.l)
        .frame(width: Self.recorderPopoverWidth)
    }
}

/// The large fn key: press it with the pointer, or press the real fn key.
/// While it is down, the mark in its corner moves in Microphone Orange.
private struct SetupPressableKey: View {
    let shortcut: SetupShortcutDisplay
    let isPhysicallyPressed: Bool

    @State private var isPointerPressed = false
    @State private var demoTask: Task<Void, Never>?

    private static let markHeight: CGFloat = 16
    /// KeyCap.large moves down by 0.8 of its 5 pt skirt while held.
    private static let pressTravel: CGFloat = 4
    /// A steady demo level: no microphone is involved here.
    private static let demoLevel = 0.75
    private static let demoPressDuration: Duration = .milliseconds(700)

    private var isPressed: Bool { isPointerPressed || isPhysicallyPressed }

    var body: some View {
        KeyCap(
            label: shortcut.label,
            systemImage: shortcut.isFn ? "globe" : nil,
            size: .large,
            isPressed: isPressed
        )
        .overlay(alignment: .topTrailing) {
            LeiseMark(mode: isPressed ? .live(level: Self.demoLevel) : .resting, color: LeiseColor.live)
                .frame(height: Self.markHeight)
                .padding(LeiseSpacing.m)
                .offset(y: isPressed ? Self.pressTravel : 0)
                .opacity(isPressed ? 1 : 0)
                .leiseAnimation(LeiseMotion.micro, value: isPressed)
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isPointerPressed { isPointerPressed = true }
                }
                .onEnded { _ in
                    isPointerPressed = false
                }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "\(shortcut.label) key, to try it out"))
        .accessibilityValue(isPressed ? String(localized: "Pressed") : "")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            demoPress()
        }
        .onDisappear { demoTask?.cancel() }
    }

    private func demoPress() {
        demoTask?.cancel()
        isPointerPressed = true
        demoTask = Task { @MainActor in
            try? await Task.sleep(for: Self.demoPressDuration)
            isPointerPressed = false
        }
    }
}

/// Follows the physical fn key while the setup window is key. Read-only: it
/// watches this app's own flagsChanged events and never consumes them.
@MainActor
final class FnKeyPressObserver: ObservableObject {
    @Published private(set) var isPressed = false
    private var monitor: Any?

    static let functionKeyCode = UInt16(kVK_Function)

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            // Local monitors run on the main thread.
            MainActor.assumeIsolated {
                self?.handle(keyCode: event.keyCode, modifierFlags: event.modifierFlags)
            }
            return event
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        if isPressed { isPressed = false }
    }

    func handle(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags) {
        guard keyCode == Self.functionKeyCode else { return }
        let isDown = modifierFlags.contains(.function)
        if isDown != isPressed { isPressed = isDown }
    }

    isolated deinit {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}

// MARK: - Ausprobieren

struct SetupTryItStep: View {
    @Binding var text: String
    let isModelReady: Bool
    let succeeded: Bool
    let instruction: String

    @FocusState private var isFieldFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let markHeight: CGFloat = 40
    private static let fieldHeight: CGFloat = 96
    /// NSTextView's default line fragment padding, so the placeholder lines
    /// up with typed text.
    private static let editorLinePadding: CGFloat = 5

    var body: some View {
        VStack(spacing: LeiseSpacing.l) {
            SetupRisingMark(height: Self.markHeight, risesOnAppear: false, rippleTrigger: succeeded)

            SetupStepHeader(
                title: succeeded ? String(localized: "That’s it.") : SetupWizardStep.tryIt.title,
                subtitle: succeeded ? String(localized: "Leise now waits in the menu bar.") : instruction
            )

            field

            Label {
                Text(String(localized: "Set up and ready"))
                    .fontWeight(.semibold)
            } icon: {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(LeiseColor.ready)
                    .symbolEffect(.bounce, value: succeeded && !reduceMotion)
            }
            .opacity(succeeded ? 1 : 0)
            .accessibilityHidden(!succeeded)
        }
        .task(id: isModelReady) {
            guard isModelReady else { return }
            // Focus once the field can take text, so dictation lands here.
            await Task.yield()
            isFieldFocused = true
        }
    }

    private var field: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $text)
                .font(.title3)
                .scrollContentBackground(.hidden)
                .focused($isFieldFocused)
                .disabled(!isModelReady)

            if text.isEmpty {
                Text(isModelReady
                    ? String(localized: "Your text appears here.")
                    : String(localized: "The language model is still loading. Just a moment."))
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .padding(.leading, Self.editorLinePadding)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .padding(LeiseSpacing.s)
        .frame(maxWidth: SetupLayout.contentWidth)
        .frame(height: Self.fieldHeight)
        .background(
            RoundedRectangle(cornerRadius: LeiseRadius.group, style: .continuous)
                .fill(isModelReady ? Color(nsColor: .textBackgroundColor) : Color(nsColor: .quaternarySystemFill))
        )
        .overlay(
            RoundedRectangle(cornerRadius: LeiseRadius.group, style: .continuous)
                .strokeBorder(
                    isFieldFocused && isModelReady ? LeiseColor.tint : Color(nsColor: .separatorColor),
                    lineWidth: isFieldFocused && isModelReady ? 2 : 1
                )
        )
        .leiseAnimation(LeiseMotion.ui, value: isModelReady)
        .leiseAnimation(LeiseMotion.micro, value: isFieldFocused)
        .accessibilityLabel(String(localized: "Try dictation text field"))
        .accessibilityHint(isModelReady
            ? String(localized: "Press your dictation shortcut and speak. The text appears here.")
            : String(localized: "The language model is still loading. Just a moment."))
    }
}

// MARK: - Model chip

/// The footer chip: download progress, then "Sprachmodell bereit".
struct SetupModelChipView: View {
    let chip: SetupModelChip
    let retry: () -> Void

    private static let barWidth: CGFloat = 56

    var body: some View {
        Group {
            switch chip.phase {
            case .ready:
                StatusLabel(kind: .ready, text: chip.text)
                    .transition(.opacity)
            case .failed:
                HStack(spacing: LeiseSpacing.s) {
                    StatusLabel(kind: .error, text: chip.text)
                    Button(String(localized: "Retry"), action: retry)
                        .buttonStyle(.link)
                }
                .transition(.opacity)
            case .unsupported:
                StatusLabel(kind: .error, text: chip.text)
                    .transition(.opacity)
            case .starting, .preparing, .downloading:
                HStack(spacing: LeiseSpacing.s) {
                    bar
                    Text(chip.text)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                .transition(.opacity)
            }
        }
        .lineLimit(1)
        .truncationMode(.tail)
        .controlSize(.small)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var bar: some View {
        if let fraction = chip.barFraction {
            ProgressView(value: fraction)
                .progressViewStyle(.linear)
                .frame(width: Self.barWidth)
                .accessibilityHidden(true)
        } else {
            ProgressView()
                .progressViewStyle(.linear)
                .frame(width: Self.barWidth)
                .accessibilityHidden(true)
        }
    }
}

// MARK: - 🌐 key notice

/// What the 🌐 key notice shows.
enum GlobeKeyNoticePresentation: Equatable {
    case hidden
    case conflict(GlobeKeyAction, guidance: GlobeKeyNoticeGuidance)
    /// "Erledigt", shortly, after the conflict went away.
    case done
}

enum GlobeKeyNoticeGuidance: Equatable {
    case none
    /// Keyboard settings are open; say what to change there.
    case openedSettings
    /// "Abstellen" did not stick; System Settings is the way.
    case couldNotChange
}

/// State behind the notice. It reads the setting when created and follows
/// changes through the service, so it never waits for a view to appear: a
/// notice that starts hidden still shows up when a conflict arises.
@MainActor
final class GlobeKeyNoticeModel: ObservableObject {
    @Published private(set) var isConfirmingFix = false
    @Published var guidance: GlobeKeyNoticeGuidance = .none

    let service: GlobeKeyService
    private let announcer: AccessibilityAnnouncementService
    private var lastAction: GlobeKeyAction
    private var confirmationTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    /// How long "Erledigt" stays before the notice hides.
    static let confirmationDuration: Duration = .milliseconds(1400)

    init(
        service: GlobeKeyService? = nil,
        announcer: AccessibilityAnnouncementService = AccessibilityAnnouncementService(),
        observesChanges: Bool = true
    ) {
        let service = service ?? GlobeKeyService()
        self.service = service
        self.announcer = announcer
        lastAction = service.action
        if observesChanges {
            service.startObserving()
        }

        service.objectWillChange
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.objectWillChange.send() }
            }
            .store(in: &cancellables)

        // `$action` publishes the new value before the property changes.
        service.$action
            .sink { [weak self] action in
                MainActor.assumeIsolated { self?.actionWillChange(to: action) }
            }
            .store(in: &cancellables)
    }

    isolated deinit {
        confirmationTask?.cancel()
    }

    func presentation(assumingFnShortcut: Bool) -> GlobeKeyNoticePresentation {
        if let action = service.conflict(assumingFnShortcut: assumingFnShortcut) {
            return .conflict(action, guidance: guidance)
        }
        if isConfirmingFix, service.usesFnForDictation || assumingFnShortcut {
            return .done
        }
        return .hidden
    }

    /// "Abstellen". Only ever called from the button.
    func turnOff() {
        if service.turnOffGlobeKeyAction() == .failed {
            guidance = .couldNotChange
        }
    }

    /// "Systemeinstellungen …".
    func openKeyboardSettings() {
        service.openKeyboardSettings()
        if guidance == .none {
            guidance = .openedSettings
        }
    }

    private func actionWillChange(to action: GlobeKeyAction) {
        defer { lastAction = action }
        guard action != lastAction else { return }
        if lastAction.interferesWithFnShortcut, action == .doNothing {
            // Fixed here or in System Settings: confirm, then step aside.
            confirmFix()
        }
    }

    private func confirmFix() {
        guidance = .none
        isConfirmingFix = true
        announcer.announce(String(localized: "All set"))
        confirmationTask?.cancel()
        confirmationTask = Task { [weak self] in
            try? await Task.sleep(for: Self.confirmationDuration)
            guard !Task.isCancelled else { return }
            self?.isConfirmingFix = false
        }
    }
}

/// Shown only while the 🌐 key's own action fires alongside an fn dictation
/// shortcut: "Abstellen" turns it off, "Systemeinstellungen …" opens
/// Keyboard settings with a one-line instruction. On success it says
/// "Erledigt" and then hides.
///
/// Embed it as `GlobeKeyNotice()`; setup passes `assumingFnShortcut` while
/// fn is shown but not yet saved.
struct GlobeKeyNotice: View {
    var assumingFnShortcut: Bool

    @StateObject private var model = GlobeKeyNoticeModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(assumingFnShortcut: Bool = false) {
        self.assumingFnShortcut = assumingFnShortcut
    }

    var body: some View {
        let presentation = model.presentation(assumingFnShortcut: assumingFnShortcut)
        Group {
            switch presentation {
            case .hidden:
                EmptyView()
            case let .conflict(action, guidance):
                conflictBanner(action: action, guidance: guidance)
                    .transition(bannerTransition)
            case .done:
                doneBanner
                    .transition(bannerTransition)
            }
        }
        .animation(LeiseMotion.adaptive(LeiseMotion.ui, reduceMotion: reduceMotion), value: presentation)
    }

    private var bannerTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98, anchor: .top))
    }

    private func conflictBanner(action: GlobeKeyAction, guidance: GlobeKeyNoticeGuidance) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: LeiseSpacing.m) {
            Image(systemName: "keyboard")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: LeiseSpacing.s) {
                Text(guidance == .couldNotChange
                    ? String(localized: "Leise couldn’t change this setting.")
                    : action.conflictMessage)
                    .fixedSize(horizontal: false, vertical: true)

                if guidance != .none {
                    Text(GlobeKeyAction.settingsInstruction)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: LeiseSpacing.s) {
                    if guidance != .couldNotChange {
                        Button(String(localized: "Turn Off")) { model.turnOff() }
                            .buttonStyle(.borderedProminent)
                            .tint(LeiseColor.tintFill)
                            .help(String(localized: "Sets “Press 🌐 key to” to “Do Nothing”, so fn only starts Leise."))
                    }
                    Button(String(localized: "System Settings…")) { model.openKeyboardSettings() }
                        .buttonStyle(.bordered)
                }
                .controlSize(.small)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(LeiseSpacing.m)
        .frame(maxWidth: SetupLayout.contentWidth)
        .background(
            RoundedRectangle(cornerRadius: LeiseRadius.group, style: .continuous)
                .fill(Color(nsColor: .quaternarySystemFill))
        )
        .accessibilityElement(children: .contain)
    }

    private var doneBanner: some View {
        Label {
            Text(String(localized: "All set"))
                .fontWeight(.medium)
        } icon: {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(LeiseColor.ready)
        }
        .padding(LeiseSpacing.m)
        .frame(maxWidth: SetupLayout.contentWidth)
        .background(
            RoundedRectangle(cornerRadius: LeiseRadius.group, style: .continuous)
                .fill(Color(nsColor: .quaternarySystemFill))
        )
        .accessibilityElement(children: .combine)
    }
}
