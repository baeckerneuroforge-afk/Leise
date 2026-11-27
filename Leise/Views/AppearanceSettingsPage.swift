import AppKit
import ServiceManagement
import SwiftUI

/// Darstellung: the indicator, and how Leise shows up as an app.
struct AppearanceSettingsPage: View {
    @AppStorage(UserDefaultsKeys.showMenuBarIcon) private var showsMenuBarIcon = true
    @AppStorage(UserDefaultsKeys.dockIconBehaviorWhenMenuBarHidden)
    private var dockIconBehaviorRawValue = DockIconBehavior.keepVisible.rawValue

    @State private var launchAtLogin = SMAppService.mainApp.status
    @State private var launchAtLoginError: String?
    @State private var appLanguage = AppLanguageChoice.current
    @State private var showsRestartAlert = false

    var body: some View {
        SettingsPage(.appearance) {
            IndicatorAppearanceSection()

            Section {
                Toggle(isOn: $showsMenuBarIcon) {
                    SettingsRowLabel(
                        title: SettingsRow.menuBarIcon.title,
                        subtitle: String(localized: "Without the icon, Leise appears in the Dock.")
                    )
                }
                .settingsRow(.menuBarIcon)

                if !showsMenuBarIcon {
                    Toggle(isOn: dockOnlyWhileWindowOpen) {
                        SettingsRowLabel(
                            title: String(localized: "In the Dock only while a window is open"),
                            info: String(localized: "Leise then shows no icon at all until you open it. To open it again, launch Leise from Spotlight or the Applications folder.")
                        )
                    }
                }

                launchAtLoginRow

                Picker(selection: $appLanguage) {
                    Text(AppLanguageChoice.system.title).tag(AppLanguageChoice.system)
                    Divider()
                    ForEach(AppLanguageChoice.languages) { choice in
                        Text(verbatim: choice.title).tag(choice)
                    }
                } label: {
                    SettingsRowLabel(
                        title: SettingsRow.appLanguage.title,
                        subtitle: String(localized: "Takes effect after Leise restarts.")
                    )
                }
                .settingsRow(.appLanguage)
                .onChange(of: appLanguage) { _, newValue in
                    newValue.apply()
                    showsRestartAlert = true
                }
            } header: {
                Text(String(localized: "App"))
            }
        }
        .alert(String(localized: "Restart Required"), isPresented: $showsRestartAlert) {
            Button(String(localized: "Restart Now"), action: restartApp)
            Button(String(localized: "Later"), role: .cancel) {}
        } message: {
            Text(String(localized: "The language change will take effect after restarting Leise."))
        }
    }

    // MARK: Dock

    private var dockOnlyWhileWindowOpen: Binding<Bool> {
        Binding(
            get: { dockIconBehaviorRawValue == DockIconBehavior.onlyWhileWindowOpen.rawValue },
            set: { onlyWhileOpen in
                dockIconBehaviorRawValue = (onlyWhileOpen ? DockIconBehavior.onlyWhileWindowOpen : .keepVisible).rawValue
            }
        )
    }

    // MARK: Launch at login

    @ViewBuilder
    private var launchAtLoginRow: some View {
        Toggle(SettingsRow.launchAtLogin.title, isOn: Binding(
            get: { launchAtLogin == .enabled || launchAtLogin == .requiresApproval },
            set: setLaunchAtLogin
        ))
        .settingsRow(.launchAtLogin)

        if launchAtLogin == .requiresApproval {
            LabeledContent {
                Button(String(localized: "Open Login Items…")) {
                    SMAppService.openSystemSettingsLoginItems()
                }
            } label: {
                StatusLabel(kind: .error, text: String(localized: "Allow Leise in Login Items first"))
            }
        } else if let launchAtLoginError {
            StatusLabel(kind: .error, text: launchAtLoginError)
        }
    }

    private func setLaunchAtLogin(_ enable: Bool) {
        do {
            if enable {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = error.localizedDescription
        }
        withLeiseAnimation(LeiseMotion.ui) {
            launchAtLogin = SMAppService.mainApp.status
        }
    }

    // MARK: Language

    private func restartApp() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            DispatchQueue.main.async {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}

/// The app's UI language: the system's, or one Leise is translated into.
enum AppLanguageChoice: Hashable, Identifiable {
    case system
    case language(String)

    static let languages: [AppLanguageChoice] = [.language("en"), .language("de"), .language("ja")]

    var id: String {
        switch self {
        case .system: "system"
        case .language(let code): code
        }
    }

    static var current: AppLanguageChoice {
        guard let code = UserDefaults.standard.string(forKey: UserDefaultsKeys.preferredAppLanguage),
              !code.isEmpty else {
            return .system
        }
        return .language(code)
    }

    /// Names in their own language, so everyone finds theirs.
    var title: String {
        switch self {
        case .system:
            let name = Self.nativeName(for: Self.systemLanguageCode)
            return String(localized: "Same as System (\(name))")
        case .language(let code):
            return Self.nativeName(for: code)
        }
    }

    func apply(defaults: UserDefaults = .standard) {
        switch self {
        case .system:
            defaults.removeObject(forKey: UserDefaultsKeys.preferredAppLanguage)
            defaults.removeObject(forKey: "AppleLanguages")
        case .language(let code):
            defaults.set(code, forKey: UserDefaultsKeys.preferredAppLanguage)
            defaults.set([code], forKey: "AppleLanguages")
        }
    }

    /// The language Leise would use without an override: the first system
    /// language it is translated into, else English.
    private static var systemLanguageCode: String {
        let global = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)
        let preferred = (global?["AppleLanguages"] as? [String]) ?? Locale.preferredLanguages
        for language in preferred {
            if language.hasPrefix("de") { return "de" }
            if language.hasPrefix("ja") { return "ja" }
            if language.hasPrefix("en") { return "en" }
        }
        return "en"
    }

    private static func nativeName(for code: String) -> String {
        Locale(identifier: code).localizedString(forLanguageCode: code)?.localizedCapitalized ?? code
    }
}
