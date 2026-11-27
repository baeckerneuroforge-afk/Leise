import AppKit
import XCTest
@testable import Leise

final class SettingsStructureTests: XCTestCase {
    // MARK: Sidebar

    func testSidebarHasExactlyNineEntries() {
        XCTAssertEqual(SettingsSidebarLayout.sections.flatMap(\.tabs).count, 9)
        XCTAssertEqual(SettingsTab.allCases.count, 9)
    }

    func testEveryTabAppearsInExactlyOneSection() {
        let placedTabs = SettingsSidebarLayout.sections.flatMap(\.tabs)

        XCTAssertEqual(placedTabs.count, Set(placedTabs).count, "a tab appears in more than one section")
        XCTAssertEqual(Set(placedTabs), Set(SettingsTab.allCases), "every tab must be reachable from the sidebar")
    }

    func testSidebarPutsWorkPagesFirstAndSettingsUnderOneHeader() {
        XCTAssertEqual(SettingsSidebarLayout.sections.map(\.id), ["work", "preferences"])
        XCTAssertEqual(SettingsSidebarLayout.workTabs, [.overview, .history, .dictionary, .transcribe])
        XCTAssertEqual(SettingsSidebarLayout.preferenceTabs, [.dictation, .apps, .audio, .appearance, .advanced])
        XCTAssertNil(SettingsSidebarLayout.title(forSection: "work"))
        XCTAssertEqual(SettingsSidebarLayout.title(forSection: "preferences"), String(localized: "Settings"))
    }

    func testEveryPageHasATitleAndASymbol() {
        for tab in SettingsTab.allCases {
            XCTAssertFalse(tab.title.isEmpty, "\(tab) has no title")
            XCTAssertNotNil(NSImage(systemSymbolName: tab.systemImage, accessibilityDescription: nil), "\(tab) uses an unknown symbol")
        }
    }

    func testPreRedesignTabNamesPointAtTheirNewPages() {
        XCTAssertEqual(SettingsTab.home, .overview)
        XCTAssertEqual(SettingsTab.dictationRecovery, .history)
    }

    // MARK: Search index

    func testEverySearchEntryPointsToASidebarPage() {
        let sidebarTabs = Set(SettingsSidebarLayout.sections.flatMap(\.tabs))
        for entry in SettingsSearchIndex.entries {
            XCTAssertTrue(sidebarTabs.contains(entry.page), "\(entry.row) points to \(entry.page), which the sidebar doesn't show")
            XCTAssertEqual(entry.page, entry.row.page)
            XCTAssertFalse(entry.title.isEmpty, "\(entry.row) has no title")
        }
    }

    func testEveryRowHasExactlyOneSearchEntry() {
        let rows = SettingsSearchIndex.entries.map(\.row)
        XCTAssertEqual(rows.count, Set(rows).count, "a row is indexed twice")
        XCTAssertEqual(Set(rows), Set(SettingsRow.allCases), "a row is missing from the index")
    }

    func testEveryPageCanBeFoundBySearch() {
        let indexedPages = Set(SettingsSearchIndex.entries.map(\.page))
        XCTAssertEqual(indexedPages, Set(SettingsTab.allCases))
    }

    func testSectionTargetsBelongToTheirPages() {
        for row in SettingsRow.allCases {
            if row.dictionarySection != nil {
                XCTAssertEqual(row.page, .dictionary, "\(row) opens a Wörterbuch section but lives on \(row.page)")
            }
            if row.transcribeMode != nil {
                XCTAssertEqual(row.page, .transcribe, "\(row) opens a Transkribieren mode but lives on \(row.page)")
            }
        }
        for section in DictionaryPageSection.allCases {
            XCTAssertTrue(SettingsRow.allCases.contains { $0.dictionarySection == section }, "no search result opens \(section)")
        }
        for mode in TranscribeMode.allCases {
            XCTAssertTrue(SettingsRow.allCases.contains { $0.transcribeMode == mode }, "no search result opens \(mode)")
        }
    }

    func testSearchFindsRowLabelsNotOnlyPageTitles() {
        for entry in SettingsSearchIndex.entries {
            let results = SettingsSearchIndex.results(for: entry.title)
            XCTAssertTrue(results.contains(entry), "searching “\(entry.title)” doesn't find its row")
        }
    }

    func testSearchIgnoresCaseAndDiacritics() {
        let entry = SettingsSearchEntry(row: .removeFillerWords, title: "Füllwörter entfernen", keywords: "äh ähm")
        let others = [SettingsSearchEntry(row: .playSounds, title: "Töne abspielen", keywords: "sound")]

        XCTAssertEqual(SettingsSearchIndex.results(for: "fullworter", in: [entry] + others), [entry])
        XCTAssertEqual(SettingsSearchIndex.results(for: "FÜLLWÖRTER", in: [entry] + others), [entry])
        XCTAssertEqual(SettingsSearchIndex.results(for: "ah", in: [entry] + others), [entry])
    }

    func testSearchRequiresEveryWordAndRanksLabelMatchesFirst() {
        let keywordMatch = SettingsSearchEntry(row: .lowerOtherApps, title: "Andere Apps leiser stellen", keywords: "lautstärke ducking")
        let titleMatch = SettingsSearchEntry(row: .microphoneTest, title: "Lautstärke testen", keywords: "")
        let entries = [keywordMatch, titleMatch]

        XCTAssertEqual(SettingsSearchIndex.results(for: "lautstärke", in: entries), [titleMatch, keywordMatch])
        XCTAssertEqual(SettingsSearchIndex.results(for: "lautstärke ducking", in: entries), [keywordMatch])
        XCTAssertEqual(SettingsSearchIndex.results(for: "   ", in: entries), [])
    }

    // MARK: Navigation

    @MainActor
    func testNavigationHelpersOpenTheNewPages() {
        let coordinator = SettingsNavigationCoordinator()

        coordinator.showOverview()
        XCTAssertEqual(coordinator.request?.tab, .overview)

        coordinator.showDictationSettings()
        XCTAssertEqual(coordinator.request?.tab, .dictation)

        coordinator.showHistory()
        XCTAssertEqual(coordinator.request?.tab, .history)
        XCTAssertNil(coordinator.request?.row)

        coordinator.showRecovery()
        XCTAssertEqual(coordinator.request?.tab, .history)
        XCTAssertEqual(coordinator.request?.row, .recovery)
    }

    @MainActor
    func testHandledRequestIsNotReplayed() throws {
        let coordinator = SettingsNavigationCoordinator()
        coordinator.show(.fillerWordList)
        let request = try XCTUnwrap(coordinator.request)
        XCTAssertEqual(request.tab, .dictionary)

        coordinator.navigate(to: .audio)
        coordinator.didHandle(request)
        XCTAssertEqual(coordinator.request?.tab, .audio, "an older request must not clear a newer one")

        let newer = try XCTUnwrap(coordinator.request)
        coordinator.didHandle(newer)
        XCTAssertNil(coordinator.request)
    }

    @MainActor
    func testRevealingARowOpensItsPageAndSection() {
        let state = SettingsWindowState()

        state.reveal(.termPacks)
        XCTAssertEqual(state.selection, .dictionary)
        XCTAssertEqual(state.dictionarySection, .termPacks)
        XCTAssertEqual(state.focusRequest?.row, .termPacks)

        state.reveal(.fileTranscription)
        XCTAssertEqual(state.selection, .transcribe)
        XCTAssertEqual(state.transcribeMode, .file)

        state.select(.audio)
        XCTAssertEqual(state.selection, .audio)
        XCTAssertNil(state.focusRequest, "a sidebar click must not flash a stale row")
    }

    @MainActor
    func testRevealingTheSameRowAgainFlashesAgain() throws {
        let state = SettingsWindowState()
        state.reveal(.playSounds)
        let first = try XCTUnwrap(state.focusRequest)
        state.reveal(.playSounds)
        let second = try XCTUnwrap(state.focusRequest)
        XCTAssertNotEqual(first.id, second.id)
    }

    // MARK: Sounds

    func testSoundsStartOffForANewInstall() throws {
        let defaults = try makeDefaults()

        SoundService.storeFeedbackDefaultIfNeeded(in: defaults)

        XCTAssertEqual(defaults.object(forKey: UserDefaultsKeys.soundFeedbackEnabled) as? Bool, false)
    }

    func testSoundsStayOnForAnInstallThatNeverChangedThem() throws {
        let defaults = try makeDefaults()
        defaults.set(true, forKey: UserDefaultsKeys.setupWizardCompleted)

        SoundService.storeFeedbackDefaultIfNeeded(in: defaults)

        XCTAssertTrue(defaults.bool(forKey: UserDefaultsKeys.soundFeedbackEnabled))
    }

    func testStoredSoundChoiceIsKept() throws {
        let defaults = try makeDefaults()
        defaults.set(true, forKey: UserDefaultsKeys.setupWizardCompleted)
        defaults.set(false, forKey: UserDefaultsKeys.soundFeedbackEnabled)

        SoundService.storeFeedbackDefaultIfNeeded(in: defaults)
        XCTAssertFalse(defaults.bool(forKey: UserDefaultsKeys.soundFeedbackEnabled))

        defaults.set(true, forKey: UserDefaultsKeys.soundFeedbackEnabled)
        SoundService.storeFeedbackDefaultIfNeeded(in: defaults)
        XCTAssertTrue(defaults.bool(forKey: UserDefaultsKeys.soundFeedbackEnabled))
    }

    // MARK: Helpers

    private func makeDefaults() throws -> UserDefaults {
        let name = "SettingsStructureTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        addTeardownBlock {
            UserDefaults(suiteName: name)?.removePersistentDomain(forName: name)
        }
        return defaults
    }
}
