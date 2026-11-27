import AppKit
import XCTest
@testable import Leise

/// An in-memory `AppleFnUsageType`, so no test touches the real preferences
/// of the Mac running it.
@MainActor
private final class FakeGlobeKeyPreferences: GlobeKeyPreferencesStoring {
    var storedValue: Int?
    var synchronizeSucceeds = true
    /// Simulates a write that the preferences daemon accepts but does not keep.
    var dropsWrites = false
    private(set) var writes: [Int] = []

    init(_ storedValue: Int?) {
        self.storedValue = storedValue
    }

    func readFnUsageType() -> Int? {
        storedValue
    }

    func writeFnUsageType(_ value: Int) -> Bool {
        writes.append(value)
        if !dropsWrites { storedValue = value }
        return synchronizeSucceeds
    }
}

/// Shortcuts a test can change after handing the loader to the service.
@MainActor
private final class HotkeyFixture {
    var hotkeys: [HotkeySlotType: [UnifiedHotkey]]

    init(hotkeys: [HotkeySlotType: [UnifiedHotkey]]) {
        self.hotkeys = hotkeys
    }
}

@MainActor
final class GlobeKeyServiceTests: XCTestCase {
    private let fn = UnifiedHotkey(keyCode: 0, modifierFlags: 0, isFn: true)
    private let optionSpace = UnifiedHotkey(
        keyCode: 49,
        modifierFlags: NSEvent.ModifierFlags.option.rawValue,
        isFn: false
    )

    private func makeService(
        fnUsageType: Int?,
        hotkeys: [HotkeySlotType: [UnifiedHotkey]]? = nil,
        notificationCenter: NotificationCenter = NotificationCenter(),
        openURL: @escaping (URL) -> Void = { _ in }
    ) -> (GlobeKeyService, FakeGlobeKeyPreferences) {
        let store = FakeGlobeKeyPreferences(fnUsageType)
        let configuredHotkeys = hotkeys ?? [.hybrid: [fn]]
        let service = GlobeKeyService(
            store: store,
            loadHotkeys: { configuredHotkeys[$0] ?? [] },
            openURL: openURL,
            notificationCenter: notificationCenter
        )
        return (service, store)
    }

    // MARK: Reading the setting

    func testMissingValueMeansTheSystemDefaultEmojiPickerAndConflicts() {
        let (service, _) = makeService(fnUsageType: nil)

        XCTAssertEqual(service.action, .showEmojiAndSymbols)
        XCTAssertEqual(service.conflict(), .showEmojiAndSymbols)
    }

    func testEachUsageTypeMapsToItsAction() {
        XCTAssertEqual(GlobeKeyAction(fnUsageType: 0), .doNothing)
        XCTAssertEqual(GlobeKeyAction(fnUsageType: 1), .changeInputSource)
        XCTAssertEqual(GlobeKeyAction(fnUsageType: 2), .showEmojiAndSymbols)
        XCTAssertEqual(GlobeKeyAction(fnUsageType: 3), .startDictation)
        XCTAssertEqual(GlobeKeyAction(fnUsageType: 9), .other(9))
    }

    func testOnlyDoNothingLeavesFnToLeise() {
        XCTAssertFalse(GlobeKeyAction.doNothing.interferesWithFnShortcut)
        for action: GlobeKeyAction in [.changeInputSource, .showEmojiAndSymbols, .startDictation, .other(9)] {
            XCTAssertTrue(action.interferesWithFnShortcut, "\(action)")
        }
    }

    func testDoNothingIsNoConflict() {
        let (service, _) = makeService(fnUsageType: 0)

        XCTAssertNil(service.conflict())
    }

    func testInputSourceAndDictationAreConflictsToo() {
        XCTAssertEqual(makeService(fnUsageType: 1).0.conflict(), .changeInputSource)
        XCTAssertEqual(makeService(fnUsageType: 3).0.conflict(), .startDictation)
    }

    // MARK: Reading the shortcut

    func testNoConflictWithoutAnFnDictationShortcut() {
        let (service, _) = makeService(fnUsageType: nil, hotkeys: [.hybrid: [optionSpace]])

        XCTAssertFalse(service.usesFnForDictation)
        XCTAssertNil(service.conflict())
    }

    func testFnInAnyDictationSlotCounts() {
        for slot: HotkeySlotType in [.hybrid, .pushToTalk, .toggle] {
            let (service, _) = makeService(fnUsageType: nil, hotkeys: [slot: [optionSpace, fn]])
            XCTAssertTrue(service.usesFnForDictation, "\(slot)")
        }
    }

    func testFnOnNonDictationShortcutsDoesNotCount() {
        let (service, _) = makeService(
            fnUsageType: nil,
            hotkeys: [.recentTranscriptions: [fn], .copyLastTranscription: [fn], .recorderToggle: [fn]]
        )

        XCTAssertNil(service.conflict())
    }

    func testDoubleTapFnStillConflicts() {
        let doubleTapFn = UnifiedHotkey(keyCode: 0, modifierFlags: 0, isFn: true, isDoubleTap: true)
        let (service, _) = makeService(fnUsageType: 2, hotkeys: [.toggle: [doubleTapFn]])

        XCTAssertEqual(service.conflict(), .showEmojiAndSymbols)
    }

    func testSetupCanCountFnBeforeItIsSaved() {
        let (service, _) = makeService(fnUsageType: nil, hotkeys: [:])

        XCTAssertNil(service.conflict())
        XCTAssertEqual(service.conflict(assumingFnShortcut: true), .showEmojiAndSymbols)
    }

    // MARK: Turning it off

    func testReadingNeverWrites() {
        let (service, store) = makeService(fnUsageType: nil)

        service.refresh()
        _ = service.conflict()
        _ = service.conflict(assumingFnShortcut: true)

        XCTAssertEqual(store.writes, [], "Only an explicit Abstellen may change the setting")
    }

    func testTurnOffWritesDoNothingAndConfirmsByReReading() {
        let (service, store) = makeService(fnUsageType: nil)

        XCTAssertEqual(service.turnOffGlobeKeyAction(), .fixed)

        XCTAssertEqual(store.writes, [GlobeKeyAction.doNothingRawValue])
        XCTAssertEqual(service.action, .doNothing)
        XCTAssertNil(service.conflict())
    }

    func testTurnOffFailsWhenSynchronizeFails() {
        let (service, store) = makeService(fnUsageType: 2)
        store.synchronizeSucceeds = false

        XCTAssertEqual(service.turnOffGlobeKeyAction(), .failed)
    }

    func testTurnOffFailsWhenTheValueDoesNotStick() {
        let (service, store) = makeService(fnUsageType: 2)
        store.dropsWrites = true

        XCTAssertEqual(service.turnOffGlobeKeyAction(), .failed)
        XCTAssertEqual(service.action, .showEmojiAndSymbols)
        XCTAssertNotNil(service.conflict())
    }

    func testTurnOffTellsOtherNoticesToReRead() {
        let center = NotificationCenter()
        let (service, _) = makeService(fnUsageType: nil, notificationCenter: center)
        let posted = expectation(forNotification: GlobeKeyService.didChangeNotification, object: service, notificationCenter: center)

        service.turnOffGlobeKeyAction()

        wait(for: [posted], timeout: 1)
    }

    func testFailedTurnOffDoesNotAnnounceAChange() {
        let center = NotificationCenter()
        let (service, store) = makeService(fnUsageType: 2, notificationCenter: center)
        store.dropsWrites = true
        let posted = expectation(forNotification: GlobeKeyService.didChangeNotification, object: service, notificationCenter: center)
        posted.isInverted = true

        service.turnOffGlobeKeyAction()

        wait(for: [posted], timeout: 0.2)
    }

    // MARK: System Settings

    func testSystemSettingsOpensKeyboardSettings() {
        var openedURLs: [URL] = []
        let (service, _) = makeService(fnUsageType: nil, openURL: { openedURLs.append($0) })

        service.openKeyboardSettings()

        XCTAssertEqual(openedURLs, [GlobeKeyService.keyboardSettingsURL])
        XCTAssertEqual(GlobeKeyService.keyboardSettingsURL.scheme, "x-apple.systempreferences")
        XCTAssertEqual(GlobeKeyService.keyboardSettingsURL.absoluteString, "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")
    }

    func testRefreshPicksUpAChangeMadeInSystemSettings() {
        let (service, store) = makeService(fnUsageType: nil)
        XCTAssertNotNil(service.conflict())

        store.storedValue = 0
        service.refresh()

        XCTAssertNil(service.conflict())
    }

    func testReturningToLeiseReReadsTheSetting() async throws {
        let center = NotificationCenter()
        let (service, store) = makeService(fnUsageType: nil, notificationCenter: center)
        service.startObserving()

        store.storedValue = 0
        center.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        try await Task.sleep(for: .milliseconds(400))

        XCTAssertEqual(service.action, .doNothing)
    }

    // MARK: Notice

    private func makeNotice(
        fnUsageType: Int?,
        hotkeys: [HotkeySlotType: [UnifiedHotkey]]? = nil,
        openURL: @escaping (URL) -> Void = { _ in }
    ) -> (GlobeKeyNoticeModel, FakeGlobeKeyPreferences) {
        let (service, store) = makeService(fnUsageType: fnUsageType, hotkeys: hotkeys, openURL: openURL)
        return (GlobeKeyNoticeModel(service: service, observesChanges: false), store)
    }

    func testNoticeShowsTheConflictRightAway() {
        let (notice, _) = makeNotice(fnUsageType: nil)

        XCTAssertEqual(notice.presentation(assumingFnShortcut: false), .conflict(.showEmojiAndSymbols, guidance: .none))
    }

    func testNoticeStaysHiddenWithoutAConflict() {
        XCTAssertEqual(makeNotice(fnUsageType: 0).0.presentation(assumingFnShortcut: true), .hidden)
        XCTAssertEqual(makeNotice(fnUsageType: nil, hotkeys: [:]).0.presentation(assumingFnShortcut: false), .hidden)
        XCTAssertEqual(
            makeNotice(fnUsageType: nil, hotkeys: [:]).0.presentation(assumingFnShortcut: true),
            .conflict(.showEmojiAndSymbols, guidance: .none)
        )
    }

    func testTurningOffConfirmsAndThenHides() async throws {
        let (notice, _) = makeNotice(fnUsageType: 2)

        notice.turnOff()

        XCTAssertEqual(notice.presentation(assumingFnShortcut: false), .done)
        try await Task.sleep(for: GlobeKeyNoticeModel.confirmationDuration + .milliseconds(300))
        XCTAssertEqual(notice.presentation(assumingFnShortcut: false), .hidden)
    }

    func testAFixInSystemSettingsIsConfirmedToo() {
        let (notice, store) = makeNotice(fnUsageType: 1)

        store.storedValue = 0
        notice.service.refresh()

        XCTAssertEqual(notice.presentation(assumingFnShortcut: false), .done)
    }

    func testSwitchingAwayFromFnHidesWithoutClaimingAFix() {
        let shortcuts = HotkeyFixture(hotkeys: [.hybrid: [fn]])
        let service = GlobeKeyService(
            store: FakeGlobeKeyPreferences(nil),
            loadHotkeys: { shortcuts.hotkeys[$0] ?? [] },
            openURL: { _ in },
            notificationCenter: NotificationCenter()
        )
        let notice = GlobeKeyNoticeModel(service: service, observesChanges: false)

        shortcuts.hotkeys = [.hybrid: [optionSpace]]
        service.refresh()

        XCTAssertEqual(notice.presentation(assumingFnShortcut: false), .hidden)
    }

    func testFailedTurnOffPointsToSystemSettings() {
        let (notice, store) = makeNotice(fnUsageType: 2)
        store.dropsWrites = true

        notice.turnOff()

        XCTAssertEqual(notice.presentation(assumingFnShortcut: false), .conflict(.showEmojiAndSymbols, guidance: .couldNotChange))
    }

    func testSystemSettingsButtonAddsTheInstruction() {
        var opened: [URL] = []
        let (notice, _) = makeNotice(fnUsageType: nil, openURL: { opened.append($0) })

        notice.openKeyboardSettings()

        XCTAssertEqual(opened, [GlobeKeyService.keyboardSettingsURL])
        XCTAssertEqual(notice.presentation(assumingFnShortcut: false), .conflict(.showEmojiAndSymbols, guidance: .openedSettings))
    }

    // MARK: Copy

    func testEveryConflictHasItsOwnSentence() {
        let actions: [GlobeKeyAction] = [.showEmojiAndSymbols, .changeInputSource, .startDictation, .other(9)]
        let messages = actions.map(\.conflictMessage)

        XCTAssertFalse(messages.contains(where: \.isEmpty))
        XCTAssertEqual(Set(messages).count, messages.count)
        XCTAssertTrue(messages.allSatisfy { $0.contains("🌐") })
        XCTAssertFalse(GlobeKeyAction.settingsInstruction.isEmpty)
    }
}
