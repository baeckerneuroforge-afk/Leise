import AppKit
import QuartzCore
import SwiftUI

// The indicator pill: one dark capsule that rests at the bottom of the screen
// and can be dragged to three fixed spots (left, center, right).
//
// Two windows carry it. A transparent strip across the bottom of the display
// draws the pill and never takes mouse events, so everything around the pill
// stays clickable. A second, invisible window sits exactly over the pill and
// receives hover, press and drag. It follows the pill every frame.
//
// All geometry (size, position, the rise from below) runs on springs that are
// integrated here on a display link, so a pill in flight can be grabbed and
// continues from exactly where it is. SwiftUI only renders those values.

// MARK: - Placement

/// Geometry of the pill along the bottom of a display. Pure functions over
/// the display's visible frame (AppKit coordinates, the area above the Dock).
///
/// Strip-local coordinates have their origin at the top-left of the strip
/// window, y pointing down, like SwiftUI inside that window.
enum LeisePillPlacement {
    /// Gap between the resting pill and the bottom of the visible frame.
    static let bottomGap: CGFloat = LeiseSpacing.m
    /// Distance of the side anchors from the visible frame's edges.
    static let sideInset: CGFloat = 96
    /// The resting pill never comes closer than this to a screen edge.
    static let edgeMargin: CGFloat = LeiseSpacing.s
    /// Room below the resting pill for its shadow. Overlaps the Dock area,
    /// which draws above the strip anyway.
    static let marginBelow: CGFloat = LeiseSpacing.xxl
    /// Room above the tallest pill for the vertical rubber band, the lift
    /// while dragging and the shadow.
    static let headroom: CGFloat = LeiseSpacing.xxxl
    /// Seconds of flight used to project where a released pill lands.
    static let projectionTime: CGFloat = 0.2
    /// The furthest a drag moves the pill up or down.
    static let verticalRubberBandLimit: CGFloat = 6
    /// How far the pill can be pulled past a screen edge.
    static let edgeRubberBandLimit: CGFloat = LeiseSpacing.l
    /// Pointer travel before a press becomes a drag.
    static let dragThreshold: CGFloat = 3

    /// The strip window that hosts the pill across the bottom of a display.
    static func stripFrame(in visibleFrame: CGRect, maxPillHeight: CGFloat = LeisePillMetrics.activeHeight) -> CGRect {
        CGRect(
            x: visibleFrame.minX,
            y: visibleFrame.minY - marginBelow,
            width: visibleFrame.width,
            height: marginBelow + bottomGap + maxPillHeight + headroom
        )
    }

    /// Bottom edge of the resting pill in strip-local coordinates.
    static func baselineY(stripHeight: CGFloat) -> CGFloat {
        stripHeight - marginBelow - bottomGap
    }

    /// The point an anchor holds and which part of the pill sits on it
    /// (0 = leading edge, 0.5 = center, 1 = trailing edge). Side anchors hold
    /// the pill's outer edge, so a widening pill grows toward the screen
    /// center instead of off the screen.
    static func pivot(
        for anchor: IndicatorAnchor,
        containerWidth: CGFloat,
        sideInset: CGFloat = sideInset
    ) -> (x: CGFloat, fraction: CGFloat) {
        switch anchor {
        case .left:
            (sideInset, 0)
        case .center:
            (containerWidth / 2, 0.5)
        case .right:
            (containerWidth - sideInset, 1)
        }
    }

    /// Range the resting pill's leading edge may take inside the container.
    static func minXRange(width: CGFloat, containerWidth: CGFloat) -> ClosedRange<CGFloat> {
        let lower = edgeMargin
        let upper = max(lower, containerWidth - edgeMargin - width)
        return lower ... upper
    }

    /// Leading edge of a resting pill of `width` held by a pivot.
    static func restingMinX(pivotX: CGFloat, fraction: CGFloat, width: CGFloat, containerWidth: CGFloat) -> CGFloat {
        let range = minXRange(width: width, containerWidth: containerWidth)
        return min(max(pivotX - fraction * width, range.lowerBound), range.upperBound)
    }

    /// The pivot springs aim for: like `pivot(for:)`, but corrected so a
    /// resting pill also stays inside a screen too small for its width.
    static func restingPivot(
        for anchor: IndicatorAnchor,
        width: CGFloat,
        containerWidth: CGFloat
    ) -> (x: CGFloat, fraction: CGFloat) {
        let pivot = pivot(for: anchor, containerWidth: containerWidth)
        let minX = restingMinX(pivotX: pivot.x, fraction: pivot.fraction, width: width, containerWidth: containerWidth)
        return (minX + pivot.fraction * width, pivot.fraction)
    }

    /// Center of a resting pill of `width` at `anchor`.
    static func centerX(
        for anchor: IndicatorAnchor,
        width: CGFloat,
        containerWidth: CGFloat,
        sideInset: CGFloat = sideInset
    ) -> CGFloat {
        let pivot = pivot(for: anchor, containerWidth: containerWidth, sideInset: sideInset)
        return restingMinX(pivotX: pivot.x, fraction: pivot.fraction, width: width, containerWidth: containerWidth)
            + width / 2
    }

    /// The resting pill in strip-local coordinates.
    static func restingFrame(
        anchor: IndicatorAnchor,
        size: CGSize,
        containerWidth: CGFloat,
        baselineY: CGFloat,
        sideInset: CGFloat = sideInset
    ) -> CGRect {
        let centerX = centerX(for: anchor, width: size.width, containerWidth: containerWidth, sideInset: sideInset)
        return CGRect(x: centerX - size.width / 2, y: baselineY - size.height, width: size.width, height: size.height)
    }

    /// The resting pill in screen (AppKit) coordinates on a display.
    static func restingFrameOnScreen(anchor: IndicatorAnchor, size: CGSize, visibleFrame: CGRect) -> CGRect {
        let centerX = centerX(for: anchor, width: size.width, containerWidth: visibleFrame.width)
        return CGRect(
            x: visibleFrame.minX + centerX - size.width / 2,
            y: visibleFrame.minY + bottomGap,
            width: size.width,
            height: size.height
        )
    }

    /// Where a pill released at `centerX` with `velocityX` (points per second) would land.
    static func projectedCenterX(_ centerX: CGFloat, velocityX: CGFloat) -> CGFloat {
        centerX + velocityX * projectionTime
    }

    /// The anchor whose resting position is closest to `centerX`.
    static func nearestAnchor(toCenterX centerX: CGFloat, width: CGFloat, containerWidth: CGFloat) -> IndicatorAnchor {
        IndicatorAnchor.allCases.min { lhs, rhs in
            abs(self.centerX(for: lhs, width: width, containerWidth: containerWidth) - centerX)
                < abs(self.centerX(for: rhs, width: width, containerWidth: containerWidth) - centerX)
        } ?? .center
    }

    /// The anchor a release lands on: the projection of the current position
    /// and velocity, snapped to the nearest anchor.
    static func landingAnchor(
        centerX: CGFloat,
        velocityX: CGFloat,
        width: CGFloat,
        containerWidth: CGFloat
    ) -> IndicatorAnchor {
        nearestAnchor(
            toCenterX: projectedCenterX(centerX, velocityX: velocityX),
            width: width,
            containerWidth: containerWidth
        )
    }

    private static let rubberBandStiffness: CGFloat = 0.55

    /// Resistance that approaches `limit` but never reaches it, like a
    /// scroll view pulled past its end.
    static func rubberBand(_ offset: CGFloat, limit: CGFloat) -> CGFloat {
        guard limit > 0, offset != 0 else { return 0 }
        let magnitude = limit * (1 - 1 / (abs(offset) * rubberBandStiffness / limit + 1))
        return offset < 0 ? -magnitude : magnitude
    }

    /// The pointer offset that `rubberBand` turns into `banded`, so a pill
    /// grabbed while springing back keeps its current height.
    static func inverseRubberBand(_ banded: CGFloat, limit: CGFloat) -> CGFloat {
        guard limit > 0, banded != 0 else { return 0 }
        let magnitude = min(abs(banded), limit * 0.999)
        let offset = (limit / rubberBandStiffness) * (magnitude / (limit - magnitude))
        return banded < 0 ? -offset : offset
    }

    /// `value` unchanged inside `range`, rubber-banded past its ends.
    static func softClamp(_ value: CGFloat, to range: ClosedRange<CGFloat>, limit: CGFloat) -> CGFloat {
        if value < range.lowerBound {
            return range.lowerBound + rubberBand(value - range.lowerBound, limit: limit)
        }
        if value > range.upperBound {
            return range.upperBound + rubberBand(value - range.upperBound, limit: limit)
        }
        return value
    }

    /// The area that receives the pointer: the pill plus a few points so the
    /// 14 pt idle bar is easy to grab. Grows monotonically with the pill, so
    /// a hovered (larger) pill always contains the idle pill's area.
    static func hitRect(forPill pill: CGRect) -> CGRect {
        let horizontalSlop = LeiseSpacing.s - 2
        let top = min(pill.minY - LeiseSpacing.xs, pill.maxY - 22)
        let bottom = pill.maxY + (LeiseSpacing.s - 2)
        return CGRect(
            x: pill.minX - horizontalSlop,
            y: top,
            width: pill.width + 2 * horizontalSlop,
            height: bottom - top
        )
    }

    /// Converts a strip-local rect into screen coordinates.
    static func screenRect(_ rect: CGRect, inStrip strip: CGRect) -> CGRect {
        CGRect(x: strip.minX + rect.minX, y: strip.maxY - rect.maxY, width: rect.width, height: rect.height)
    }

    /// Converts a screen point into strip-local coordinates.
    static func stripPoint(_ point: CGPoint, inStrip strip: CGRect) -> CGPoint {
        CGPoint(x: point.x - strip.minX, y: strip.maxY - point.y)
    }
}

// MARK: - Velocity

/// Pointer velocity from the most recent samples, in points per second.
/// A pointer that rested before release has no velocity, so a careful drop
/// lands where it is.
struct LeisePillVelocityTracker {
    /// How much history feeds the estimate.
    static let window: TimeInterval = 0.08
    /// A pause this long before release counts as resting.
    static let restThreshold: TimeInterval = 0.05

    private var samples: [(time: TimeInterval, point: CGPoint)] = []

    mutating func reset() {
        samples.removeAll(keepingCapacity: true)
    }

    mutating func add(_ point: CGPoint, at time: TimeInterval) {
        samples.append((time, point))
        samples.removeAll { time - $0.time > Self.window }
    }

    func velocity(at time: TimeInterval) -> CGVector {
        guard let last = samples.last,
              time - last.time <= Self.restThreshold,
              let first = samples.first(where: { last.time - $0.time <= Self.window }),
              last.time > first.time else {
            return .zero
        }
        let duration = CGFloat(last.time - first.time)
        return CGVector(
            dx: (last.point.x - first.point.x) / duration,
            dy: (last.point.y - first.point.y) / duration
        )
    }
}

// MARK: - Springs

/// One animated value: current value, velocity and target.
struct LeisePillSpring: Equatable {
    var value: Double
    var velocity: Double = 0
    var target: Double
    let epsilon: Double

    init(_ value: Double, epsilon: Double) {
        self.value = value
        self.target = value
        self.epsilon = epsilon
    }

    var isSettled: Bool {
        abs(target - value) <= epsilon && abs(velocity) <= epsilon * 20
    }

    mutating func snap() {
        value = target
        velocity = 0
    }

    mutating func step(by deltaTime: TimeInterval, spring: Spring = LeiseMotion.shapeSpring) {
        guard !isSettled else {
            snap()
            return
        }
        spring.update(value: &value, velocity: &velocity, target: target, deltaTime: deltaTime)
        if isSettled {
            snap()
        }
    }
}

// MARK: - Windows

/// The transparent strip that draws the pill. It ignores the mouse
/// entirely; `LeisePillHitPanel` takes the pointer where the pill is.
final class LeisePillStripPanel: NSPanel {
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        isFloatingPanel = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        hidesOnDeactivate = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        animationBehavior = .none
        appearance = NSAppearance(named: .darkAqua)
        setAccessibilityTitle("Leise")
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Invisible window exactly over the pill. Receives hover, press and drag.
final class LeisePillHitPanel: NSPanel {
    let hitView = LeisePillHitView()

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        isFloatingPanel = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        hidesOnDeactivate = false
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        isReleasedWhenClosed = false
        animationBehavior = .none
        contentView = hitView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    // The pill's own accessibility element lives in the strip; this window
    // is only a pointer target.
    override func isAccessibilityElement() -> Bool { false }
    override func accessibilityChildren() -> [Any]? { [] }
}

@MainActor
protocol LeisePillPointerHandling: AnyObject {
    func pointerEntered()
    func pointerExited()
    func pointerMoved()
    func pointerDown(_ event: NSEvent)
    func pointerDragged(_ event: NSEvent)
    func pointerUp(_ event: NSEvent)
}

/// Forwards the pointer to the controller. Its tracking area works while
/// Leise is in the background (`.activeAlways`).
final class LeisePillHitView: NSView {
    weak var handler: LeisePillPointerHandling?
    private var trackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        // One step above fully transparent, so the window server never
        // treats the area as see-through for clicks.
        layer?.backgroundColor = NSColor.black.withAlphaComponent(1 / 255).cgColor
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { handler?.pointerEntered() }
    override func mouseExited(with event: NSEvent) { handler?.pointerExited() }
    override func mouseMoved(with event: NSEvent) { handler?.pointerMoved() }
    override func mouseDown(with event: NSEvent) { handler?.pointerDown(event) }
    override func mouseDragged(with event: NSEvent) { handler?.pointerDragged(event) }
    override func mouseUp(with event: NSEvent) { handler?.pointerUp(event) }
    // A right click or scroll over the pill means nothing; swallow it rather
    // than letting it fall through to whatever is under the transparent strip.
    override func rightMouseDown(with event: NSEvent) {}
    override func scrollWheel(with event: NSEvent) {}
}

/// Receives the display link, which is added to the main run loop. The
/// target is main-actor isolated, so the `@objc` entry point checks that it
/// runs on the main thread (Swift 6 dynamic isolation).
@MainActor
private final class LeisePillDisplayLinkTarget: NSObject {
    weak var controller: LeisePillController?

    @objc func step(_ link: CADisplayLink) {
        controller?.displayLinkFired(link)
    }
}

// MARK: - Controller

/// Owns the pill's windows, its springs and the drag interaction.
/// `IndicatorCoordinator` decides what it shows and on which display.
@MainActor
final class LeisePillController: LeisePillPointerHandling {
    let model: LeisePillModel

    /// Called when a drag or VoiceOver moves the pill to a new anchor.
    var onAnchorCommitted: ((IndicatorAnchor) -> Void)?
    /// The hint the idle pill shows on hover ("fn halten zum Sprechen"),
    /// asked for each time the pointer arrives.
    var hoverHintProvider: (() -> String)?
    /// Undo for the feedback message's Undo button.
    var onUndo: (() -> Void)?
    /// The pointer in screen coordinates. Read live rather than from the
    /// event: the pointer window moves with the pill during a drag.
    var pointerLocation: () -> CGPoint = { NSEvent.mouseLocation }

    private let stripPanel = LeisePillStripPanel()
    private let hitPanel = LeisePillHitPanel()
    private let hostingView: NSHostingView<LeisePillStripView>
    private let displayLinkTarget = LeisePillDisplayLinkTarget()
    private var displayLink: CADisplayLink?
    private var lastFrameTimestamp: CFTimeInterval?
    private var framesSinceStart = 0
    private var frameWatchdog: Task<Void, Never>?
    private static let frameWatchdogDelay: Duration = .milliseconds(600)
    private let haptics: any NSHapticFeedbackPerformer = NSHapticFeedbackManager.defaultPerformer

    private var visibleFrame: CGRect = .zero
    private var stripFrame: CGRect = .zero
    private var displayMode: NotchIndicatorDisplay?
    private var anchor: IndicatorAnchor = .center
    private var content = LeisePillContent.idle
    private var isDimmed = false

    // Geometry. The pill's leading edge is `pivotX - fraction * width`; see
    // `LeisePillPlacement.pivot(for:containerWidth:)`.
    private var pivotX = LeisePillSpring(0, epsilon: 0.1)
    private var fraction = LeisePillSpring(0.5, epsilon: 0.001)
    private var width = LeisePillSpring(Double(LeisePillMetrics.idleSize.width), epsilon: 0.1)
    private var height = LeisePillSpring(Double(LeisePillMetrics.idleSize.height), epsilon: 0.1)
    /// Vertical offset from the resting line; strip-local, positive is down.
    private var lift = LeisePillSpring(0, epsilon: 0.05)
    /// 0 = sunk below its spot and transparent, 1 = shown.
    private var presence = LeisePillSpring(0, epsilon: 0.002)
    /// Reduce Motion replaces the rise and the flight with a plain crossfade.
    private var fade: (from: Double, to: Double, elapsed: TimeInterval)?

    private(set) var isPresented = false
    private var pendingDismiss = false
    private var isPointerInside = false
    private var drag: DragSession?

    private struct DragSession {
        var startPointer: CGPoint
        var startPivotX: CGFloat
        /// Pointer offset that reproduces the lift the pill had when grabbed.
        var startLiftOffset: CGFloat
        var startAnchor: IndicatorAnchor
        var lastProjectedAnchor: IndicatorAnchor
        var velocity = LeisePillVelocityTracker()
        var isDragging = false
        var isCancelled = false
        var pressesUndo = false
    }

    init() {
        let model = LeisePillModel()
        self.model = model
        hostingView = NSHostingView(rootView: LeisePillStripView(model: model))
        hostingView.sizingOptions = []
        stripPanel.contentView = hostingView
        hitPanel.hitView.handler = self
        displayLinkTarget.controller = self

        model.onAdjustAnchor = { [weak self] step in
            guard let self else { return }
            commitAnchor(anchor.moved(by: step))
        }
        model.onUndo = { [weak self] in
            self?.onUndo?()
        }
    }

    // MARK: State

    var isVisible: Bool { stripPanel.isVisible }
    var isInteracting: Bool { drag != nil }
    var currentAnchor: IndicatorAnchor { anchor }
    var isAnimating: Bool { displayLink.map { !$0.isPaused } ?? false }
    /// The pill's current frame in screen coordinates.
    var pillFrameOnScreen: CGRect { LeisePillPlacement.screenRect(model.capsuleFrame, inStrip: stripFrame) }
    /// The pointer-receiving window's frame in screen coordinates.
    var hitFrameOnScreen: CGRect { hitPanel.frame }
    var stripFrameOnScreen: CGRect { stripPanel.frame }
    var stripIgnoresMouseEvents: Bool { stripPanel.ignoresMouseEvents }
    var hitPanelIsVisible: Bool { hitPanel.isVisible }

    // MARK: Content

    func setContent(_ newContent: LeisePillContent, isDimmed newDimmed: Bool) {
        if model.isDimmed != newDimmed {
            model.isDimmed = newDimmed
        }
        isDimmed = newDimmed
        guard newContent != content else { return }
        let previous = content
        content = newContent
        model.content = newContent

        if case let .message(message) = newContent.phase {
            model.appIcon = message.appBundleIdentifier.map { AppGlyph.icon(for: $0) }
            if message.kind == .error, previous.phase != newContent.phase, !LeiseMotion.systemReduceMotion {
                model.shakeCount += 1
            }
        } else if model.appIcon != nil {
            model.appIcon = nil
        }

        if newContent.phase != .idle {
            if model.hoverHint != nil {
                model.hoverHint = nil
            }
        } else if isPointerInside, drag == nil, model.hoverHint == nil {
            model.hoverHint = hoverHintProvider?()
        }
        retarget()
    }

    /// Moves the pill to `newAnchor`, e.g. when the Position setting changes.
    func setAnchor(_ newAnchor: IndicatorAnchor) {
        guard newAnchor != anchor, drag == nil else { return }
        anchor = newAnchor
        model.anchor = newAnchor
        retarget()
    }

    /// Applies a new anchor from VoiceOver's adjustable action and reports it.
    func commitAnchor(_ target: IndicatorAnchor) {
        guard target != anchor, drag == nil else { return }
        settle(on: target, velocityX: 0, commit: true)
    }

    // MARK: Presentation

    /// Shows the pill on the display whose visible frame is given. Rising
    /// from below the first time, moving straight over when the display
    /// changes.
    func present(inVisibleFrame newVisibleFrame: CGRect, displayMode newDisplayMode: NotchIndicatorDisplay) {
        pendingDismiss = false
        if newDisplayMode != displayMode {
            displayMode = newDisplayMode
            for panel in [stripPanel, hitPanel] as [NSPanel] {
                FloatingPanelSpacePolicy.applyIndicatorPolicy(
                    to: panel,
                    displayMode: newDisplayMode,
                    windowLevel: FloatingPanelSpacePolicy.floatingIndicatorWindowLevel
                )
            }
        }
        if (newVisibleFrame != visibleFrame || !stripPanel.isVisible), drag == nil {
            place(inVisibleFrame: newVisibleFrame)
        }

        if isPresented, stripPanel.isVisible {
            if !hitPanel.isVisible, drag == nil {
                hitPanel.orderFrontRegardless()
            }
            return
        }

        isPresented = true
        if !stripPanel.isVisible {
            presence.value = 0
            presence.velocity = 0
            applyPresentation()
            stripPanel.orderFrontRegardless()
        }
        hitPanel.orderFrontRegardless()

        presence.target = 1
        if LeiseMotion.systemReduceMotion {
            presence.snap()
            startFade(to: 1)
        } else {
            fade = nil
        }
        startDisplayLink()
    }

    func present(on screen: NSScreen, displayMode: NotchIndicatorDisplay) {
        present(inVisibleFrame: screen.visibleFrame, displayMode: displayMode)
    }

    /// Orders the shown pill front again. In "active screen" mode the windows
    /// move to the active Space only when ordered front, so the coordinator
    /// calls this after a Space or app switch.
    func reassertOnActiveSpace() {
        guard isPresented, stripPanel.isVisible else { return }
        stripPanel.orderFrontRegardless()
        if drag == nil {
            hitPanel.orderFrontRegardless()
        }
    }

    /// Sinks the pill away and orders its windows out once it is gone. A
    /// drag in progress finishes first.
    func dismiss() {
        guard drag == nil else {
            pendingDismiss = true
            return
        }
        pendingDismiss = false
        guard isPresented || stripPanel.isVisible else { return }
        isPresented = false
        hitPanel.orderOut(nil)
        setPointerInside(false)
        guard stripPanel.isVisible else { return }

        presence.target = 0
        if LeiseMotion.systemReduceMotion {
            presence.snap()
            startFade(to: 0)
        } else {
            fade = nil
        }
        startDisplayLink()
    }

    /// Esc while dragging sends the pill back to where it came from.
    /// Returns whether a drag consumed the key.
    @discardableResult
    func cancelDragIfActive() -> Bool {
        guard var session = drag, session.isDragging, !session.isCancelled else { return false }
        session.isCancelled = true
        drag = session
        model.isDragging = false
        model.projectedAnchor = nil
        settle(on: session.startAnchor, velocityX: 0, commit: false)
        return true
    }

    // MARK: Placement

    private func place(inVisibleFrame newVisibleFrame: CGRect) {
        visibleFrame = newVisibleFrame
        stripFrame = LeisePillPlacement.stripFrame(in: newVisibleFrame)
        stripPanel.setFrame(stripFrame, display: false)
        // A new display: jump straight to the resting spot.
        updateTargets()
        snapGeometry()
    }

    private func currentLayout() -> LeisePillLayout {
        let containerWidth = stripFrame.width > 0 ? stripFrame.width : LeisePillMetrics.maxWidth
        return LeisePillMetrics.layout(
            for: content,
            hoverHint: content.phase == .idle ? model.hoverHint : nil,
            maxWidth: min(LeisePillMetrics.maxWidth, containerWidth - 2 * LeisePillPlacement.edgeMargin)
        )
    }

    private func updateTargets() {
        let layout = currentLayout()
        if model.layout != layout {
            model.layout = layout
        }
        width.target = Double(layout.size.width)
        height.target = Double(layout.size.height)
        guard stripFrame.width > 0, drag == nil || drag?.isCancelled == true else { return }
        let pivot = LeisePillPlacement.restingPivot(
            for: anchor,
            width: layout.size.width,
            containerWidth: stripFrame.width
        )
        pivotX.target = Double(pivot.x)
        fraction.target = Double(pivot.fraction)
        lift.target = 0
    }

    /// Points the springs at the layout for the current content and anchor.
    private func retarget() {
        updateTargets()
        if !stripPanel.isVisible || LeiseMotion.systemReduceMotion {
            snapGeometry()
        } else {
            startDisplayLink()
        }
    }

    private func snapGeometry() {
        if drag?.isDragging != true || drag?.isCancelled == true {
            pivotX.snap()
            lift.snap()
        }
        fraction.snap()
        width.snap()
        height.snap()
        applyGeometry()
    }

    // MARK: Frame loop

    private var geometryIsSettled: Bool {
        pivotX.isSettled && fraction.isSettled && width.isSettled && height.isSettled && lift.isSettled
    }

    private var isPointerDriven: Bool {
        drag?.isDragging == true && drag?.isCancelled != true
    }

    private func startDisplayLink() {
        if displayLink == nil, let view = stripPanel.contentView {
            let link = view.displayLink(
                target: displayLinkTarget,
                selector: #selector(LeisePillDisplayLinkTarget.step(_:))
            )
            link.add(to: .main, forMode: .common)
            displayLink = link
        }
        if displayLink?.isPaused != false {
            lastFrameTimestamp = nil
            displayLink?.isPaused = false
        }
        armFrameWatchdog()
    }

    fileprivate func displayLinkFired(_ link: CADisplayLink) {
        let now = link.timestamp
        let deltaTime = lastFrameTimestamp.map { min(max(now - $0, 1.0 / 240), 1.0 / 20) } ?? (1.0 / 120)
        lastFrameTimestamp = now
        framesSinceStart += 1
        step(by: deltaTime)
    }

    /// A display that sleeps (or a window macOS considers occluded) delivers
    /// no frames. Rather than leaving the pill half risen or never ordered
    /// out, finish the animation without motion if no frame arrives.
    private func armFrameWatchdog() {
        framesSinceStart = 0
        frameWatchdog?.cancel()
        frameWatchdog = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.frameWatchdogDelay)
            guard !Task.isCancelled, let self, framesSinceStart == 0, isAnimating else { return }
            finishAnimationsWithoutMotion()
        }
    }

    private func finishAnimationsWithoutMotion() {
        if !isPointerDriven {
            pivotX.snap()
            lift.snap()
        }
        fraction.snap()
        width.snap()
        height.snap()
        presence.snap()
        fade = nil
        applyGeometry()
        applyPresentation()
        displayLink?.isPaused = true
        lastFrameTimestamp = nil
        didSettle()
    }

    /// Advances every spring by `deltaTime`. Internal so tests can run the
    /// frame loop without a display.
    func step(by deltaTime: TimeInterval) {
        if !isPointerDriven {
            pivotX.step(by: deltaTime)
            lift.step(by: deltaTime)
        }
        fraction.step(by: deltaTime)
        width.step(by: deltaTime)
        height.step(by: deltaTime)
        presence.step(by: deltaTime)
        applyGeometry()
        applyPresentation(advancingFadeBy: deltaTime)

        if geometryIsSettled, presence.isSettled, fade == nil {
            displayLink?.isPaused = true
            lastFrameTimestamp = nil
            didSettle()
        }
    }

    private func didSettle() {
        if !isPresented, stripPanel.isVisible {
            stripPanel.orderOut(nil)
            hitPanel.orderOut(nil)
            return
        }
        syncPointerInside()
    }

    private func applyGeometry() {
        guard stripFrame.width > 0 else { return }
        let w = CGFloat(width.value)
        let h = CGFloat(height.value)
        var minX = CGFloat(pivotX.value) - CGFloat(fraction.value) * w
        if isPointerDriven {
            minX = LeisePillPlacement.softClamp(
                minX,
                to: LeisePillPlacement.minXRange(width: w, containerWidth: stripFrame.width),
                limit: LeisePillPlacement.edgeRubberBandLimit
            )
        }
        let baseline = LeisePillPlacement.baselineY(stripHeight: stripFrame.height)
        let frame = CGRect(x: minX, y: baseline - h + CGFloat(lift.value), width: w, height: h)
        if model.capsuleFrame != frame {
            model.capsuleFrame = frame
        }
        if isPointerDriven {
            updateAnchorDots(width: w, baseline: baseline)
        }
        updateHitPanelFrame(for: frame)
    }

    private func applyPresentation(advancingFadeBy deltaTime: TimeInterval = 0) {
        let progress = CGFloat(presence.value)
        // Under Reduce Motion the pill only fades; it never moves or scales.
        let moves = !LeiseMotion.systemReduceMotion
        let offset = moves ? (1 - progress) * LeisePillMetrics.riseDistance : 0
        let scale = moves ? LeisePillMetrics.hiddenScale + (1 - LeisePillMetrics.hiddenScale) * progress : 1
        // Opacity leads the motion so the pill is fully there before it lands.
        var opacity = Double(min(max(progress * 1.6, 0), 1))

        if var current = fade {
            current.elapsed += deltaTime
            let t = min(max(current.elapsed / LeiseMotion.reducedDuration, 0), 1)
            let eased = t * t * (3 - 2 * t)
            opacity = current.from + (current.to - current.from) * eased
            fade = t >= 1 ? nil : current
        }

        if model.presentationOffset != offset { model.presentationOffset = offset }
        if model.presentationScale != scale { model.presentationScale = scale }
        if model.presentationOpacity != opacity { model.presentationOpacity = opacity }
    }

    private func startFade(to target: Double, from origin: Double? = nil) {
        fade = (from: origin ?? model.presentationOpacity, to: target, elapsed: 0)
    }

    private func updateHitPanelFrame(for pill: CGRect) {
        let rect = LeisePillPlacement.screenRect(LeisePillPlacement.hitRect(forPill: pill), inStrip: stripFrame)
            .integral
        if hitPanel.frame != rect {
            hitPanel.setFrame(rect, display: false)
        }
    }

    private func updateAnchorDots(width: CGFloat, baseline: CGFloat) {
        let y = baseline + LeisePillPlacement.bottomGap / 2
        let dots = IndicatorAnchor.allCases.map { anchor in
            LeisePillAnchorDot(
                anchor: anchor,
                center: CGPoint(
                    x: LeisePillPlacement.centerX(for: anchor, width: width, containerWidth: stripFrame.width),
                    y: y
                )
            )
        }
        if model.anchorDots != dots {
            model.anchorDots = dots
        }
    }

    // MARK: Pointer

    func pointerEntered() {
        guard drag == nil else { return }
        setPointerInside(true)
    }

    func pointerExited() {
        guard drag == nil else { return }
        setPointerInside(false)
    }

    func pointerMoved() {
        guard drag == nil else { return }
        if isPointerInside {
            NSCursor.openHand.set()
        } else {
            setPointerInside(true)
        }
        updateUndoHover()
    }

    func pointerDown(_ event: NSEvent) {
        let pointer = pointerLocation()
        if !isPointerInside {
            setPointerInside(true)
        }
        // Grabbing a pill in flight stops it exactly where it is. The grab
        // point becomes the pivot, so if the pill changes size while it is
        // carried, the spot under the pointer stays under the pointer.
        let frame = model.capsuleFrame
        let localX = LeisePillPlacement.stripPoint(pointer, inStrip: stripFrame).x
        let grabFraction = frame.width > 0 ? min(max((localX - frame.minX) / frame.width, 0), 1) : 0.5
        fraction.value = Double(grabFraction)
        fraction.target = fraction.value
        fraction.velocity = 0
        pivotX.value = Double(frame.minX + grabFraction * frame.width)
        pivotX.target = pivotX.value
        pivotX.velocity = 0
        let startLift = CGFloat(lift.value)
        lift.target = lift.value
        lift.velocity = 0

        var session = DragSession(
            startPointer: pointer,
            startPivotX: CGFloat(pivotX.value),
            startLiftOffset: LeisePillPlacement.inverseRubberBand(
                -startLift,
                limit: LeisePillPlacement.verticalRubberBandLimit
            ),
            startAnchor: anchor,
            lastProjectedAnchor: anchor,
            pressesUndo: undoButtonContains(pointer)
        )
        session.velocity.add(pointer, at: event.timestamp)
        drag = session

        if session.pressesUndo {
            model.isUndoPressed = true
        } else {
            model.isPressed = true
            NSCursor.closedHand.set()
        }
    }

    func pointerDragged(_ event: NSEvent) {
        guard var session = drag, !session.isCancelled else { return }
        let pointer = pointerLocation()
        session.velocity.add(pointer, at: event.timestamp)
        let dx = pointer.x - session.startPointer.x
        let dy = pointer.y - session.startPointer.y

        if session.pressesUndo {
            let inside = undoButtonContains(pointer)
            if model.isUndoPressed != inside {
                model.isUndoPressed = inside
            }
            drag = session
            return
        }

        if !session.isDragging {
            guard hypot(dx, dy) >= LeisePillPlacement.dragThreshold else {
                drag = session
                return
            }
            session.isDragging = true
            model.isPressed = false
            model.isDragging = true
            model.projectedAnchor = anchor
            drag = session
            if model.hoverHint != nil {
                // Carrying the idle pill keeps it small, so it is easy to
                // see where it lands.
                model.hoverHint = nil
                retarget()
            }
        }

        NSCursor.closedHand.set()
        // Horizontal follows the pointer 1:1, vertical rubber-bands.
        pivotX.value = Double(session.startPivotX + dx)
        pivotX.target = pivotX.value
        lift.value = Double(-LeisePillPlacement.rubberBand(
            session.startLiftOffset + dy,
            limit: LeisePillPlacement.verticalRubberBandLimit
        ))
        lift.target = lift.value
        drag = session
        applyGeometry()

        let projected = LeisePillPlacement.landingAnchor(
            centerX: model.capsuleFrame.midX,
            velocityX: session.velocity.velocity(at: event.timestamp).dx,
            width: model.capsuleFrame.width,
            containerWidth: stripFrame.width
        )
        if projected != session.lastProjectedAnchor {
            session.lastProjectedAnchor = projected
            drag = session
            haptics.perform(.alignment, performanceTime: .now)
            model.projectedAnchor = projected
        }
    }

    func pointerUp(_ event: NSEvent) {
        guard var session = drag else { return }
        let pointer = pointerLocation()
        model.isPressed = false

        if session.pressesUndo {
            drag = nil
            model.isUndoPressed = false
            // The press froze the pill; let it finish any flight.
            retarget()
            if undoButtonContains(pointer) {
                onUndo?()
            }
        } else if session.isDragging, !session.isCancelled {
            session.velocity.add(pointer, at: event.timestamp)
            let velocity = session.velocity.velocity(at: event.timestamp)
            let frame = model.capsuleFrame
            let landing = LeisePillPlacement.landingAnchor(
                centerX: frame.midX,
                velocityX: velocity.dx,
                width: frame.width,
                containerWidth: stripFrame.width
            )
            // Continue from where the pill is drawn, including any edge
            // rubber band, so the release never jumps.
            pivotX.value = Double(frame.minX + CGFloat(fraction.value) * frame.width)
            drag = nil
            model.isDragging = false
            model.projectedAnchor = nil
            settle(on: landing, velocityX: velocity.dx, commit: true)
        } else {
            // A press without a drag (or a cancelled drag): if the press
            // caught the pill in flight, it continues home from there.
            let wasCancelled = session.isCancelled
            drag = nil
            if !wasCancelled {
                retarget()
            }
        }

        if pendingDismiss {
            dismiss()
            return
        }
        // The pill may have flown out from under the pointer.
        let resting = LeisePillPlacement.restingFrame(
            anchor: anchor,
            size: model.layout.size,
            containerWidth: stripFrame.width,
            baselineY: LeisePillPlacement.baselineY(stripHeight: stripFrame.height)
        )
        let restingHit = LeisePillPlacement.screenRect(LeisePillPlacement.hitRect(forPill: resting), inStrip: stripFrame)
        setPointerInside(restingHit.contains(pointer), forceCursor: true)
    }

    /// Springs the pill to `target`, carrying the release velocity, and for
    /// a real drop persists the new anchor.
    private func settle(on target: IndicatorAnchor, velocityX: CGFloat, commit: Bool) {
        let previous = anchor
        anchor = target
        model.anchor = target
        updateTargets()
        let pivot = LeisePillPlacement.restingPivot(
            for: target,
            width: CGFloat(width.target),
            containerWidth: stripFrame.width
        )
        pivotX.target = Double(pivot.x)
        pivotX.velocity = Double(velocityX)
        fraction.target = Double(pivot.fraction)
        lift.target = 0
        lift.velocity = 0

        if LeiseMotion.systemReduceMotion || !stripPanel.isVisible {
            // No flight: the pill reappears at its new spot.
            pivotX.snap()
            lift.snap()
            fraction.snap()
            applyGeometry()
            if stripPanel.isVisible {
                startFade(to: 1, from: 0)
                startDisplayLink()
            }
        } else {
            startDisplayLink()
        }
        if commit, target != previous {
            onAnchorCommitted?(target)
        }
    }

    private func setPointerInside(_ inside: Bool, forceCursor: Bool = false) {
        let changed = inside != isPointerInside
        guard changed || forceCursor else { return }
        let hintBefore = model.hoverHint
        isPointerInside = inside
        if model.isHovering != inside {
            model.isHovering = inside
        }
        if inside {
            NSCursor.openHand.set()
            if content.phase == .idle, model.hoverHint == nil {
                model.hoverHint = hoverHintProvider?()
            }
        } else {
            NSCursor.arrow.set()
            if model.hoverHint != nil {
                model.hoverHint = nil
            }
            if model.isUndoHovered {
                model.isUndoHovered = false
            }
        }
        if changed || model.hoverHint != hintBefore {
            retarget()
        }
    }

    /// Hover and exit only arrive when the pointer moves. When the pill moves
    /// away from (or under) a resting pointer, check by hand.
    private func syncPointerInside() {
        guard drag == nil else { return }
        let inside = hitPanel.isVisible && hitPanel.frame.contains(pointerLocation())
        if inside != isPointerInside {
            setPointerInside(inside)
        }
    }

    private func undoButtonContains(_ screenPoint: CGPoint) -> Bool {
        guard case let .message(message) = content.phase,
              message.undoTitle != nil,
              let frame = model.undoButtonFrame else {
            return false
        }
        return frame.insetBy(dx: -LeiseSpacing.xs, dy: -LeiseSpacing.xs)
            .contains(LeisePillPlacement.stripPoint(screenPoint, inStrip: stripFrame))
    }

    private func updateUndoHover() {
        let hovered = undoButtonContains(pointerLocation())
        if model.isUndoHovered != hovered {
            model.isUndoHovered = hovered
        }
    }
}
