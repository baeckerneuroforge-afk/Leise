import AppKit
import SwiftUI
import XCTest
@testable import Leise

// MARK: - Anchor geometry

final class LeisePillPlacementTests: XCTestCase {
    private let idle = LeisePillMetrics.idleSize
    private let message = CGSize(width: 290, height: LeisePillMetrics.activeHeight)

    /// A 14" MacBook Pro display with the Dock at the bottom.
    private let dockBottom = CGRect(x: 0, y: 70, width: 1512, height: 875)
    /// The same display with the Dock on the left.
    private let dockLeft = CGRect(x: 62, y: 0, width: 1450, height: 945)
    /// A second display left of the main one, with the Dock hidden.
    private let secondaryDisplay = CGRect(x: -1920, y: 4, width: 1920, height: 1051)

    func testPillRestsTwelvePointsAboveTheDock() {
        for anchor in IndicatorAnchor.allCases {
            let frame = LeisePillPlacement.restingFrameOnScreen(anchor: anchor, size: idle, visibleFrame: dockBottom)
            XCTAssertEqual(frame.minY, dockBottom.minY + 12, "\(anchor)")
            XCTAssertEqual(frame.size, idle)
        }
    }

    func testCenterAnchorIsCenteredOnTheVisibleFrame() {
        let frame = LeisePillPlacement.restingFrameOnScreen(anchor: .center, size: idle, visibleFrame: dockBottom)

        XCTAssertEqual(frame.midX, dockBottom.midX)
    }

    func testSideAnchorsSitNinetySixPointsInsideTheEdges() {
        let left = LeisePillPlacement.restingFrameOnScreen(anchor: .left, size: idle, visibleFrame: dockBottom)
        let right = LeisePillPlacement.restingFrameOnScreen(anchor: .right, size: idle, visibleFrame: dockBottom)

        XCTAssertEqual(left.minX, dockBottom.minX + 96)
        XCTAssertEqual(right.maxX, dockBottom.maxX - 96)
    }

    func testDockOnTheLeftShiftsAnchorsWithTheVisibleFrame() {
        let left = LeisePillPlacement.restingFrameOnScreen(anchor: .left, size: idle, visibleFrame: dockLeft)
        let center = LeisePillPlacement.restingFrameOnScreen(anchor: .center, size: idle, visibleFrame: dockLeft)
        let right = LeisePillPlacement.restingFrameOnScreen(anchor: .right, size: idle, visibleFrame: dockLeft)

        XCTAssertEqual(left.minX, 62 + 96, "the left spot starts after the Dock")
        XCTAssertEqual(center.midX, dockLeft.midX)
        XCTAssertEqual(right.maxX, 1512 - 96)
        XCTAssertEqual(center.minY, 12, "without a bottom Dock the pill sits 12 pt above the screen edge")
    }

    func testSecondaryDisplayWithNegativeOriginKeepsAnchorsOnThatDisplay() {
        for anchor in IndicatorAnchor.allCases {
            let frame = LeisePillPlacement.restingFrameOnScreen(anchor: anchor, size: message, visibleFrame: secondaryDisplay)
            XCTAssertTrue(secondaryDisplay.contains(frame), "\(anchor) \(frame)")
        }
    }

    func testWideningPillGrowsTowardTheScreenCenter() {
        let idleLeft = LeisePillPlacement.restingFrameOnScreen(anchor: .left, size: idle, visibleFrame: dockBottom)
        let wideLeft = LeisePillPlacement.restingFrameOnScreen(anchor: .left, size: message, visibleFrame: dockBottom)
        let idleRight = LeisePillPlacement.restingFrameOnScreen(anchor: .right, size: idle, visibleFrame: dockBottom)
        let wideRight = LeisePillPlacement.restingFrameOnScreen(anchor: .right, size: message, visibleFrame: dockBottom)
        let idleCenter = LeisePillPlacement.restingFrameOnScreen(anchor: .center, size: idle, visibleFrame: dockBottom)
        let wideCenter = LeisePillPlacement.restingFrameOnScreen(anchor: .center, size: message, visibleFrame: dockBottom)

        XCTAssertEqual(wideLeft.minX, idleLeft.minX, "the left pill keeps its outer edge")
        XCTAssertEqual(wideRight.maxX, idleRight.maxX, "the right pill keeps its outer edge")
        XCTAssertEqual(wideCenter.midX, idleCenter.midX, "the centered pill grows both ways")
    }

    func testSmallScreenKeepsEveryAnchorInsideAndInOrder() {
        let small = CGRect(x: 0, y: 0, width: 640, height: 480)
        let centers = IndicatorAnchor.allCases.map {
            LeisePillPlacement.restingFrameOnScreen(anchor: $0, size: message, visibleFrame: small)
        }

        for frame in centers {
            XCTAssertGreaterThanOrEqual(frame.minX, small.minX + LeisePillPlacement.edgeMargin)
            XCTAssertLessThanOrEqual(frame.maxX, small.maxX - LeisePillPlacement.edgeMargin)
        }
        XCTAssertLessThanOrEqual(centers[0].midX, centers[1].midX)
        XCTAssertLessThanOrEqual(centers[1].midX, centers[2].midX)
    }

    func testPillWiderThanTheScreenStaysInsideTheEdgeMargins() {
        let tiny = CGRect(x: 0, y: 0, width: 280, height: 400)
        let tooWide = CGSize(width: 264, height: LeisePillMetrics.activeHeight)

        for anchor in IndicatorAnchor.allCases {
            let frame = LeisePillPlacement.restingFrameOnScreen(anchor: anchor, size: tooWide, visibleFrame: tiny)
            XCTAssertEqual(frame.minX, LeisePillPlacement.edgeMargin, "\(anchor)")
        }
    }

    func testRestingPivotMatchesTheRestingFrame() {
        let containerWidth: CGFloat = 640
        for anchor in IndicatorAnchor.allCases {
            for width in [idle.width, 150, message.width, 600] {
                let pivot = LeisePillPlacement.restingPivot(for: anchor, width: width, containerWidth: containerWidth)
                let expected = LeisePillPlacement.restingFrame(
                    anchor: anchor,
                    size: CGSize(width: width, height: 30),
                    containerWidth: containerWidth,
                    baselineY: 50
                )
                XCTAssertEqual(pivot.x - pivot.fraction * width, expected.minX, accuracy: 0.001, "\(anchor) \(width)")
            }
        }
    }

    func testStripCoversTheVisibleWidthAndReachesBelowTheDockEdge() {
        let strip = LeisePillPlacement.stripFrame(in: dockBottom)

        XCTAssertEqual(strip.minX, dockBottom.minX)
        XCTAssertEqual(strip.width, dockBottom.width)
        XCTAssertLessThan(strip.minY, dockBottom.minY, "room for the shadow below the pill")
        XCTAssertGreaterThan(strip.maxY, dockBottom.minY + 12 + LeisePillMetrics.activeHeight)
    }

    func testStripLocalAndScreenCoordinatesRoundTrip() {
        let strip = LeisePillPlacement.stripFrame(in: dockBottom)
        let baseline = LeisePillPlacement.baselineY(stripHeight: strip.height)
        let local = LeisePillPlacement.restingFrame(
            anchor: .left,
            size: idle,
            containerWidth: strip.width,
            baselineY: baseline
        )

        let onScreen = LeisePillPlacement.screenRect(local, inStrip: strip)

        XCTAssertEqual(onScreen, LeisePillPlacement.restingFrameOnScreen(anchor: .left, size: idle, visibleFrame: dockBottom))
        XCTAssertEqual(
            LeisePillPlacement.stripPoint(CGPoint(x: onScreen.minX, y: onScreen.maxY), inStrip: strip),
            CGPoint(x: local.minX, y: local.minY)
        )
    }

    func testHitAreaCoversThePillAndGrowsMonotonically() {
        let idleFrame = CGRect(x: 100, y: 40, width: idle.width, height: idle.height)
        let hovered = CGRect(x: 100, y: 54 - 30, width: 150, height: 30)

        let idleHit = LeisePillPlacement.hitRect(forPill: idleFrame)
        let hoveredHit = LeisePillPlacement.hitRect(forPill: hovered)

        XCTAssertTrue(idleHit.contains(idleFrame))
        XCTAssertGreaterThanOrEqual(idleHit.height, 28, "the 14 pt bar is easy to grab")
        XCTAssertTrue(hoveredHit.contains(idleHit), "hovering never shrinks the hit area under the pointer")
        XCTAssertLessThanOrEqual(idleHit.width - idleFrame.width, 12, "only a few points of slop")
    }
}

// MARK: - Release projection

final class LeisePillProjectionTests: XCTestCase {
    private let containerWidth: CGFloat = 1512
    private let width = LeisePillMetrics.idleSize.width

    private func center(_ anchor: IndicatorAnchor) -> CGFloat {
        LeisePillPlacement.centerX(for: anchor, width: width, containerWidth: containerWidth)
    }

    func testProjectionUsesTwoHundredMillisecondsOfFlight() {
        XCTAssertEqual(LeisePillPlacement.projectedCenterX(500, velocityX: 1000), 700)
        XCTAssertEqual(LeisePillPlacement.projectedCenterX(500, velocityX: -250), 450)
    }

    func testGentleReleaseLandsOnTheNearestAnchor() {
        let nearCenter = center(.center) - 120

        XCTAssertEqual(
            LeisePillPlacement.landingAnchor(centerX: nearCenter, velocityX: 0, width: width, containerWidth: containerWidth),
            .center
        )
    }

    func testFlingFromTheCenterReachesTheLeftAnchor() {
        let start = center(.center) - 60

        XCTAssertEqual(
            LeisePillPlacement.landingAnchor(centerX: start, velocityX: -2400, width: width, containerWidth: containerWidth),
            .left,
            "a quick flick carries the pill even though it was released near the center"
        )
    }

    func testFlingFromTheLeftReachesTheRightAnchorWithEnoughSpeed() {
        let start = center(.left) + 40

        XCTAssertEqual(
            LeisePillPlacement.landingAnchor(centerX: start, velocityX: 1500, width: width, containerWidth: containerWidth),
            .center
        )
        XCTAssertEqual(
            LeisePillPlacement.landingAnchor(centerX: start, velocityX: 6000, width: width, containerWidth: containerWidth),
            .right
        )
    }

    func testFlingBackAgainstTheDragDirectionReturnsHome() {
        let draggedTowardRight = center(.center) + 350

        XCTAssertEqual(
            LeisePillPlacement.landingAnchor(
                centerX: draggedTowardRight,
                velocityX: -1800,
                width: width,
                containerWidth: containerWidth
            ),
            .center
        )
    }

    func testReleasePastAnEdgeLandsOnThatSide() {
        XCTAssertEqual(
            LeisePillPlacement.landingAnchor(centerX: -40, velocityX: 0, width: width, containerWidth: containerWidth),
            .left
        )
        XCTAssertEqual(
            LeisePillPlacement.landingAnchor(centerX: containerWidth + 40, velocityX: 0, width: width, containerWidth: containerWidth),
            .right
        )
    }

    func testVelocityTrackerMeasuresTheLastSamples() {
        var tracker = LeisePillVelocityTracker()
        tracker.add(CGPoint(x: 0, y: 0), at: 1.00)
        tracker.add(CGPoint(x: 10, y: 2), at: 1.01)
        tracker.add(CGPoint(x: 20, y: 4), at: 1.02)
        tracker.add(CGPoint(x: 30, y: 6), at: 1.03)

        let velocity = tracker.velocity(at: 1.03)

        XCTAssertEqual(velocity.dx, 1000, accuracy: 0.5)
        XCTAssertEqual(velocity.dy, 200, accuracy: 0.5)
    }

    func testVelocityTrackerForgetsOldSamples() {
        var tracker = LeisePillVelocityTracker()
        tracker.add(CGPoint(x: 0, y: 0), at: 1.0)
        tracker.add(CGPoint(x: 400, y: 0), at: 1.02)
        tracker.add(CGPoint(x: 405, y: 0), at: 1.2)
        tracker.add(CGPoint(x: 410, y: 0), at: 1.21)

        XCTAssertEqual(tracker.velocity(at: 1.21).dx, 500, accuracy: 0.5, "only the last 80 ms count")
    }

    func testPointerThatRestedBeforeReleaseHasNoVelocity() {
        var tracker = LeisePillVelocityTracker()
        tracker.add(CGPoint(x: 0, y: 0), at: 1.00)
        tracker.add(CGPoint(x: 50, y: 0), at: 1.02)

        XCTAssertEqual(tracker.velocity(at: 1.2), .zero, "a careful drop lands where it is")
    }

    func testVerticalRubberBandNeverExceedsSixPoints() {
        let limit = LeisePillPlacement.verticalRubberBandLimit
        var previous: CGFloat = 0
        for offset in stride(from: CGFloat(1), through: 400, by: 7) {
            let banded = LeisePillPlacement.rubberBand(offset, limit: limit)
            XCTAssertLessThan(banded, limit)
            XCTAssertGreaterThan(banded, previous, "monotonic")
            XCTAssertEqual(LeisePillPlacement.rubberBand(-offset, limit: limit), -banded, "symmetric")
            previous = banded
        }
        XCTAssertEqual(LeisePillPlacement.rubberBand(0, limit: limit), 0)
    }

    func testInverseRubberBandRoundTrips() {
        let limit = LeisePillPlacement.verticalRubberBandLimit
        for offset in [-120, -12, -2, 0.5, 3, 40, 200] as [CGFloat] {
            let banded = LeisePillPlacement.rubberBand(offset, limit: limit)
            XCTAssertEqual(LeisePillPlacement.inverseRubberBand(banded, limit: limit), offset, accuracy: 0.01)
        }
    }

    func testSoftClampIsIdentityInsideTheRange() {
        XCTAssertEqual(LeisePillPlacement.softClamp(50, to: 10 ... 100, limit: 16), 50)
        XCTAssertGreaterThan(LeisePillPlacement.softClamp(-200, to: 10 ... 100, limit: 16), 10 - 16)
        XCTAssertLessThan(LeisePillPlacement.softClamp(400, to: 10 ... 100, limit: 16), 100 + 16)
    }

    func testSpringSettlesOnItsTargetAndCanBeRetargetedMidFlight() {
        var spring = LeisePillSpring(0, epsilon: 0.1)
        spring.target = 100
        for _ in 0 ..< 6 {
            spring.step(by: 1.0 / 120)
        }
        let midFlight = spring.value
        XCTAssertGreaterThan(midFlight, 0)
        XCTAssertLessThan(midFlight, 100)

        // Retarget: continues from where it is, no jump.
        spring.target = -50
        spring.step(by: 1.0 / 120)
        XCTAssertEqual(spring.value, midFlight, accuracy: 15)

        for _ in 0 ..< 240 {
            spring.step(by: 1.0 / 120)
        }
        XCTAssertTrue(spring.isSettled)
        XCTAssertEqual(spring.value, -50)
    }
}

// MARK: - Anchor persistence and migration

final class LeisePillSettingsTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "LeisePillSettingsTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testAnchorDefaultsToCenter() {
        XCTAssertEqual(DictationViewModel.loadIndicatorPillAnchor(defaults: defaults), .center)
    }

    func testEveryAnchorPersists() {
        for anchor in IndicatorAnchor.allCases {
            DictationViewModel.persistIndicatorPillAnchor(anchor, defaults: defaults)

            XCTAssertEqual(defaults.string(forKey: UserDefaultsKeys.indicatorPillAnchor), anchor.rawValue)
            XCTAssertEqual(DictationViewModel.loadIndicatorPillAnchor(defaults: defaults), anchor)
        }
    }

    func testUnknownAnchorFallsBackToCenter() {
        defaults.set("top", forKey: UserDefaultsKeys.indicatorPillAnchor)

        XCTAssertEqual(DictationViewModel.loadIndicatorPillAnchor(defaults: defaults), .center)
    }

    func testAnchorNeighboursStopAtTheEnds() {
        XCTAssertEqual(IndicatorAnchor.center.moved(by: -1), .left)
        XCTAssertEqual(IndicatorAnchor.center.moved(by: 1), .right)
        XCTAssertEqual(IndicatorAnchor.left.moved(by: -1), .left)
        XCTAssertEqual(IndicatorAnchor.right.moved(by: 1), .right)
    }

    func testMigrationMovesNotchAndOverlayToThePill() {
        for legacy in [IndicatorStyle.notch, .overlay] {
            defaults.set(legacy.rawValue, forKey: UserDefaultsKeys.indicatorStyle)

            DictationViewModel.migrateLegacyIndicatorSettings(defaults: defaults)

            XCTAssertEqual(defaults.string(forKey: UserDefaultsKeys.indicatorStyle), IndicatorStyle.minimal.rawValue)
            XCTAssertEqual(DictationViewModel.loadIndicatorStyle(defaults: defaults), .minimal)
        }
    }

    func testMigrationKeepsTheMinimalStyleAndUnknownValuesLoadAsThePill() {
        defaults.set(IndicatorStyle.minimal.rawValue, forKey: UserDefaultsKeys.indicatorStyle)
        DictationViewModel.migrateLegacyIndicatorSettings(defaults: defaults)
        XCTAssertEqual(defaults.string(forKey: UserDefaultsKeys.indicatorStyle), IndicatorStyle.minimal.rawValue)

        defaults.set("mystery", forKey: UserDefaultsKeys.indicatorStyle)
        DictationViewModel.migrateLegacyIndicatorSettings(defaults: defaults)
        XCTAssertEqual(DictationViewModel.loadIndicatorStyle(defaults: defaults), .minimal)
    }

    func testMigrationLeavesAFreshInstallUntouched() {
        DictationViewModel.migrateLegacyIndicatorSettings(defaults: defaults)

        XCTAssertNil(defaults.object(forKey: UserDefaultsKeys.indicatorStyle))
        XCTAssertNil(defaults.object(forKey: UserDefaultsKeys.indicatorPillAnchor))
        XCTAssertEqual(DictationViewModel.loadIndicatorVisibility(defaults: defaults), .always)
    }

    func testMigrationDropsTheTopBottomPosition() {
        defaults.set(OverlayPosition.top.rawValue, forKey: UserDefaultsKeys.overlayPosition)

        DictationViewModel.migrateLegacyIndicatorSettings(defaults: defaults)

        XCTAssertNil(defaults.object(forKey: UserDefaultsKeys.overlayPosition), "the pill always rests at the bottom")
    }

    func testMigrationKeepsVisibilityDisplayAndUnusedLegacyKeys() {
        defaults.set(NotchIndicatorVisibility.duringActivity.rawValue, forKey: UserDefaultsKeys.notchIndicatorVisibility)
        defaults.set(NotchIndicatorDisplay.builtInScreen.rawValue, forKey: UserDefaultsKeys.notchIndicatorDisplay)
        defaults.set(NotchIndicatorContent.timer.rawValue, forKey: UserDefaultsKeys.notchIndicatorLeftContent)

        DictationViewModel.migrateLegacyIndicatorSettings(defaults: defaults)

        XCTAssertEqual(DictationViewModel.loadIndicatorVisibility(defaults: defaults), .duringActivity)
        XCTAssertEqual(defaults.string(forKey: UserDefaultsKeys.notchIndicatorDisplay), NotchIndicatorDisplay.builtInScreen.rawValue)
        XCTAssertEqual(defaults.string(forKey: UserDefaultsKeys.notchIndicatorLeftContent), NotchIndicatorContent.timer.rawValue)
    }

    func testMigrationIsIdempotent() {
        defaults.set(IndicatorStyle.notch.rawValue, forKey: UserDefaultsKeys.indicatorStyle)
        defaults.set(OverlayPosition.top.rawValue, forKey: UserDefaultsKeys.overlayPosition)

        DictationViewModel.migrateLegacyIndicatorSettings(defaults: defaults)
        DictationViewModel.migrateLegacyIndicatorSettings(defaults: defaults)

        XCTAssertEqual(defaults.string(forKey: UserDefaultsKeys.indicatorStyle), IndicatorStyle.minimal.rawValue)
        XCTAssertNil(defaults.object(forKey: UserDefaultsKeys.overlayPosition))
    }
}

// MARK: - Content

final class LeisePillContentTests: XCTestCase {
    func testRecordingWithLiveMicrophoneListens() {
        let content = LeisePillContent.resolve(LeisePillInputs(dictationState: .recording))

        XCTAssertEqual(content.phase, .listening)
    }

    func testRecordingBeforeTheFirstAudioBufferIsPreparing() {
        let content = LeisePillContent.resolve(LeisePillInputs(dictationState: .recording, isRecordingInputReady: false))

        XCTAssertEqual(content.phase, .preparing, "orange only once the microphone is live")
    }

    func testRecorderShowsItsElapsedTime() {
        let content = LeisePillContent.resolve(LeisePillInputs(
            dictationState: .idle,
            recorderState: .recording,
            recorderElapsed: 3725
        ))

        XCTAssertEqual(content.phase, .recording(elapsed: "1:02:05"))
        XCTAssertEqual(LeisePillFormat.elapsed(42), "0:42")
        XCTAssertEqual(LeisePillFormat.elapsed(724), "12:04")
    }

    func testDictationWinsOverTheRecorder() {
        let content = LeisePillContent.resolve(LeisePillInputs(dictationState: .processing, recorderState: .recording))

        XCTAssertEqual(content.phase, .processing)
    }

    func testInsertionNamesTheTargetApp() {
        let content = LeisePillContent.resolve(LeisePillInputs(
            dictationState: .inserting,
            insertionTarget: IndicatorInsertionTarget(appName: "Mail", bundleIdentifier: "com.apple.mail")
        ))

        XCTAssertEqual(content.phase, .message(LeisePillMessage(
            kind: .inserted,
            text: String(localized: "Inserted in \("Mail")"),
            appBundleIdentifier: "com.apple.mail"
        )))
    }

    func testInsertionIntoAnUnknownAppFallsBackToTextInserted() {
        let content = LeisePillContent.resolve(LeisePillInputs(
            dictationState: .inserting,
            insertionTarget: IndicatorInsertionTarget(appName: "  ", bundleIdentifier: nil)
        ))

        XCTAssertEqual(content.phase, .message(LeisePillMessage(kind: .inserted, text: String(localized: "Text inserted"))))
    }

    func testFeedbackKindsPickTheGlyph() {
        let cases: [(IndicatorFeedbackKind, LeisePillMessage.Kind)] = [
            (.success, .inserted),
            (.error, .error),
            (.cancelled, .cancelled),
            (.info, .info),
        ]
        for (kind, expected) in cases {
            let content = LeisePillContent.resolve(LeisePillInputs(
                dictationState: .inserting,
                feedbackMessage: "Message",
                feedbackIcon: "clock.arrow.circlepath",
                feedbackKind: kind,
                insertionTarget: IndicatorInsertionTarget(appName: "Mail", bundleIdentifier: "com.apple.mail")
            ))
            guard case let .message(message) = content.phase else {
                return XCTFail("expected a message for \(kind)")
            }
            XCTAssertEqual(message.kind, expected)
            XCTAssertEqual(message.text, "Message", "feedback replaces the insertion message")
            XCTAssertEqual(message.symbolName, kind == .info ? "clock.arrow.circlepath" : nil)
        }
    }

    func testUndoTitleTravelsWithTheMessage() {
        let content = LeisePillContent.resolve(LeisePillInputs(
            dictationState: .inserting,
            feedbackMessage: "Removed",
            feedbackUndoTitle: "Undo"
        ))

        guard case let .message(message) = content.phase else { return XCTFail("expected a message") }
        XCTAssertEqual(message.undoTitle, "Undo")
    }

    func testErrorStateBecomesAnErrorMessage() {
        let content = LeisePillContent.resolve(LeisePillInputs(dictationState: .error("Mikrofon getrennt")))

        XCTAssertEqual(content.phase, .message(LeisePillMessage(kind: .error, text: "Mikrofon getrennt")))
    }

    func testEscHintShowsOnlyWhileDictationCanBeCancelled() {
        let hint = String(localized: "Press Esc again to cancel")
        for state in [DictationViewModel.State.recording, .processing] {
            let content = LeisePillContent.resolve(LeisePillInputs(dictationState: state, cancelWarningMessage: hint))
            XCTAssertEqual(content.escHint, hint, "\(state)")
        }
        let inserting = LeisePillContent.resolve(LeisePillInputs(dictationState: .inserting, cancelWarningMessage: hint))
        XCTAssertNil(inserting.escHint)
    }

    func testHotkeyHintSpellsTheFnKeyLikeTheKeycap() {
        let fn = UnifiedHotkey(keyCode: 0, modifierFlags: 0, isFn: true)
        let toggle = UnifiedHotkey(keyCode: 49, modifierFlags: NSEvent.ModifierFlags.option.rawValue, isFn: false)

        XCTAssertEqual(
            LeisePillHotkeyHint.text(hybrid: [fn], pushToTalk: [], toggle: []),
            String(localized: "Hold \("fn") to talk")
        )
        XCTAssertEqual(
            LeisePillHotkeyHint.text(hybrid: [], pushToTalk: [], toggle: [toggle]),
            String(localized: "Press \(HotkeyService.displayName(for: toggle)) to talk")
        )
        XCTAssertEqual(
            LeisePillHotkeyHint.text(hybrid: [], pushToTalk: [], toggle: []),
            String(localized: "No dictation shortcut set")
        )
    }
}

// MARK: - Layout

final class LeisePillLayoutTests: XCTestCase {
    /// Ten points per character keeps the expectations independent of fonts.
    private func measure(_ text: String, _: LeisePillTypography.Style) -> CGFloat {
        CGFloat(text.count) * 10
    }

    func testIdleIsTheQuietBar() {
        let layout = LeisePillMetrics.layout(for: .idle, hoverHint: nil, measure: measure)

        XCTAssertEqual(layout.size, CGSize(width: 44, height: 14))
        XCTAssertNil(layout.glyphColumnWidth, "the bars sit centered")
    }

    func testHoverExpandsToAtLeastOneHundredFiftyPoints() {
        let short = LeisePillMetrics.layout(for: .idle, hoverHint: "fn", measure: measure)
        let long = LeisePillMetrics.layout(for: .idle, hoverHint: String(repeating: "x", count: 20), measure: measure)

        XCTAssertEqual(short.size, CGSize(width: 150, height: 30))
        XCTAssertEqual(long.size.width, LeisePillMetrics.hoverGlyphColumnWidth + 200 + LeisePillMetrics.trailingPadding)
    }

    func testListeningAndProcessingAreSixtyFourPointsWide() {
        for phase in [LeisePillPhase.listening, .preparing, .processing] {
            let layout = LeisePillMetrics.layout(for: LeisePillContent(phase: phase), hoverHint: "ignored", measure: measure)
            XCTAssertEqual(layout.size, CGSize(width: 64, height: 30), "\(phase)")
        }
    }

    func testEscHintWidensThePillWhileListening() {
        let content = LeisePillContent(phase: .listening, escHint: String(repeating: "x", count: 18))

        let layout = LeisePillMetrics.layout(for: content, hoverHint: nil, measure: measure)

        XCTAssertEqual(layout.size.width, LeisePillMetrics.glyphColumnWidth + 180 + LeisePillMetrics.trailingPadding)
        XCTAssertEqual(layout.trailingWidth, 180)
    }

    func testMessageMakesRoomForTheAppIconAndUndo() {
        let plain = LeisePillMetrics.layout(
            for: LeisePillContent(phase: .message(LeisePillMessage(kind: .error, text: "abcdefghij"))),
            hoverHint: nil,
            measure: measure
        )
        let withIcon = LeisePillMetrics.layout(
            for: LeisePillContent(phase: .message(LeisePillMessage(kind: .inserted, text: "abcdefghij", appBundleIdentifier: "com.apple.mail"))),
            hoverHint: nil,
            measure: measure
        )
        let withUndo = LeisePillMetrics.layout(
            for: LeisePillContent(phase: .message(LeisePillMessage(kind: .info, text: "abcdefghij", undoTitle: "Undo"))),
            hoverHint: nil,
            measure: measure
        )

        XCTAssertEqual(withIcon.size.width - plain.size.width, LeisePillMetrics.appIconSize + LeiseSpacing.s)
        XCTAssertEqual(withUndo.size.width - plain.size.width, LeiseSpacing.m + 40 + 2 * LeisePillMetrics.undoHorizontalPadding)
    }

    func testLongMessagesStopAtTheMaximumWidth() {
        let content = LeisePillContent(phase: .message(LeisePillMessage(kind: .error, text: String(repeating: "x", count: 80))))

        let layout = LeisePillMetrics.layout(for: content, hoverHint: nil, maxWidth: 340, measure: measure)

        XCTAssertEqual(layout.size.width, 340)
        XCTAssertEqual(layout.trailingWidth, 340 - LeisePillMetrics.glyphColumnWidth - LeisePillMetrics.trailingPadding)
    }

    func testRealTextMeasurementIsPositive() {
        XCTAssertGreaterThan(LeisePillTypography.width(of: "Keine Sprache erkannt", style: .message), 80)
        XCTAssertGreaterThan(LeisePillTypography.width(of: "12:04", style: .time), 20)
    }
}

// MARK: - Controller

@MainActor
final class LeisePillControllerTests: XCTestCase {
    private var controller: LeisePillController!
    private var pointer = CGPoint.zero
    private var committed: [IndicatorAnchor] = []
    private var clock: TimeInterval = 1000

    override func setUp() async throws {
        try await super.setUp()
        guard let screen = NSScreen.screens.first else {
            throw XCTSkip("Indicator pill tests need a display")
        }
        let controller = LeisePillController()
        controller.pointerLocation = { [unowned self] in pointer }
        controller.onAnchorCommitted = { [unowned self] in committed.append($0) }
        controller.present(inVisibleFrame: screen.visibleFrame, displayMode: .activeScreen)
        self.controller = controller
        settle()
    }

    override func tearDown() async throws {
        if let controller {
            controller.dismiss()
            settle()
        }
        controller = nil
        committed = []
        try await super.tearDown()
    }

    private func settle(frames: Int = 400) {
        for _ in 0 ..< frames {
            controller.step(by: 1.0 / 120)
        }
    }

    private func event(_ type: NSEvent.EventType, advance: TimeInterval = 0.008) -> NSEvent {
        clock += advance
        return NSEvent.mouseEvent(
            with: type,
            location: .zero,
            modifierFlags: [],
            timestamp: clock,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        )!
    }

    /// Drags the pill horizontally by `distance` in `steps` moves.
    private func drag(by distance: CGFloat, steps: Int = 12, release: Bool = true) {
        let start = CGPoint(x: controller.pillFrameOnScreen.midX, y: controller.pillFrameOnScreen.midY)
        pointer = start
        controller.pointerDown(event(.leftMouseDown))
        for index in 1 ... steps {
            pointer = CGPoint(x: start.x + distance * CGFloat(index) / CGFloat(steps), y: start.y)
            controller.pointerDragged(event(.leftMouseDragged))
        }
        if release {
            controller.pointerUp(event(.leftMouseUp))
        }
    }

    func testStripNeverTakesTheMouseAndThePointerWindowCoversOnlyThePill() {
        XCTAssertTrue(controller.isVisible)
        XCTAssertTrue(controller.stripIgnoresMouseEvents, "clicks around the pill reach the apps below")
        XCTAssertTrue(controller.hitPanelIsVisible)

        let pill = controller.pillFrameOnScreen
        let hit = controller.hitFrameOnScreen
        XCTAssertTrue(hit.insetBy(dx: -1, dy: -1).contains(pill))
        XCTAssertLessThan(hit.width, pill.width + 16)
        XCTAssertLessThan(hit.height, 40)
        XCTAssertLessThan(hit.width * hit.height, controller.stripFrameOnScreen.width * controller.stripFrameOnScreen.height / 20)
    }

    func testPillRestsAtTheCenterByDefault() {
        guard let screen = NSScreen.screens.first else { return }
        let expected = LeisePillPlacement.restingFrameOnScreen(
            anchor: .center,
            size: LeisePillMetrics.idleSize,
            visibleFrame: screen.visibleFrame
        )

        XCTAssertEqual(controller.pillFrameOnScreen.midX, expected.midX, accuracy: 0.5)
        XCTAssertEqual(controller.pillFrameOnScreen.minY, expected.minY, accuracy: 0.5)
    }

    func testSmallMovementIsAPressNotADrag() {
        let frame = controller.pillFrameOnScreen
        pointer = CGPoint(x: frame.midX, y: frame.midY)
        controller.pointerDown(event(.leftMouseDown))
        XCTAssertTrue(controller.model.isPressed)

        pointer.x += 2
        controller.pointerDragged(event(.leftMouseDragged))
        XCTAssertFalse(controller.model.isDragging, "under the 3 pt threshold")
        XCTAssertEqual(controller.pillFrameOnScreen, frame)

        controller.pointerUp(event(.leftMouseUp))
        XCTAssertFalse(controller.model.isPressed)
        XCTAssertTrue(committed.isEmpty)
    }

    func testDragFollowsThePointerOneToOneHorizontally() {
        let start = controller.pillFrameOnScreen
        drag(by: -120, release: false)

        XCTAssertTrue(controller.model.isDragging)
        XCTAssertEqual(controller.pillFrameOnScreen.midX, start.midX - 120, accuracy: 0.01)
        XCTAssertFalse(controller.model.anchorDots.isEmpty, "the three spots show while dragging")

        controller.pointerUp(event(.leftMouseUp, advance: 0.2))
    }

    func testVerticalDragRubberBandsAtMostSixPoints() {
        let start = controller.pillFrameOnScreen
        pointer = CGPoint(x: start.midX, y: start.midY)
        controller.pointerDown(event(.leftMouseDown))
        pointer.y += 200
        controller.pointerDragged(event(.leftMouseDragged))

        let lifted = controller.pillFrameOnScreen.minY - start.minY
        XCTAssertGreaterThan(lifted, 0)
        XCTAssertLessThan(lifted, LeisePillPlacement.verticalRubberBandLimit)

        controller.pointerUp(event(.leftMouseUp, advance: 0.2))
        settle()
        XCTAssertEqual(controller.pillFrameOnScreen.minY, start.minY, accuracy: 0.1, "springs back")
    }

    func testFlingSnapsToTheProjectedAnchorAndPersistsIt() {
        guard let screen = NSScreen.screens.first else { return }
        drag(by: -260, steps: 6)

        XCTAssertEqual(controller.currentAnchor, .left)
        XCTAssertEqual(committed, [.left])
        settle()
        let expected = LeisePillPlacement.restingFrameOnScreen(
            anchor: .left,
            size: LeisePillMetrics.idleSize,
            visibleFrame: screen.visibleFrame
        )
        XCTAssertEqual(controller.pillFrameOnScreen.minX, expected.minX, accuracy: 0.5)
        XCTAssertFalse(controller.model.isDragging)
    }

    func testCarefulDropNearHomeStaysHome() {
        let start = controller.pillFrameOnScreen
        drag(by: 60, release: false)
        // Rest before letting go: no velocity.
        controller.pointerUp(event(.leftMouseUp, advance: 0.3))

        XCTAssertEqual(controller.currentAnchor, .center)
        XCTAssertTrue(committed.isEmpty)
        settle()
        XCTAssertEqual(controller.pillFrameOnScreen.midX, start.midX, accuracy: 0.5)
    }

    func testEscDuringADragReturnsThePillToItsAnchor() {
        let start = controller.pillFrameOnScreen
        drag(by: 400, release: false)

        XCTAssertTrue(controller.cancelDragIfActive())
        XCTAssertFalse(controller.cancelDragIfActive(), "a second Esc is no longer the drag's")
        // Further movement is ignored until the button comes up.
        pointer.x += 200
        controller.pointerDragged(event(.leftMouseDragged))
        controller.pointerUp(event(.leftMouseUp))

        XCTAssertEqual(controller.currentAnchor, .center)
        XCTAssertTrue(committed.isEmpty)
        settle()
        XCTAssertEqual(controller.pillFrameOnScreen.midX, start.midX, accuracy: 0.5)
    }

    func testEscWithoutADragIsLeftToDictation() {
        XCTAssertFalse(controller.cancelDragIfActive())
    }

    func testGrabbingThePillMidFlightContinuesFromWhereItIs() {
        drag(by: -260, steps: 6)
        for _ in 0 ..< 6 {
            controller.step(by: 1.0 / 120)
        }
        let inFlight = controller.pillFrameOnScreen

        pointer = CGPoint(x: inFlight.midX, y: inFlight.midY)
        controller.pointerDown(event(.leftMouseDown))
        controller.step(by: 1.0 / 120)

        XCTAssertEqual(controller.pillFrameOnScreen.midX, inFlight.midX, accuracy: 0.01, "caught, not teleported")
        controller.pointerUp(event(.leftMouseUp, advance: 0.3))
    }

    func testPositionSettingMovesThePill() {
        guard let screen = NSScreen.screens.first else { return }
        controller.setAnchor(.right)
        settle()

        let expected = LeisePillPlacement.restingFrameOnScreen(
            anchor: .right,
            size: LeisePillMetrics.idleSize,
            visibleFrame: screen.visibleFrame
        )
        XCTAssertEqual(controller.pillFrameOnScreen.maxX, expected.maxX, accuracy: 0.5)
        XCTAssertTrue(committed.isEmpty, "a setting change is not reported back")
    }

    func testVoiceOverAdjustsThePosition() {
        controller.model.onAdjustAnchor?(1)
        XCTAssertEqual(controller.currentAnchor, .right)
        controller.model.onAdjustAnchor?(1)
        XCTAssertEqual(controller.currentAnchor, .right)
        controller.model.onAdjustAnchor?(-1)
        XCTAssertEqual(committed, [.right, .center])
    }

    func testListeningWidensThePillAndMessagesWidenFurther() {
        controller.setContent(LeisePillContent(phase: .listening), isDimmed: false)
        settle()
        XCTAssertEqual(controller.pillFrameOnScreen.size, CGSize(width: 64, height: 30))

        controller.setContent(
            LeisePillContent(phase: .message(LeisePillMessage(kind: .error, text: "Keine Sprache erkannt"))),
            isDimmed: false
        )
        settle()
        XCTAssertGreaterThan(controller.pillFrameOnScreen.width, 64)
        XCTAssertEqual(controller.model.shakeCount, LeiseMotion.systemReduceMotion ? 0 : 1, "errors shake once")
        XCTAssertTrue(controller.hitFrameOnScreen.contains(controller.pillFrameOnScreen))
    }

    func testDismissOrdersBothWindowsOutOnceThePillHasSunk() {
        controller.dismiss()
        XCTAssertFalse(controller.hitPanelIsVisible, "nothing to grab while it sinks")
        XCTAssertTrue(controller.isVisible, "still sinking")

        settle()

        XCTAssertFalse(controller.isVisible)
    }

    func testPresentDuringDismissalKeepsThePill() {
        guard let screen = NSScreen.screens.first else { return }
        controller.dismiss()
        controller.step(by: 1.0 / 120)
        controller.present(inVisibleFrame: screen.visibleFrame, displayMode: .activeScreen)
        settle()

        XCTAssertTrue(controller.isVisible)
        XCTAssertTrue(controller.hitPanelIsVisible)
        XCTAssertEqual(controller.model.presentationOpacity, 1, accuracy: 0.001)
    }

    func testDismissDuringADragWaitsForTheDrop() {
        drag(by: -40, release: false)
        controller.dismiss()
        XCTAssertTrue(controller.isVisible)

        controller.pointerUp(event(.leftMouseUp, advance: 0.3))
        settle()
        XCTAssertFalse(controller.isVisible)
    }
}
