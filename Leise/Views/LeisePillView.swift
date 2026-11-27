import AppKit
import Observation
import SwiftUI

// The indicator pill's content and rendering. `LeisePillController`
// (LeisePillPanel.swift) owns the windows and drives the geometry; the views
// here only draw what the model says.

// MARK: - Content

/// What the pill shows.
enum LeisePillPhase: Equatable {
    /// The quiet resting bar ("Immer").
    case idle
    /// Recording requested, microphone not delivering audio yet.
    case preparing
    /// Dictation is listening: the bars follow the voice in Microphone Orange.
    case listening
    /// The audio recorder is running.
    case recording(elapsed: String)
    /// Transcribing: a wave runs through the bars.
    case processing
    /// A result or feedback message: done, error, cancel or information.
    case message(LeisePillMessage)
}

struct LeisePillMessage: Hashable {
    enum Kind: Equatable {
        /// The bars fold into a green check.
        case inserted
        /// A red cross and a short head shake.
        case error
        /// A neutral white cross.
        case cancelled
        /// Neutral information with its own symbol.
        case info
    }

    var kind: Kind
    var text: String
    /// SF Symbol for `.info` messages.
    var symbolName: String?
    /// The app the text went into, for its icon.
    var appBundleIdentifier: String?
    var undoTitle: String?
}

/// Everything the pill needs from dictation and the recorder.
struct LeisePillInputs: Equatable {
    var dictationState: DictationViewModel.State
    var recorderState: AudioRecorderViewModel.RecorderState = .idle
    var isRecordingInputReady = true
    var recorderElapsed: TimeInterval = 0
    var feedbackMessage: String?
    var feedbackIcon: String?
    var feedbackKind: IndicatorFeedbackKind = .info
    var feedbackUndoTitle: String?
    var insertionTarget: IndicatorInsertionTarget?
    var cancelWarningMessage: String?
}

struct LeisePillContent: Equatable {
    var phase: LeisePillPhase
    /// "Noch einmal Esc zum Abbrechen" after the first Esc.
    var escHint: String?

    static let idle = LeisePillContent(phase: .idle, escHint: nil)

    static func resolve(_ inputs: LeisePillInputs) -> LeisePillContent {
        let presentation = IndicatorPresentationState.resolve(
            dictationState: inputs.dictationState,
            recorderState: inputs.recorderState
        )
        let phase: LeisePillPhase
        switch presentation.state {
        case .idle:
            phase = .idle
        case .recording:
            if presentation.source == .recorder {
                phase = .recording(elapsed: LeisePillFormat.elapsed(inputs.recorderElapsed))
            } else {
                phase = inputs.isRecordingInputReady ? .listening : .preparing
            }
        case .processing:
            phase = .processing
        case .inserting:
            phase = .message(insertingMessage(inputs))
        case let .error(message):
            phase = .message(LeisePillMessage(kind: .error, text: message))
        }

        let hint: String?
        switch phase {
        case .preparing, .listening, .processing:
            hint = inputs.cancelWarningMessage
        default:
            hint = nil
        }
        return LeisePillContent(phase: phase, escHint: hint)
    }

    private static func insertingMessage(_ inputs: LeisePillInputs) -> LeisePillMessage {
        if let text = inputs.feedbackMessage {
            let kind: LeisePillMessage.Kind
            switch inputs.feedbackKind {
            case .success:
                kind = .inserted
            case .info:
                kind = .info
            case .cancelled:
                kind = .cancelled
            case .error:
                kind = .error
            }
            return LeisePillMessage(
                kind: kind,
                text: text,
                symbolName: kind == .info ? inputs.feedbackIcon : nil,
                undoTitle: inputs.feedbackUndoTitle
            )
        }

        let appName = inputs.insertionTarget?.appName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let appName, !appName.isEmpty {
            return LeisePillMessage(
                kind: .inserted,
                text: String(localized: "Inserted in \(appName)"),
                appBundleIdentifier: inputs.insertionTarget?.bundleIdentifier
            )
        }
        return LeisePillMessage(kind: .inserted, text: String(localized: "Text inserted"))
    }
}

enum LeisePillFormat {
    /// "0:42", "12:04" or "1:02:03" for the recorder's elapsed time.
    static func elapsed(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}

/// The idle pill's hover hint for the configured dictation shortcut.
enum LeisePillHotkeyHint {
    static func text(hybrid: [UnifiedHotkey], pushToTalk: [UnifiedHotkey], toggle: [UnifiedHotkey]) -> String {
        if let hotkey = hybrid.first ?? pushToTalk.first {
            return String(localized: "Hold \(label(for: hotkey)) to talk")
        }
        if let hotkey = toggle.first {
            return String(localized: "Press \(label(for: hotkey)) to talk")
        }
        return String(localized: "No dictation shortcut set")
    }

    /// The fn key is spelled the way it is printed on the key.
    static func label(for hotkey: UnifiedHotkey) -> String {
        if hotkey.isFn, !hotkey.isDoubleTap {
            return "fn"
        }
        return HotkeyService.displayName(for: hotkey)
    }
}

// MARK: - Layout

/// Size and inner layout of the pill for a piece of content.
struct LeisePillLayout: Equatable {
    var size: CGSize
    /// Width of the leading column that holds the bars or the result glyph;
    /// `nil` centers the bars in the whole pill.
    var glyphColumnWidth: CGFloat?
    /// Width reserved for the text after the glyph column.
    var trailingWidth: CGFloat
    /// Height of the five bars.
    var barHeight: CGFloat
}

enum LeisePillMetrics {
    /// The resting bar under "Immer", like Wispr Flow's.
    static let idleSize = CGSize(width: 44, height: 14)
    static let activeHeight: CGFloat = 30
    static let listeningWidth: CGFloat = 64
    static let hoverMinimumWidth: CGFloat = 150
    /// Wide enough for the longest German message ("Text konnte nicht
    /// eingefügt werden – in der Zwischenablage behalten", about 470 pt with
    /// glyph and padding), so every cause reads in full. Longer engine
    /// errors truncate at the tail.
    static let maxWidth: CGFloat = 480
    static let glyphColumnWidth: CGFloat = 40
    static let hoverGlyphColumnWidth: CGFloat = 36
    static let trailingPadding: CGFloat = LeiseSpacing.l
    static let appIconSize: CGFloat = 18
    static let undoHeight: CGFloat = 20
    static let undoHorizontalPadding: CGFloat = LeiseSpacing.s
    static let idleBarHeight: CGFloat = 7
    static let hoverBarHeight: CGFloat = 11
    static let activeBarHeight: CGFloat = 15
    /// The pill rises from this far below its spot.
    static let riseDistance: CGFloat = 10
    static let hiddenScale: CGFloat = 0.94

    static func layout(
        for content: LeisePillContent,
        hoverHint: String?,
        maxWidth: CGFloat = maxWidth,
        measure: (String, LeisePillTypography.Style) -> CGFloat = LeisePillTypography.width
    ) -> LeisePillLayout {
        func withText(_ textWidth: CGFloat, column: CGFloat, minimum: CGFloat, barHeight: CGFloat) -> LeisePillLayout {
            let natural = column + textWidth + trailingPadding
            let width = min(max(natural, minimum), maxWidth)
            return LeisePillLayout(
                size: CGSize(width: width, height: activeHeight),
                glyphColumnWidth: column,
                trailingWidth: max(0, width - column - trailingPadding),
                barHeight: barHeight
            )
        }

        if let hint = content.escHint {
            return withText(
                measure(hint, .message),
                column: glyphColumnWidth,
                minimum: listeningWidth,
                barHeight: activeBarHeight
            )
        }

        switch content.phase {
        case .idle:
            if let hoverHint {
                return withText(
                    measure(hoverHint, .message),
                    column: hoverGlyphColumnWidth,
                    minimum: hoverMinimumWidth,
                    barHeight: hoverBarHeight
                )
            }
            return LeisePillLayout(size: idleSize, glyphColumnWidth: nil, trailingWidth: 0, barHeight: idleBarHeight)
        case .preparing, .listening, .processing:
            return LeisePillLayout(
                size: CGSize(width: listeningWidth, height: activeHeight),
                glyphColumnWidth: nil,
                trailingWidth: 0,
                barHeight: activeBarHeight
            )
        case let .recording(elapsed):
            return withText(
                measure(elapsed, .time),
                column: glyphColumnWidth,
                minimum: listeningWidth,
                barHeight: activeBarHeight
            )
        case let .message(message):
            var textWidth = measure(message.text, .message)
            if message.appBundleIdentifier != nil {
                textWidth += appIconSize + LeiseSpacing.s
            }
            if let undo = message.undoTitle {
                textWidth += LeiseSpacing.m + measure(undo, .button) + 2 * undoHorizontalPadding
            }
            return withText(textWidth, column: glyphColumnWidth, minimum: listeningWidth, barHeight: activeBarHeight)
        }
    }
}

/// The pill's type: SF Pro 12.5 pt, SF Pro Rounded with tabular digits for times.
enum LeisePillTypography {
    enum Style {
        case message
        case time
        case button
    }

    static let size: CGFloat = 12.5
    static let buttonSize: CGFloat = 11

    static func font(_ style: Style) -> Font {
        switch style {
        case .message:
            .system(size: size, weight: .medium)
        case .time:
            .system(size: size, weight: .semibold, design: .rounded).monospacedDigit()
        case .button:
            .system(size: buttonSize, weight: .semibold)
        }
    }

    static func nsFont(_ style: Style) -> NSFont {
        switch style {
        case .message:
            return .systemFont(ofSize: size, weight: .medium)
        case .time:
            let base = NSFont.monospacedDigitSystemFont(ofSize: size, weight: .semibold)
            guard let rounded = base.fontDescriptor.withDesign(.rounded) else { return base }
            return NSFont(descriptor: rounded, size: size) ?? base
        case .button:
            return .systemFont(ofSize: buttonSize, weight: .semibold)
        }
    }

    /// Rendered width of `text`, rounded up, with a point of slack for
    /// SwiftUI's own text layout.
    static func width(of text: String, style: Style) -> CGFloat {
        let measured = (text as NSString).size(withAttributes: [.font: nsFont(style)]).width
        return (measured + 1).rounded(.up)
    }
}

// MARK: - Model

struct LeisePillAnchorDot: Equatable, Identifiable {
    var anchor: IndicatorAnchor
    var center: CGPoint
    var id: IndicatorAnchor { anchor }
}

/// Live voice level for the bars. Not observed: the bars read it on every
/// animation frame, so a 30 Hz level stream does not re-render the pill.
@MainActor
final class LeisePillLevelMeter {
    var level: Double = 0
    /// A made-up voice for the settings preview.
    var isSynthetic = false

    func value(at time: TimeInterval) -> Double {
        guard isSynthetic else { return level }
        let syllables = 0.5 + 0.5 * sin(time * 7.3)
        let phrase = 0.55 + 0.45 * sin(time * 1.7)
        return min(max(0.15 + 0.75 * syllables * phrase, 0), 1)
    }
}

/// What the pill views draw. Written by `LeisePillController` (or the
/// settings preview), read by SwiftUI.
@MainActor
@Observable
final class LeisePillModel {
    var content = LeisePillContent.idle
    var layout = LeisePillMetrics.layout(for: .idle, hoverHint: nil)
    var appIcon: NSImage?
    var hoverHint: String?
    var isHovering = false
    /// Dictation can't start right now (shortcuts paused, no model).
    var isDimmed = false
    var isPressed = false
    var isDragging = false
    var isUndoPressed = false
    var isUndoHovered = false
    var anchor: IndicatorAnchor = .center
    /// Where a drag released now would land; drives the anchor dots.
    var projectedAnchor: IndicatorAnchor?
    var anchorDots: [LeisePillAnchorDot] = []
    /// Bumped to play the error head shake.
    var shakeCount = 0

    /// The pill's frame in the strip, top-left origin.
    var capsuleFrame = CGRect(origin: .zero, size: LeisePillMetrics.idleSize)
    var presentationOffset: CGFloat = 0
    var presentationScale: CGFloat = 1
    var presentationOpacity: Double = 1

    @ObservationIgnored let level = LeisePillLevelMeter()
    /// The Undo button's frame in the strip, reported by the view so the
    /// pointer window can route clicks to it.
    @ObservationIgnored var undoButtonFrame: CGRect?
    @ObservationIgnored var onAdjustAnchor: ((Int) -> Void)?
    @ObservationIgnored var onUndo: (() -> Void)?
}

// MARK: - Strip

/// Root view of the strip window: the pill plus the anchor dots shown while
/// it is dragged.
struct LeisePillStripView: View {
    let model: LeisePillModel

    nonisolated static let coordinateSpace = "LeisePillStrip"

    var body: some View {
        ZStack(alignment: .topLeading) {
            LeisePillAnchorDots(model: model)

            LeisePillCapsule(model: model)
                .offset(y: model.presentationOffset)
                .scaleEffect(model.presentationScale, anchor: .bottom)
                .opacity(model.presentationOpacity)
                .position(x: model.capsuleFrame.midX, y: model.capsuleFrame.midY)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .coordinateSpace(.named(Self.coordinateSpace))
        .environment(\.colorScheme, .dark)
    }
}

/// Three faint dots along the bottom while dragging; the one the pill would
/// land on brightens.
private struct LeisePillAnchorDots: View {
    let model: LeisePillModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(model.anchorDots) { dot in
                let isTarget = dot.anchor == model.projectedAnchor
                Circle()
                    .fill(isTarget ? Color.white.opacity(0.9) : Color.black.opacity(contrast == .increased ? 0.55 : 0.32))
                    .overlay {
                        Circle().strokeBorder(
                            isTarget ? Color.black.opacity(0.3) : Color.white.opacity(contrast == .increased ? 0.8 : 0.5),
                            lineWidth: 0.5
                        )
                    }
                    .frame(width: isTarget ? 7 : 5, height: isTarget ? 7 : 5)
                    .position(dot.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .opacity(model.isDragging ? 1 : 0)
        .animation(LeiseMotion.adaptive(LeiseMotion.micro, reduceMotion: reduceMotion), value: model.isDragging)
        .animation(LeiseMotion.adaptive(LeiseMotion.micro, reduceMotion: reduceMotion), value: model.projectedAnchor)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Capsule

/// The dark capsule: material, hairline, shadow and content.
struct LeisePillCapsule: View {
    let model: LeisePillModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    private var interactionScale: CGFloat {
        if model.isDragging { return 1.04 }
        if model.isPressed { return 0.97 }
        return 1
    }

    var body: some View {
        let size = model.capsuleFrame.size
        let shakes = !reduceMotion
        LeisePillContentRow(model: model, size: size)
            .frame(width: size.width, height: size.height)
            .background {
                if reduceTransparency {
                    Capsule().fill(Color.black)
                } else {
                    LeisePillMaterial()
                }
            }
            .clipShape(Capsule())
            .overlay {
                Capsule().strokeBorder(Color.white.opacity(contrast == .increased ? 0.32 : 0.12), lineWidth: 0.5)
            }
            .background {
                LeisePillShadow(height: size.height, isLifted: model.isDragging)
            }
            .animation(LeiseMotion.adaptive(LeiseMotion.micro, reduceMotion: reduceMotion)) { content in
                content.scaleEffect(reduceMotion ? 1 : interactionScale)
            }
            .keyframeAnimator(initialValue: CGFloat.zero, trigger: model.shakeCount) { content, offset in
                content.offset(x: shakes ? offset : 0)
            } keyframes: { _ in
                // 300 ms, four decaying beats of at most 5 pt.
                KeyframeTrack {
                    CubicKeyframe(-5, duration: 0.06)
                    CubicKeyframe(4, duration: 0.06)
                    CubicKeyframe(-3, duration: 0.06)
                    CubicKeyframe(2, duration: 0.06)
                    CubicKeyframe(0, duration: 0.06)
                }
            }
            .modifier(LeisePillAccessibility(model: model))
    }
}

/// The soft shadow around (never through) the translucent capsule.
private struct LeisePillShadow: View {
    let height: CGFloat
    let isLifted: Bool

    var body: some View {
        // Scales with the pill: the 14 pt idle bar gets a much lighter shadow.
        let strength = min(max((height - LeisePillMetrics.idleSize.height)
            / (LeisePillMetrics.activeHeight - LeisePillMetrics.idleSize.height), 0), 1)
        let radius = (isLifted ? 18 : 6 + 8 * strength)
        let y = (isLifted ? 10 : 2 + 4 * strength)
        Capsule()
            .fill(Color.black)
            .shadow(color: Color.black.opacity(isLifted ? 0.42 : 0.26 + 0.08 * strength), radius: radius, y: y)
            .mask {
                Rectangle()
                    .padding(-LeiseSpacing.xxxl * 2)
                    .overlay { Capsule().blendMode(.destinationOut) }
                    .compositingGroup()
            }
            .allowsHitTesting(false)
    }
}

/// The dark HUD material behind the pill. Always active: Leise is usually
/// in the background, and an inactive material would turn flat.
private struct LeisePillMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> LeisePillMaterialView {
        let view = LeisePillMaterialView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .darkAqua)
        return view
    }

    func updateNSView(_ nsView: LeisePillMaterialView, context: Context) {}
}

/// Masks the blur to a capsule itself, so the material never shows square
/// corners even where SwiftUI's clip does not reach the platform view.
final class LeisePillMaterialView: NSVisualEffectView {
    private var maskHeight: CGFloat = 0

    override func layout() {
        super.layout()
        let height = bounds.height.rounded()
        guard height > 0, height != maskHeight else { return }
        maskHeight = height
        let radius = height / 2
        let image = NSImage(size: NSSize(width: height, height: height), flipped: false) { rect in
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        maskImage = image
    }
}

/// Leading glyph column (bars or result) plus the trailing text.
private struct LeisePillContentRow: View {
    let model: LeisePillModel
    let size: CGSize

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var layout: LeisePillLayout { model.layout }

    var body: some View {
        HStack(spacing: 0) {
            LeisePillGlyphColumn(model: model)
                .frame(width: layout.glyphColumnWidth ?? size.width, height: size.height)
                .animation(
                    LeiseMotion.adaptive(LeiseMotion.shape, reduceMotion: reduceMotion),
                    value: layout.glyphColumnWidth == nil
                )

            // Always present, so leaving text can fade out while the shape
            // shrinks; overflow is clipped by the capsule.
            LeisePillTrailing(model: model)
                .frame(width: layout.trailingWidth, height: size.height, alignment: .leading)
        }
        .frame(width: size.width, height: size.height, alignment: .leading)
    }
}

/// The five bars, folding into a check or cross when a message arrives.
private struct LeisePillGlyphColumn: View {
    let model: LeisePillModel
    @Environment(\.colorSchemeContrast) private var contrast

    private var message: LeisePillMessage? {
        if case let .message(message) = model.content.phase { return message }
        return nil
    }

    private var barsMode: LeisePillBars.Mode {
        switch model.content.phase {
        case .idle, .preparing:
            .resting
        case .listening, .recording:
            .live
        case .processing:
            .wave
        case .message:
            .folded
        }
    }

    private var barsColor: Color {
        let increased = contrast == .increased
        switch model.content.phase {
        case .idle:
            if model.hoverHint != nil {
                return .white.opacity(increased ? 0.9 : 0.72)
            }
            if model.isDimmed {
                return .white.opacity(increased ? 0.4 : 0.18)
            }
            return .white.opacity(increased ? 0.6 : (model.isHovering ? 0.5 : 0.34))
        case .preparing:
            return .white.opacity(increased ? 0.75 : 0.5)
        case .listening:
            return LeiseColor.live
        case .recording:
            return LeiseColor.record
        case .processing, .message:
            return .white.opacity(increased ? 0.92 : 0.78)
        }
    }

    var body: some View {
        ZStack {
            LeisePillBars(
                mode: barsMode,
                color: barsColor,
                height: model.layout.barHeight,
                level: model.level
            )

            if let message {
                LeisePillResultGlyph(message: message)
                    .id(message)
                    .transition(.asymmetric(
                        insertion: .identity,
                        removal: .opacity.animation(LeiseMotion.micro)
                    ))
            }
        }
    }
}

/// The five Leise bars as a live meter.
private struct LeisePillBars: View {
    enum Mode: Equatable {
        case resting
        case live
        case wave
        case folded
    }

    let mode: Mode
    let color: Color
    let height: CGFloat
    let level: LeisePillLevelMeter

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var smoother = LeisePillBarSmoother()

    private var animates: Bool {
        !reduceMotion && (mode == .live || mode == .wave)
    }

    var body: some View {
        TimelineView(.animation(paused: !animates)) { context in
            let heights = currentHeights(at: context.date.timeIntervalSinceReferenceDate)
            let bars = LeiseMarkShape.barRects(
                in: CGRect(x: 0, y: 0, width: height * LeiseMark.aspectRatio, height: height),
                heights: heights
            )
            ZStack(alignment: .topLeading) {
                ForEach(bars.indices, id: \.self) { index in
                    let bar = bars[index]
                    Capsule()
                        .fill(color)
                        .frame(width: bar.width, height: bar.height)
                        .position(x: bar.midX, y: bar.midY)
                }
            }
            .frame(width: height * LeiseMark.aspectRatio, height: height)
        }
        .scaleEffect(x: 1, y: mode == .folded ? 0.12 : 1)
        .opacity(mode == .folded ? 0 : 1)
        .animation(LeiseMotion.adaptive(LeiseMotion.ui, reduceMotion: reduceMotion), value: mode)
        .animation(LeiseMotion.adaptive(LeiseMotion.shape, reduceMotion: reduceMotion), value: height)
        .animation(LeiseMotion.adaptive(LeiseMotion.ui, reduceMotion: reduceMotion), value: color)
        .accessibilityHidden(true)
    }

    private func currentHeights(at time: TimeInterval) -> [CGFloat] {
        switch mode {
        case .resting, .folded:
            return smoother.settle(to: LeiseMarkShape.restingHeights)
        case .live:
            if reduceMotion {
                return smoother.settle(to: LeiseMarkShape.listeningHeights)
            }
            return smoother.follow(LeiseMarkShape.liveHeights(level: level.value(at: time), time: time), at: time)
        case .wave:
            if reduceMotion {
                return smoother.settle(to: LeiseMarkShape.restingHeights)
            }
            return smoother.settle(to: LeiseMarkShape.waveHeights(time: time))
        }
    }
}

/// Eases the live bars toward the voice level so they move smoothly at any
/// frame rate (the preview's 0.4-per-frame at 60 Hz).
@MainActor
private final class LeisePillBarSmoother {
    private var heights = LeiseMarkShape.restingHeights.map { $0 * 0.45 }
    private var lastTime: TimeInterval?

    func follow(_ target: [CGFloat], at time: TimeInterval) -> [CGFloat] {
        let deltaTime = lastTime.map { min(max(time - $0, 0), 0.1) } ?? (1.0 / 60)
        lastTime = time
        let factor = CGFloat(1 - pow(0.6, deltaTime * 60))
        for index in heights.indices where index < target.count {
            heights[index] += (target[index] - heights[index]) * factor
        }
        return heights
    }

    func settle(to target: [CGFloat]) -> [CGFloat] {
        heights = target
        lastTime = nil
        return target
    }
}

/// Check, cross or info symbol drawn after the bars fold.
private struct LeisePillResultGlyph: View {
    let message: LeisePillMessage

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var isShown = false

    private var symbolName: String {
        switch message.kind {
        case .inserted:
            "checkmark"
        case .error, .cancelled:
            "xmark"
        case .info:
            message.symbolName ?? "info.circle"
        }
    }

    private var color: Color {
        switch message.kind {
        case .inserted:
            LeiseColor.ready
        case .error:
            LeiseColor.record
        case .cancelled, .info:
            .white.opacity(contrast == .increased ? 0.9 : 0.72)
        }
    }

    private var drawsOn: Bool {
        !reduceMotion && message.kind != .info
    }

    var body: some View {
        ZStack {
            if isShown {
                Image(systemName: symbolName)
                    .font(.system(size: message.kind == .info ? 13 : 12.5, weight: .bold))
                    .foregroundStyle(color)
                    .transition(glyphTransition)
            }
        }
        .task {
            // The bars fold first (DESIGN.md: the check draws 100 ms later).
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 100))
            withAnimation(LeiseMotion.adaptive(LeiseMotion.moment, reduceMotion: reduceMotion)) {
                isShown = true
            }
        }
        .accessibilityHidden(true)
    }

    private var glyphTransition: AnyTransition {
        guard drawsOn else { return .opacity }
        if #available(macOS 26.0, *) {
            return AnyTransition(SymbolEffectTransition(effect: DrawOnSymbolEffect.drawOn, options: .default))
        }
        return .scale(scale: 0.4).combined(with: .opacity)
    }
}

/// What follows the glyph column.
private enum LeisePillTrailingItem: Equatable {
    case text(String)
    case time
    case message(LeisePillMessage)

    /// Identity: a new value crossfades. The recorder time keeps its
    /// identity and counts with `.numericText()` instead.
    var key: String {
        switch self {
        case let .text(text):
            "text-" + text
        case .time:
            "time"
        case let .message(message):
            "message-\(message.kind)-\(message.text)-\(message.undoTitle ?? "")"
        }
    }
}

/// Text after the glyph column: hover hint, Esc hint, recorder time or the
/// message with app icon and Undo.
private struct LeisePillTrailing: View {
    let model: LeisePillModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var item: LeisePillTrailingItem? {
        if let hint = model.content.escHint { return .text(hint) }
        switch model.content.phase {
        case .idle:
            return model.hoverHint.map { .text($0) }
        case .recording:
            return .time
        case let .message(message):
            return .message(message)
        case .preparing, .listening, .processing:
            return nil
        }
    }

    private var transition: AnyTransition {
        // Contents fade in 90 ms after the shape starts moving, and leave fast.
        .asymmetric(
            insertion: .opacity.animation(reduceMotion ? LeiseMotion.reduced : LeiseMotion.ui.delay(0.09)),
            removal: .opacity.animation(reduceMotion ? LeiseMotion.reduced : LeiseMotion.micro)
        )
    }

    var body: some View {
        ZStack(alignment: .leading) {
            if let item {
                // Carries its own width and text, so it can keep drawing
                // while it fades out after the pill moved on.
                LeisePillTrailingContent(model: model, item: item, width: model.layout.trailingWidth)
                    .id(item.key)
                    .transition(transition)
            }
        }
        .frame(maxHeight: .infinity, alignment: .leading)
    }
}

private struct LeisePillTrailingContent: View {
    let model: LeisePillModel
    let item: LeisePillTrailingItem
    let width: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    private var textColor: Color {
        .white.opacity(contrast == .increased ? 1 : 0.88)
    }

    var body: some View {
        Group {
            switch item {
            case let .text(string):
                text(string)
            case .time:
                if case let .recording(elapsed) = model.content.phase {
                    Text(verbatim: elapsed)
                        .font(LeisePillTypography.font(.time))
                        .foregroundStyle(textColor)
                        .contentTransition(.numericText())
                        .animation(LeiseMotion.adaptive(LeiseMotion.moment, reduceMotion: reduceMotion), value: elapsed)
                }
            case let .message(message):
                // Spacing mirrors `LeisePillMetrics.layout(for:)` exactly, so
                // the text gets the width that was measured for it.
                HStack(spacing: 0) {
                    if message.appBundleIdentifier != nil {
                        Group {
                            if let icon = model.appIcon {
                                Image(nsImage: icon)
                                    .resizable()
                                    .interpolation(.high)
                            } else {
                                Color.clear
                            }
                        }
                        .frame(width: LeisePillMetrics.appIconSize, height: LeisePillMetrics.appIconSize)
                        .padding(.trailing, LeiseSpacing.s)
                        .accessibilityHidden(true)
                    }
                    text(message.text)
                    if let undoTitle = message.undoTitle {
                        Spacer(minLength: LeiseSpacing.m)
                        LeisePillUndoButton(model: model, title: undoTitle)
                    }
                }
            }
        }
        .frame(width: max(width, 0), alignment: .leading)
    }

    private func text(_ string: String) -> some View {
        Text(verbatim: string)
            .font(LeisePillTypography.font(.message))
            .foregroundStyle(textColor)
            .lineLimit(1)
            .truncationMode(.tail)
    }
}

/// The capsule Undo button inside a feedback message. Clicks arrive through
/// the pointer window; VoiceOver uses the pill's Undo action.
private struct LeisePillUndoButton: View {
    let model: LeisePillModel
    let title: String

    var body: some View {
        Text(verbatim: title)
            .font(LeisePillTypography.font(.button))
            .foregroundStyle(Color.white)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, LeisePillMetrics.undoHorizontalPadding)
            .frame(height: LeisePillMetrics.undoHeight)
            .background(
                Capsule().fill(Color.white.opacity(model.isUndoPressed ? 0.28 : (model.isUndoHovered ? 0.18 : 0.12)))
            )
            .animation(LeiseMotion.micro, value: model.isUndoPressed)
            .animation(LeiseMotion.micro, value: model.isUndoHovered)
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .named(LeisePillStripView.coordinateSpace))
            } action: { frame in
                model.undoButtonFrame = frame
            }
            .onDisappear {
                model.undoButtonFrame = nil
            }
            .accessibilityHidden(true)
    }
}

/// One VoiceOver element for the whole pill: what it is doing, where it
/// sits, adjustable to move it, and Undo when offered.
private struct LeisePillAccessibility: ViewModifier {
    let model: LeisePillModel

    private var stateDescription: String {
        if let hint = model.content.escHint { return hint }
        switch model.content.phase {
        case .idle:
            return model.hoverHint ?? String(localized: "Idle")
        case .preparing:
            return String(localized: "Preparing microphone")
        case .listening:
            return String(localized: "Listening")
        case let .recording(elapsed):
            return String(localized: "Recording, \(elapsed)")
        case .processing:
            return String(localized: "Processing transcription")
        case let .message(message):
            return message.text
        }
    }

    func body(content: Content) -> some View {
        let undoTitle: String? = {
            if case let .message(message) = model.content.phase { return message.undoTitle }
            return nil
        }()
        content
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: String(localized: "Dictation indicator, \(stateDescription)")))
            .accessibilityValue(Text(verbatim: String(localized: "Position: \(model.anchor.localizedName)")))
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment:
                    model.onAdjustAnchor?(1)
                case .decrement:
                    model.onAdjustAnchor?(-1)
                @unknown default:
                    break
                }
            }
            .accessibilityActions {
                if let undoTitle {
                    Button(undoTitle) {
                        model.onUndo?()
                    }
                }
            }
    }
}

// MARK: - Settings

/// Darstellung › Indikator: a live preview, when the pill shows, on which
/// display, and where it rests. Embedded by the settings window.
struct IndicatorAppearanceSection: View {
    @ObservedObject private var dictation = ServiceContainer.shared.dictationViewModel

    private var isHidden: Bool { dictation.notchIndicatorVisibility == .never }

    var body: some View {
        Section {
            LeisePillPreviewStrip(
                anchor: dictation.indicatorPillAnchor,
                visibility: dictation.notchIndicatorVisibility
            )
            .listRowInsets(EdgeInsets(
                top: LeiseSpacing.m,
                leading: LeiseSpacing.m,
                bottom: LeiseSpacing.m,
                trailing: LeiseSpacing.m
            ))

            Picker(String(localized: "Show"), selection: $dictation.notchIndicatorVisibility) {
                Text(String(localized: "Always")).tag(NotchIndicatorVisibility.always)
                Text(String(localized: "Only while dictating")).tag(NotchIndicatorVisibility.duringActivity)
                Text(String(localized: "Never")).tag(NotchIndicatorVisibility.never)
            }

            Picker(String(localized: "Screen"), selection: $dictation.notchIndicatorDisplay) {
                Text(String(localized: "Active Screen")).tag(NotchIndicatorDisplay.activeScreen)
                Text(String(localized: "Primary Screen")).tag(NotchIndicatorDisplay.primaryScreen)
                Text(String(localized: "Built-in Screen")).tag(NotchIndicatorDisplay.builtInScreen)
            }
            .disabled(isHidden)

            Picker(String(localized: "Position"), selection: $dictation.indicatorPillAnchor) {
                ForEach(IndicatorAnchor.allCases, id: \.self) { anchor in
                    Text(anchor.localizedName).tag(anchor)
                }
            }
            .pickerStyle(.segmented)
            .disabled(isHidden)
        } header: {
            Text(String(localized: "Indicator"))
        } footer: {
            Text(isHidden
                ? String(localized: "Leise then shows its status only in the menu bar.")
                : String(localized: "Drag the indicator to the left, the center or the right. Leise remembers where you put it."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

/// A small desktop strip with the three spots and the real pill running
/// through a dictation. Loops only while on screen; static under Reduce Motion.
struct LeisePillPreviewStrip: View {
    var anchor: IndicatorAnchor
    var visibility: NotchIndicatorVisibility

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model = LeisePillPreviewStrip.makeModel()
    @State private var isShown = true

    static let height: CGFloat = 88
    private static let dockHeight: CGFloat = 16
    private static let bottomGap: CGFloat = LeiseSpacing.s

    private static func makeModel() -> LeisePillModel {
        let model = LeisePillModel()
        model.level.isSynthetic = true
        return model
    }

    private struct LoopKey: Equatable {
        var visibility: NotchIndicatorVisibility
        var reduceMotion: Bool
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let sideInset = max(LeiseSpacing.xxl, width * LeisePillPlacement.sideInset / 1512)
            let baseline = proxy.size.height - Self.dockHeight - Self.bottomGap - LeiseSpacing.xs
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: LeiseRadius.group, style: .continuous)
                    .fill(.quaternary)
                RoundedRectangle(cornerRadius: LeiseRadius.control, style: .continuous)
                    .fill(.quaternary)
                    .frame(width: width * 0.42, height: Self.dockHeight)
                    .position(x: width / 2, y: proxy.size.height - Self.dockHeight / 2 - LeiseSpacing.xs)

                ForEach(IndicatorAnchor.allCases, id: \.self) { spot in
                    Circle()
                        .fill(.tertiary)
                        .frame(width: 4, height: 4)
                        .position(
                            x: LeisePillPlacement.centerX(
                                for: spot,
                                width: LeisePillMetrics.idleSize.width,
                                containerWidth: width,
                                sideInset: sideInset
                            ),
                            y: baseline + Self.bottomGap / 2
                        )
                        .opacity(visibility == .never ? 0 : 1)
                }

                if visibility != .never {
                    let size = model.layout.size
                    let frame = LeisePillPlacement.restingFrame(
                        anchor: anchor,
                        size: size,
                        containerWidth: width,
                        baselineY: baseline,
                        sideInset: sideInset
                    )
                    LeisePillCapsule(model: model)
                        .environment(\.colorScheme, .dark)
                        .offset(y: isShown ? 0 : LeisePillMetrics.riseDistance)
                        .scaleEffect(isShown || reduceMotion ? 1 : LeisePillMetrics.hiddenScale, anchor: .bottom)
                        .opacity(isShown ? 1 : 0)
                        .position(x: frame.midX, y: frame.midY)
                        .animation(LeiseMotion.adaptive(LeiseMotion.shape, reduceMotion: reduceMotion), value: anchor)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: LeiseRadius.group, style: .continuous))
        }
        .frame(height: Self.height)
        .task(id: LoopKey(visibility: visibility, reduceMotion: reduceMotion)) {
            await runLoop()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Preview of the indicator"))
        .accessibilityValue(String(localized: "Position: \(anchor.localizedName)"))
    }

    private func show(_ content: LeisePillContent, shown: Bool = true) {
        withAnimation(LeiseMotion.adaptive(LeiseMotion.shape, reduceMotion: reduceMotion)) {
            model.content = content
            model.layout = LeisePillMetrics.layout(for: content, hoverHint: nil)
            model.capsuleFrame.size = model.layout.size
            isShown = shown
        }
        if case let .message(message) = content.phase {
            model.appIcon = message.appBundleIdentifier.map { AppGlyph.icon(for: $0) }
        }
    }

    private func runLoop() async {
        let showsIdle = visibility == .always
        guard visibility != .never else { return }
        guard !reduceMotion else {
            show(showsIdle ? .idle : LeisePillContent(phase: .listening), shown: true)
            return
        }

        let inserted = LeisePillContent(phase: .message(LeisePillMessage(
            kind: .inserted,
            text: String(localized: "Inserted in \("Mail")"),
            appBundleIdentifier: "com.apple.mail"
        )))
        let steps: [(LeisePillContent, Bool, Duration)] = [
            (.idle, showsIdle, .milliseconds(1600)),
            (LeisePillContent(phase: .listening), true, .milliseconds(2400)),
            (LeisePillContent(phase: .processing), true, .milliseconds(1000)),
            (inserted, true, .milliseconds(1500)),
        ]
        while !Task.isCancelled {
            for (content, shown, duration) in steps {
                show(content, shown: shown)
                try? await Task.sleep(for: duration)
                if Task.isCancelled { return }
            }
        }
    }
}
