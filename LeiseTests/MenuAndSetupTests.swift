import AppKit
import LeiseCore
import ParakeetEngine
import XCTest
@testable import Leise

// MARK: - Setup steps

final class SetupWizardStepTests: XCTestCase {
    func testSetupHasFourSteps() {
        XCTAssertEqual(SetupWizardStep.allCases, [.welcome, .access, .shortcut, .tryIt])
        XCTAssertEqual(SetupWizardStep.allCases.map(\.number), [1, 2, 3, 4])
    }

    func testSavedStepsFromTheFiveStepWizardLandOnTryIt() {
        XCTAssertEqual(SetupWizardStep.restored(fromSavedIndex: 0), .welcome)
        XCTAssertEqual(SetupWizardStep.restored(fromSavedIndex: 2), .shortcut)
        // The old "AI & Engine" (3) and "Finish" (4) steps are gone.
        XCTAssertEqual(SetupWizardStep.restored(fromSavedIndex: 3), .tryIt)
        XCTAssertEqual(SetupWizardStep.restored(fromSavedIndex: 4), .tryIt)
        XCTAssertEqual(SetupWizardStep.restored(fromSavedIndex: -2), .welcome)
        XCTAssertEqual(SetupWizardStep.restored(fromSavedIndex: 99), .tryIt)
    }

    func testStepsKnowTheirNeighbors() {
        XCTAssertNil(SetupWizardStep.welcome.previous)
        XCTAssertEqual(SetupWizardStep.welcome.next, .access)
        XCTAssertEqual(SetupWizardStep.tryIt.previous, .shortcut)
        XCTAssertNil(SetupWizardStep.tryIt.next)
    }

    func testStepsSlideInFromTheDirectionOfTravel() {
        XCTAssertEqual(SetupTravel.forward.edgeSign, 1)
        XCTAssertEqual(SetupTravel.backward.edgeSign, -1)
        XCTAssertEqual(SetupTravel.inPlace.edgeSign, 0)
    }
}

final class SetupPrimaryActionTests: XCTestCase {
    private func resolve(_ step: SetupWizardStep, mic: Bool = false, ax: Bool = false) -> SetupPrimaryAction {
        SetupPrimaryAction.resolve(step: step, microphoneGranted: mic, accessibilityGranted: ax)
    }

    func testFooterButtonFollowsTheSteps() {
        XCTAssertEqual(resolve(.welcome), .begin)
        XCTAssertEqual(resolve(.shortcut, mic: true, ax: true), .next)
        XCTAssertEqual(resolve(.tryIt), .finish)
    }

    func testAccessAsksForTheMicrophoneFirst() {
        XCTAssertEqual(resolve(.access), .allowMicrophone)
        XCTAssertTrue(SetupPrimaryAction.allowMicrophone.isProminent)
        XCTAssertFalse(SetupPrimaryAction.accessibilityRowIsPrimary(microphoneGranted: false, accessibilityGranted: false))
    }

    func testWithOnlyTheMicrophoneTheFooterOffersLaterAndTheRowLeads() {
        XCTAssertEqual(resolve(.access, mic: true), .later)
        XCTAssertFalse(SetupPrimaryAction.later.isProminent)
        XCTAssertTrue(SetupPrimaryAction.accessibilityRowIsPrimary(microphoneGranted: true, accessibilityGranted: false))
    }

    func testWithBothPermissionsTheFooterContinues() {
        XCTAssertEqual(resolve(.access, mic: true, ax: true), .next)
        XCTAssertFalse(SetupPrimaryAction.accessibilityRowIsPrimary(microphoneGranted: true, accessibilityGranted: true))
    }
}

// MARK: - Model chip and choice

final class SetupModelChipTests: XCTestCase {
    private let v2 = SetupWizardParakeetRecommendation.v2ModelId
    private let v3 = SetupWizardParakeetRecommendation.v3ModelId

    private func chip(
        supported: Bool = true,
        ready: Bool = false,
        selected: String? = nil,
        status: ModelPreparationStatus? = .idle,
        activity: ParakeetModelActivity? = nil,
        didFail: Bool = false
    ) -> SetupModelChip {
        SetupModelChip.resolve(
            isSupported: supported,
            engineReady: ready,
            selectedModelID: selected,
            status: status,
            activity: activity,
            didFail: didFail
        )
    }

    func testDownloadShowsTheFractionOfTheMultilingualModel() {
        let resolved = chip(activity: .downloading(modelID: v3, fractionCompleted: 0.64))

        XCTAssertEqual(resolved.phase, .downloading(fractionCompleted: 0.64))
        XCTAssertEqual(resolved.barFraction, 0.64)
        XCTAssertTrue(resolved.showsBar)
        XCTAssertTrue(resolved.text.contains(0.64.formatted(.percent.precision(.fractionLength(0)))))
        XCTAssertNotEqual(resolved.text, chip(activity: .downloading(modelID: v2, fractionCompleted: 0.64)).text)
    }

    func testFractionIsClamped() {
        XCTAssertEqual(chip(activity: .downloading(modelID: v3, fractionCompleted: 1.7)).barFraction, 1)
        XCTAssertEqual(chip(activity: .downloading(modelID: v3, fractionCompleted: -1)).barFraction, 0)
    }

    func testLoadingAfterTheDownloadIsIndeterminate() {
        let resolved = chip(activity: .loading(modelID: v3))

        XCTAssertEqual(resolved.phase, .preparing)
        XCTAssertNil(resolved.barFraction)
        XCTAssertTrue(resolved.showsBar)
    }

    func testReadyNamesTheModel() {
        let resolved = chip(ready: true, selected: v3, status: .ready)

        XCTAssertTrue(resolved.isReady)
        XCTAssertFalse(resolved.showsBar)
        XCTAssertTrue(resolved.text.contains("Parakeet v3"))
    }

    func testReadyWinsOverStaleActivity() {
        XCTAssertTrue(chip(ready: true, selected: v3, activity: .loading(modelID: v3)).isReady)
    }

    func testFailuresAndUnsupportedMacsHaveTheirOwnStates() {
        XCTAssertEqual(chip(status: .failed(message: "offline")).phase, .failed)
        XCTAssertEqual(chip(status: .idle, didFail: true).phase, .failed)
        XCTAssertEqual(chip(supported: false).phase, .unsupported)
        XCTAssertEqual(chip().phase, .starting)
        XCTAssertEqual(chip(status: .preparing(message: "Downloading model", progress: 0.3)).phase, .preparing)
    }

    func testSetupKeepsAWorkingChoiceAndUpgradesEnglishOnlyWhenNeeded() {
        XCTAssertEqual(SetupModelChoice.targetModelID(currentModelID: nil, recommendedModelID: v3), v3)
        XCTAssertEqual(SetupModelChoice.targetModelID(currentModelID: nil, recommendedModelID: v2), v2)
        XCTAssertEqual(SetupModelChoice.targetModelID(currentModelID: v2, recommendedModelID: v3), v3)
        XCTAssertEqual(SetupModelChoice.targetModelID(currentModelID: v3, recommendedModelID: v2), v3)
        XCTAssertEqual(SetupModelChoice.targetModelID(currentModelID: v2, recommendedModelID: v2), v2)
    }

    func testModelNamesAreShort() {
        XCTAssertEqual(ParakeetModelNaming.shortName(forModelID: v3), "Parakeet v3")
        XCTAssertEqual(ParakeetModelNaming.shortName(forModelID: v2), "Parakeet v2")
        XCTAssertNil(ParakeetModelNaming.shortName(forModelID: "other"))
        XCTAssertTrue(ParakeetModelNaming.isMultilingual(modelID: v3))
        XCTAssertFalse(ParakeetModelNaming.isMultilingual(modelID: v2))
    }
}

final class ParakeetDefaultModelTests: XCTestCase {
    private let v2 = SetupWizardParakeetRecommendation.v2ModelId
    private let v3 = SetupWizardParakeetRecommendation.v3ModelId

    func testIDsMatchTheSetupRecommendation() {
        XCTAssertEqual(ParakeetDefaultModel.englishModelID, v2)
        XCTAssertEqual(ParakeetDefaultModel.multilingualModelID, v3)
    }

    func testGermanMacsGetTheMultilingualModel() {
        XCTAssertEqual(ParakeetDefaultModel.modelID(forPreferredLanguages: ["de-DE"]), v3)
        XCTAssertEqual(ParakeetDefaultModel.modelID(forPreferredLanguages: ["de"]), v3)
    }

    func testASecondEuropeanLanguageAlsoChoosesV3() {
        XCTAssertEqual(ParakeetDefaultModel.modelID(forPreferredLanguages: ["en-US", "de-DE"]), v3)
        XCTAssertEqual(ParakeetDefaultModel.modelID(forPreferredLanguages: ["en-GB", "fr-FR"]), v3)
        XCTAssertEqual(ParakeetDefaultModel.modelID(forPreferredLanguages: ["pt-BR"]), v3)
    }

    func testEnglishAloneKeepsV2() {
        XCTAssertEqual(ParakeetDefaultModel.modelID(forPreferredLanguages: ["en-US"]), v2)
        XCTAssertEqual(ParakeetDefaultModel.modelID(forPreferredLanguages: ["en-GB", "en-AU"]), v2)
        XCTAssertEqual(ParakeetDefaultModel.modelID(forPreferredLanguages: []), v2)
    }

    func testLanguagesNeitherModelCoversKeepV2() {
        XCTAssertEqual(ParakeetDefaultModel.modelID(forPreferredLanguages: ["ja-JP"]), v2)
        XCTAssertEqual(ParakeetDefaultModel.modelID(forPreferredLanguages: ["en-US", "zh-Hans-CN"]), v2)
    }
}

// MARK: - Shortcut

final class SetupShortcutDisplayTests: XCTestCase {
    private let fn = UnifiedHotkey(keyCode: 0, modifierFlags: 0, isFn: true)
    private let optionSpace = UnifiedHotkey(keyCode: 49, modifierFlags: NSEvent.ModifierFlags.option.rawValue, isFn: false)

    func testFreshInstallShowsFnAsPending() {
        let display = SetupShortcutDisplay.resolve(hotkeys: [:], recommendedApplies: true)

        XCTAssertEqual(display.label, "fn")
        XCTAssertTrue(display.isFn)
        XCTAssertTrue(display.isPending)
        XCTAssertTrue(display.isHeld)
        XCTAssertTrue(display.isConfigured)
    }

    func testSavedShortcutsWinInTriggerOrder() {
        let display = SetupShortcutDisplay.resolve(
            hotkeys: [.toggle: [fn], .hybrid: [optionSpace]],
            recommendedApplies: false
        )

        XCTAssertEqual(display.label, HotkeyService.displayName(for: optionSpace))
        XCTAssertFalse(display.isFn)
        XCTAssertFalse(display.isPending)
    }

    func testToggleShortcutsArePressedNotHeld() {
        let display = SetupShortcutDisplay.resolve(hotkeys: [.toggle: [fn]], recommendedApplies: false)

        XCTAssertFalse(display.isHeld)
        XCTAssertNotEqual(display.tryItInstruction, SetupShortcutDisplay.resolve(hotkeys: [.hybrid: [fn]], recommendedApplies: false).tryItInstruction)
    }

    func testMissingShortcutIsReported() {
        let display = SetupShortcutDisplay.resolve(hotkeys: [:], recommendedApplies: false)

        XCTAssertFalse(display.isConfigured)
        XCTAssertFalse(display.tryItInstruction.contains("fn"))
    }

    func testPlainFnReadsLikeTheKeycap() {
        XCTAssertEqual(SetupShortcutDisplay.displayLabel(for: fn), "fn")
        let doubleTap = UnifiedHotkey(keyCode: 0, modifierFlags: 0, isFn: true, isDoubleTap: true)
        XCTAssertEqual(SetupShortcutDisplay.displayLabel(for: doubleTap), HotkeyService.displayName(for: doubleTap))
    }

    func testInstructionNamesTheKey() {
        let display = SetupShortcutDisplay.resolve(hotkeys: [.hybrid: [optionSpace]], recommendedApplies: false)

        XCTAssertTrue(display.tryItInstruction.contains(display.label))
    }
}

@MainActor
final class FnKeyPressObserverTests: XCTestCase {
    func testFollowsOnlyTheFnKey() {
        let observer = FnKeyPressObserver()

        observer.handle(keyCode: FnKeyPressObserver.functionKeyCode, modifierFlags: .function)
        XCTAssertTrue(observer.isPressed)

        observer.handle(keyCode: 0x38, modifierFlags: [.function, .shift])
        XCTAssertTrue(observer.isPressed, "Other modifiers do not release fn")

        observer.handle(keyCode: FnKeyPressObserver.functionKeyCode, modifierFlags: [])
        XCTAssertFalse(observer.isPressed)
    }

    func testStopReleasesTheKey() {
        let observer = FnKeyPressObserver()
        observer.handle(keyCode: FnKeyPressObserver.functionKeyCode, modifierFlags: .function)

        observer.stop()

        XCTAssertFalse(observer.isPressed)
    }
}

// MARK: - Menu status

final class MenuBarStatusTests: XCTestCase {
    private let v3 = SetupWizardParakeetRecommendation.v3ModelId
    private let hold = MenuBarShortcutHint(label: "fn", isHeld: true)

    private func model(
        ready: Bool = false,
        preparing: Bool = false,
        fraction: Double? = nil,
        onDemand: Bool = false
    ) -> MenuBarModelSnapshot {
        MenuBarModelSnapshot(
            isReady: ready,
            isPreparing: preparing,
            downloadFraction: fraction,
            loadsOnDemand: onDemand,
            modelID: v3,
            displayName: "Parakeet TDT v3"
        )
    }

    private func status(
        paused: Bool = false,
        state: DictationViewModel.State = .idle,
        model: MenuBarModelSnapshot,
        shortcut: MenuBarShortcutHint? = MenuBarShortcutHint(label: "fn", isHeld: true)
    ) -> MenuBarStatus {
        MenuBarStatus.resolve(hotkeysPaused: paused, dictationState: state, model: model, shortcut: shortcut)
    }

    func testReadyNamesTheModelAndTheShortcut() {
        let resolved = status(model: model(ready: true))

        XCTAssertEqual(resolved.kind, .ready)
        XCTAssertTrue(resolved.title.contains("Parakeet v3"))
        XCTAssertEqual(resolved.subtitle, hold.text)
        XCTAssertTrue(resolved.subtitle.contains("fn"))
    }

    func testAModelOnDiskCountsAsReady() {
        XCTAssertEqual(status(model: model(onDemand: true)).kind, .ready)
    }

    func testLoadingShowsTheDownloadPercentage() {
        let resolved = status(model: model(preparing: true, fraction: 0.4))

        XCTAssertEqual(resolved.kind, .loading)
        XCTAssertTrue(resolved.subtitle.contains(0.4.formatted(.percent.precision(.fractionLength(0)))))
    }

    func testNoModel() {
        XCTAssertEqual(status(model: model()).kind, .noModel)
    }

    func testPausedBeatsTheModelState() {
        XCTAssertEqual(status(paused: true, model: model(ready: true)).kind, .paused)
    }

    func testActiveDictationIsReported() {
        XCTAssertEqual(status(state: .recording, model: model(ready: true)).kind, .listening)
        XCTAssertEqual(status(state: .processing, model: model(ready: true)).kind, .writing)
        XCTAssertEqual(status(state: .inserting, model: model(ready: true)).kind, .ready)
    }

    func testHintsFollowTheShortcutMode() {
        XCTAssertNotEqual(MenuBarShortcutHint(label: "fn", isHeld: true).text, MenuBarShortcutHint(label: "fn", isHeld: false).text)
        XCTAssertNotEqual(status(model: model(ready: true), shortcut: nil).subtitle, hold.text)
    }

    func testShortcutHintUsesTheFirstTriggerSlot() {
        let fn = UnifiedHotkey(keyCode: 0, modifierFlags: 0, isFn: true)
        let control = UnifiedHotkey(keyCode: 11, modifierFlags: NSEvent.ModifierFlags.control.rawValue, isFn: false)

        let hint = MenuBarShortcutHint.resolve { slot in
            switch slot {
            case .toggle: [control]
            case .hybrid: [fn]
            default: []
            }
        }
        XCTAssertEqual(hint, MenuBarShortcutHint(label: "fn", isHeld: true))

        let toggleOnly = MenuBarShortcutHint.resolve { $0 == .toggle ? [control] : [] }
        XCTAssertEqual(toggleOnly?.isHeld, false)
        XCTAssertNil(MenuBarShortcutHint.resolve { _ in [] })
    }

    func testShortNameFallsBackToTheModelName() {
        var snapshot = model()
        snapshot.modelID = nil
        XCTAssertEqual(snapshot.shortName, "Parakeet TDT v3")
        snapshot.displayName = nil
        XCTAssertEqual(snapshot.shortName, "Parakeet")
    }
}

@MainActor
final class MenuBarImagesTests: XCTestCase {
    func testEveryMenuSymbolUsesTheSameSlot() {
        for name in ["record.circle", "doc.text", "clock.arrow.circlepath", "gearshape", nil] as [String?] {
            let image = MenuItemSymbol.image(name)
            XCTAssertEqual(image.size, MenuItemSymbol.slotSize, name ?? "empty slot")
            XCTAssertTrue(image.isTemplate)
        }
    }

    func testStatusTileKeepsItsColors() {
        for kind: MenuBarStatus.Kind in [.ready, .loading, .noModel, .paused, .listening, .writing] {
            let image = MenuBarStatusTile.image(for: kind)
            XCTAssertEqual(image.size, MenuBarStatusTile.size)
            XCTAssertFalse(image.isTemplate)
        }
    }

    func testGlyphDescriptionNamesEveryActiveState() {
        let idle = MenuBarGlyphModel.describe(dictationState: .idle, recorderState: .idle)
        let both = MenuBarGlyphModel.describe(dictationState: .recording, recorderState: .recording)

        XCTAssertNotEqual(idle, both)
        XCTAssertTrue(both.contains(MenuBarGlyphModel.describe(dictationState: .recording, recorderState: .idle)))
    }

    func testAboutCreditsStateLicenseAndOrigin() {
        XCTAssertTrue(LeiseAboutPanel.credits.contains("GPL-3.0"))
        XCTAssertTrue(LeiseAboutPanel.credits.contains("TypeWhisper"))
    }
}

// MARK: - Recent transcriptions palette

@MainActor
private final class CopyingPaletteControllerSpy: SelectionPaletteControlling {
    private(set) var isVisible = false
    private(set) var lastConfiguration: SelectionPaletteConfiguration?
    private(set) var lastItems: [SelectionPaletteItem] = []
    private var onSelect: ((SelectionPaletteItem) -> Void)?
    private var onCopy: ((SelectionPaletteItem) -> Void)?

    func show(
        configuration: SelectionPaletteConfiguration,
        items: [SelectionPaletteItem],
        onSelect: @escaping (SelectionPaletteItem) -> Void
    ) {
        show(configuration: configuration, items: items, onSelect: onSelect, onCopy: nil)
    }

    func show(
        configuration: SelectionPaletteConfiguration,
        items: [SelectionPaletteItem],
        onSelect: @escaping (SelectionPaletteItem) -> Void,
        onCopy: ((SelectionPaletteItem) -> Void)?
    ) {
        isVisible = true
        lastConfiguration = configuration
        lastItems = items
        self.onSelect = onSelect
        self.onCopy = onCopy
    }

    func hide() {
        isVisible = false
    }

    func copy(_ item: SelectionPaletteItem) {
        onCopy?(item)
    }
}

@MainActor
final class RecentTranscriptionPaletteTests: XCTestCase {
    private func makeHandler() throws -> (RecentTranscriptionPaletteHandler, RecentTranscriptionStore, CopyingPaletteControllerSpy, URL) {
        let directory = try TestSupport.makeTemporaryDirectory()
        let spy = CopyingPaletteControllerSpy()
        let store = RecentTranscriptionStore()
        let handler = RecentTranscriptionPaletteHandler(
            textInsertionService: TextInsertionService(),
            historyService: HistoryService(appSupportDirectory: directory),
            recentTranscriptionStore: store,
            paletteController: spy
        )
        return (handler, store, spy, directory)
    }

    func testRowsCarryTheAppIconAndTime() throws {
        let (handler, store, spy, directory) = try makeHandler()
        defer { TestSupport.remove(directory) }
        let timestamp = Date()
        store.recordTranscription(
            id: UUID(),
            finalText: "Danke für das Gespräch heute.",
            timestamp: timestamp,
            appName: "Mail",
            appBundleIdentifier: "com.apple.mail"
        )

        handler.triggerSelection(currentState: .idle)

        let item = try XCTUnwrap(spy.lastItems.first)
        XCTAssertEqual(item.appBundleIdentifier, "com.apple.mail")
        XCTAssertEqual(item.subtitle, "Mail")
        XCTAssertEqual(item.detail, RecentTranscriptionPaletteHandler.timeLabel(for: timestamp, relativeTo: Date()))
        XCTAssertTrue(item.accessibilityText.contains("Mail"))
    }

    func testPaletteIsSearchableWithKeyHints() throws {
        let (handler, store, spy, directory) = try makeHandler()
        defer { TestSupport.remove(directory) }
        store.recordTranscription(id: UUID(), finalText: "Hallo", timestamp: Date(), appName: nil, appBundleIdentifier: nil)

        handler.triggerSelection(currentState: .idle)

        let configuration = try XCTUnwrap(spy.lastConfiguration)
        XCTAssertTrue(configuration.showsSearchField)
        XCTAssertEqual(configuration.footerHints.map(\.key), ["↩", "⌘C", "esc"])
        XCTAssertEqual(configuration.titleLineLimit, 2)
        XCTAssertNotNil(configuration.noMatchesTitle)
    }

    func testCopyPutsTheEntryOnTheClipboardAndConfirms() throws {
        let (handler, store, spy, directory) = try makeHandler()
        defer { TestSupport.remove(directory) }
        let pasteboard = NSPasteboard.withUniqueName()
        handler.pasteboardProvider = { pasteboard }
        var feedback: String?
        handler.onShowNotchFeedback = { message, _, _, _, _ in feedback = message }
        store.recordTranscription(id: UUID(), finalText: "  Kopier mich  ", timestamp: Date(), appName: nil, appBundleIdentifier: nil)

        handler.triggerSelection(currentState: .idle)
        spy.copy(try XCTUnwrap(spy.lastItems.first))

        XCTAssertEqual(pasteboard.string(forType: .string), "Kopier mich")
        XCTAssertEqual(feedback, String(localized: "Copied to clipboard"))
    }

    func testOlderEntriesShowTheDayInsteadOfTheTime() {
        let now = Date()
        let calendar = Calendar.current
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now) ?? now

        XCTAssertEqual(
            RecentTranscriptionPaletteHandler.timeLabel(for: now, relativeTo: now),
            now.formatted(date: .omitted, time: .shortened)
        )
        XCTAssertNotEqual(
            RecentTranscriptionPaletteHandler.timeLabel(for: yesterday, relativeTo: now),
            yesterday.formatted(date: .omitted, time: .shortened)
        )
    }
}

@MainActor
final class SelectionPaletteSpotlightTests: XCTestCase {
    private let items = [
        SelectionPaletteItem(id: UUID(), title: "Danke für das Gespräch", subtitle: "Mail", searchTokens: ["Mail", "com.apple.mail"]),
        SelectionPaletteItem(id: UUID(), title: "Fasse die Entscheidungen zusammen", subtitle: "Safari", searchTokens: ["Safari"]),
    ]

    private func configuration() -> SelectionPaletteConfiguration {
        SelectionPaletteConfiguration(searchPrompt: "Search", emptyStateTitle: "Empty", noMatchesTitle: "No matches")
    }

    private func keyEvent(keyCode: UInt16, characters: String, modifierFlags: NSEvent.ModifierFlags = []) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifierFlags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode
        ))
    }

    func testCommandCCopiesTheSelection() throws {
        var copied: SelectionPaletteItem?
        let model = SelectionPaletteInteractionModel(
            configuration: configuration(),
            items: items,
            onSelect: { _ in XCTFail("⌘C must not insert") },
            onDismiss: {},
            onCopy: { copied = $0 }
        )

        XCTAssertTrue(model.perform(.moveDown))
        XCTAssertTrue(model.handleKeyDown(try keyEvent(keyCode: 8, characters: "c", modifierFlags: .command)))

        XCTAssertEqual(copied, items[1])
        XCTAssertEqual(model.searchText, "", "⌘C is not typed into the search")
    }

    func testCopyWithoutHandlerIsNotConsumed() {
        let model = SelectionPaletteInteractionModel(configuration: configuration(), items: items, onSelect: { _ in }, onDismiss: {})

        XCTAssertFalse(model.copySelection())
    }

    func testFieldCommandsMoveAcceptAndClose() {
        var inserted: SelectionPaletteItem?
        var dismissed = false
        let model = SelectionPaletteInteractionModel(
            configuration: configuration(),
            items: items,
            onSelect: { inserted = $0 },
            onDismiss: { dismissed = true }
        )

        _ = model.perform(.moveUp)
        XCTAssertEqual(model.selectedIndex, 1)
        _ = model.perform(.accept)
        XCTAssertEqual(inserted, items[1])
        _ = model.perform(.cancel)
        XCTAssertTrue(dismissed)
    }

    func testClickSelectsAndDoubleClickInserts() {
        var inserted: SelectionPaletteItem?
        let model = SelectionPaletteInteractionModel(configuration: configuration(), items: items, onSelect: { inserted = $0 }, onDismiss: {})

        model.highlight(items[1])
        XCTAssertEqual(model.selectedIndex, 1)
        XCTAssertNil(inserted)

        model.selectItem(items[1])
        XCTAssertEqual(inserted, items[1])
    }

    func testSearchMatchesTheAppAndReportsNoMatches() {
        let model = SelectionPaletteInteractionModel(configuration: configuration(), items: items, onSelect: { _ in }, onDismiss: {})

        model.searchText = "  safari "
        XCTAssertEqual(model.filteredItems, [items[1]])

        model.searchText = "xyz"
        XCTAssertTrue(model.filteredItems.isEmpty)
        XCTAssertEqual(model.emptyStateTitle, "No matches")
        XCTAssertNil(model.selectedItem)
        XCTAssertEqual(model.filteredItems(for: "mail"), [items[0]])
    }

    func testPanelGrowsWithResultsUpToFiveRows() {
        let configuration = SelectionPaletteConfiguration(
            panelWidth: 540,
            panelHeight: .greatestFiniteMagnitude,
            titleLineLimit: 2,
            searchPrompt: "Search",
            emptyStateTitle: "Empty",
            footerHints: [SelectionPaletteHint(key: "↩", label: "Insert")]
        )
        let one = SelectionPaletteMetrics.height(rowCount: 1, configuration: configuration)
        let five = SelectionPaletteMetrics.height(rowCount: 5, configuration: configuration)
        let fifty = SelectionPaletteMetrics.height(rowCount: 50, configuration: configuration)
        let none = SelectionPaletteMetrics.height(rowCount: 0, configuration: configuration)

        XCTAssertLessThan(one, five)
        XCTAssertEqual(five, fifty, "Beyond five rows the list scrolls")
        XCTAssertGreaterThan(none, 0)
        XCTAssertLessThan(none, five)
    }
}
