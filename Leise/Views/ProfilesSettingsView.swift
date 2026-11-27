import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Apps: rules for single apps or websites. They apply as soon as the app is
/// in front.
struct ProfilesSettingsView: View {
    @ObservedObject private var viewModel = ServiceContainer.shared.profilesViewModel
    @ObservedObject private var settings = ServiceContainer.shared.settingsViewModel

    var body: some View {
        SettingsPage(.apps) {
            Section {
                if viewModel.profiles.isEmpty {
                    VStack(alignment: .leading, spacing: LeiseSpacing.xs) {
                        Text(String(localized: "No rules yet"))
                            .font(.headline)
                        Text(String(localized: "For example: always English in Xcode, or press Return after inserting in Messages."))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, LeiseSpacing.xs)
                } else {
                    ForEach(viewModel.profiles) { profile in
                        AppRuleRow(
                            profile: profile,
                            summary: AppRuleSummary.text(for: profile),
                            isEnabled: Binding(
                                get: { profile.isEnabled },
                                set: { viewModel.setEnabled($0, for: profile) }
                            ),
                            edit: { viewModel.startEditing(profile) },
                            delete: { viewModel.delete(profile) }
                        )
                    }
                }
            } header: {
                Text(String(localized: "Your own rules for single apps or websites. They apply as soon as the app is in front."))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .textCase(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, LeiseSpacing.xs)
            } footer: {
                AddAppMenu(
                    excluding: Set(viewModel.profiles.flatMap(\.bundleIdentifiers)),
                    pickApp: { app in viewModel.prepareNewProfile(app: app.bundleIdentifier, name: app.name) },
                    pickWebsite: { viewModel.prepareNewProfile() }
                )
                .padding(.top, LeiseSpacing.s)
            }
        }
        .sheet(isPresented: $viewModel.showingEditor) {
            AppRuleEditor(viewModel: viewModel, languages: settings.availableLanguages)
        }
    }
}

// MARK: - Row

private struct AppRuleRow: View {
    let profile: Profile
    let summary: String
    @Binding var isEnabled: Bool
    let edit: () -> Void
    let delete: () -> Void

    var body: some View {
        HStack(spacing: LeiseSpacing.m) {
            AppRuleGlyph(profile: profile)
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.name)
                    .lineLimit(1)
                Text(summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture(count: 2, perform: edit)

            Button(action: edit) {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            .help(String(localized: "Edit"))
            .accessibilityLabel(String(localized: "Edit “\(profile.name)”"))

            Toggle(isOn: $isEnabled) {
                Text(String(localized: "“\(profile.name)” active"))
            }
            .toggleStyle(.switch)
            .labelsHidden()
        }
        .opacity(isEnabled ? 1 : 0.6)
        .leiseAnimation(LeiseMotion.ui, value: isEnabled)
        .contextMenu {
            Button(String(localized: "Edit…"), action: edit)
            Divider()
            Button(String(localized: "Delete"), role: .destructive, action: delete)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(profile.name)
    }
}

/// The app's real icon, a globe for website rules, a neutral tile for a
/// rule that applies everywhere.
private struct AppRuleGlyph: View {
    let profile: Profile

    var body: some View {
        if let bundleIdentifier = profile.bundleIdentifiers.first {
            AppGlyph(bundleIdentifier: bundleIdentifier, size: 22)
        } else {
            Image(systemName: profile.urlPatterns.isEmpty ? "square.dashed" : "globe")
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: LeiseRadius.control, style: .continuous))
                .accessibilityHidden(true)
        }
    }
}

/// "Sprache: Englisch · Nach dem Einfügen Return drücken".
enum AppRuleSummary {
    @MainActor
    static func text(for profile: Profile) -> String {
        var parts: [String] = []

        if profile.bundleIdentifiers.count > 1 {
            parts.append(profile.bundleIdentifiers.dropFirst().map(InstalledApp.name(for:)).formatted(.list(type: .and)))
        }
        if !profile.urlPatterns.isEmpty {
            parts.append(profile.urlPatterns.formatted(.list(type: .and)))
        }
        switch profile.inputLanguageSelection {
        case .inheritGlobal:
            break
        case .auto:
            parts.append(String(localized: "Language: detect automatically"))
        case .exact(let code):
            parts.append(String(localized: "Language: \(localizedAppLanguageName(for: code))"))
        case .hints(let codes):
            parts.append(String(localized: "Language: \(codes.map(localizedAppLanguageName(for:)).formatted(.list(type: .and)))"))
        }
        switch profile.outputFormat {
        case "plainText": parts.append(String(localized: "Plain text"))
        case "markdown": parts.append(String(localized: "Markdown"))
        default: break
        }
        if profile.autoEnterEnabled {
            parts.append(String(localized: "Press Return after inserting"))
        }
        if let hotkey = profile.hotkey {
            parts.append(String(localized: "Shortcut \(HotkeyService.displayName(for: hotkey))"))
        }

        if parts.isEmpty {
            return profile.bundleIdentifiers.isEmpty && profile.urlPatterns.isEmpty
                ? String(localized: "Applies to every app without its own rule")
                : String(localized: "Like the default · click to adjust")
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Picking apps

/// An app a rule can point at.
struct InstalledApp: Identifiable, Hashable {
    let bundleIdentifier: String
    let name: String

    var id: String { bundleIdentifier }

    /// Apps with a Dock icon that are running now, by name.
    @MainActor
    static func running(excluding excluded: Set<String>) -> [InstalledApp] {
        let ownBundleIdentifier = Bundle.main.bundleIdentifier
        var seen = Set<String>()
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> InstalledApp? in
                guard let bundleIdentifier = app.bundleIdentifier,
                      bundleIdentifier != ownBundleIdentifier,
                      !excluded.contains(bundleIdentifier),
                      seen.insert(bundleIdentifier).inserted else { return nil }
                return InstalledApp(bundleIdentifier: bundleIdentifier, name: app.localizedName ?? name(for: bundleIdentifier))
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    @MainActor
    static func name(for bundleIdentifier: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return bundleIdentifier
        }
        return appName(at: url)
    }

    static func appName(at url: URL) -> String {
        let name = FileManager.default.displayName(atPath: url.path)
        return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }

    /// A small copy of the app icon for menus.
    @MainActor
    static func menuIcon(for bundleIdentifier: String) -> NSImage {
        let icon = (AppGlyph.icon(for: bundleIdentifier).copy() as? NSImage) ?? NSImage()
        icon.size = NSSize(width: 16, height: 16)
        return icon
    }

    /// Lets the user pick any app from the Applications folder.
    @MainActor
    static func chooseFromApplications(completion: @escaping @MainActor (InstalledApp) -> Void) {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = String(localized: "Choose")
        panel.begin { response in
            guard response == .OK,
                  let url = panel.url,
                  let bundleIdentifier = Bundle(url: url)?.bundleIdentifier else { return }
            MainActor.assumeIsolated {
                completion(InstalledApp(bundleIdentifier: bundleIdentifier, name: appName(at: url)))
            }
        }
    }
}

/// "App hinzufügen …": running apps with their icons, any other app, or a website.
private struct AddAppMenu: View {
    let excluding: Set<String>
    let pickApp: @MainActor (InstalledApp) -> Void
    var pickWebsite: (@MainActor () -> Void)?

    var body: some View {
        Menu {
            let running = InstalledApp.running(excluding: excluding)
            if !running.isEmpty {
                Section(String(localized: "Open Apps")) {
                    ForEach(running) { app in
                        Button {
                            pickApp(app)
                        } label: {
                            Label {
                                Text(app.name)
                            } icon: {
                                Image(nsImage: InstalledApp.menuIcon(for: app.bundleIdentifier))
                            }
                        }
                    }
                }
                Divider()
            }
            Button(String(localized: "Other App…")) {
                InstalledApp.chooseFromApplications(completion: pickApp)
            }
            if let pickWebsite {
                Button(String(localized: "Website…"), action: pickWebsite)
            }
        } label: {
            Label(String(localized: "Add App…"), systemImage: "plus")
        }
        .fixedSize()
    }
}

// MARK: - Editor

private struct AppRuleEditor: View {
    @ObservedObject var viewModel: ProfilesViewModel
    let languages: [(code: String, name: String)]

    @State private var showsDeleteConfirmation = false
    @FocusState private var isNameFocused: Bool

    private var isNew: Bool { viewModel.editingProfile == nil }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    ForEach(viewModel.editorApps, id: \.self) { bundleIdentifier in
                        HStack(spacing: LeiseSpacing.m) {
                            AppGlyph(bundleIdentifier: bundleIdentifier, size: 22)
                            Text(InstalledApp.name(for: bundleIdentifier))
                            Spacer()
                            Button {
                                viewModel.removeEditorApp(bundleIdentifier)
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel(String(localized: "Remove \(InstalledApp.name(for: bundleIdentifier))"))
                        }
                    }

                    AddAppMenu(
                        excluding: Set(viewModel.editorApps),
                        pickApp: { app in viewModel.addEditorApp(app.bundleIdentifier, name: app.name) }
                    )

                    LabeledContent {
                        TextField(
                            String(localized: "Websites"),
                            text: $viewModel.editorURLPatterns,
                            prompt: Text(verbatim: "intranet.example.com"),
                            axis: .vertical
                        )
                        .labelsHidden()
                        .lineLimit(1...4)
                        .multilineTextAlignment(.trailing)
                    } label: {
                        SettingsRowLabel(
                            title: String(localized: "Websites"),
                            subtitle: String(localized: "One domain per line")
                        )
                    }
                } header: {
                    Text(String(localized: "Applies To"))
                } footer: {
                    if viewModel.editorApps.isEmpty && viewModel.editorURLPatterns.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(String(localized: "Without apps or websites, the rule applies to every app that has no rule of its own."))
                    }
                }

                Section {
                    TextField(String(localized: "Name"), text: $viewModel.editorName)
                        .focused($isNameFocused)

                    SpokenLanguagePicker(
                        selection: $viewModel.editorLanguage,
                        languages: languages,
                        inheritTitle: String(localized: "Same as Dictation")
                    ) {
                        Text(String(localized: "Language"))
                    }

                    Picker(String(localized: "Output format"), selection: $viewModel.editorOutputFormat) {
                        Text(String(localized: "Automatic")).tag("")
                        Text(String(localized: "Plain text")).tag("plainText")
                        Text(String(localized: "Markdown")).tag("markdown")
                    }

                    Toggle(String(localized: "Press Return after inserting"), isOn: $viewModel.editorAutoEnterEnabled)

                    LabeledContent {
                        HotkeyRecorderView(
                            label: viewModel.editorHotkey.map(HotkeyService.displayName(for:)) ?? "",
                            title: String(localized: "Own shortcut"),
                            presentation: viewModel.editorHotkey == nil
                                ? .pushButton(title: String(localized: "Set…"))
                                : .compactChip,
                            onRecord: { viewModel.editorHotkey = $0 },
                            onClear: { viewModel.editorHotkey = nil }
                        )
                    } label: {
                        SettingsRowLabel(
                            title: String(localized: "Own shortcut"),
                            info: String(localized: "Dictating with this shortcut always uses this rule, whichever app is in front.")
                        )
                    }

                    Toggle(String(localized: "Active"), isOn: $viewModel.editorEnabled)
                } header: {
                    Text(String(localized: "Rule"))
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                if !isNew {
                    Button(String(localized: "Delete Rule…"), role: .destructive) {
                        showsDeleteConfirmation = true
                    }
                }
                Spacer()
                Button(String(localized: "Cancel"), role: .cancel) {
                    viewModel.showingEditor = false
                }
                .keyboardShortcut(.cancelAction)
                Button(isNew ? String(localized: "Add Rule") : String(localized: "Save")) {
                    viewModel.saveEditor()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!viewModel.isEditorValid)
            }
            .padding(LeiseSpacing.l)
        }
        .frame(width: 560, height: 600)
        .onAppear {
            if viewModel.editorName.isEmpty {
                isNameFocused = true
            }
        }
        .confirmationDialog(
            String(localized: "Delete “\(viewModel.editorName)”?"),
            isPresented: $showsDeleteConfirmation
        ) {
            Button(String(localized: "Delete Rule"), role: .destructive) {
                viewModel.deleteEditingProfile()
            }
        } message: {
            Text(String(localized: "Dictation in this app then uses your normal settings again."))
        }
    }
}
