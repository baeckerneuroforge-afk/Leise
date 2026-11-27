import AppKit
import SwiftUI

/// Audio: which microphone, which sounds, and what happens to other audio
/// while you dictate.
struct AudioSettingsPage: View {
    @ObservedObject private var dictation = ServiceContainer.shared.dictationViewModel
    @ObservedObject private var audioDevice = ServiceContainer.shared.audioDeviceService
    @State private var customSounds: [String] = SoundChoice.installedCustomSounds()

    private let soundService = ServiceContainer.shared.soundService

    var body: some View {
        SettingsPage(.audio) {
            Section {
                inputPicker
                levelRow
                MicrophoneStatusRows(audioDevice: audioDevice)
                FallbackMicrophonesGroup(audioDevice: audioDevice)
            } header: {
                Text(String(localized: "Microphone"))
            } footer: {
                Text(String(localized: "If a microphone goes away, Leise takes the next one on the list."))
            }

            Section {
                Toggle(SettingsRow.playSounds.title, isOn: $dictation.soundFeedbackEnabled)
                    .settingsRow(.playSounds)

                ForEach(SoundEvent.allCases, id: \.self) { event in
                    SoundEventPicker(event: event, soundService: soundService, customSounds: $customSounds)
                        .disabled(!dictation.soundFeedbackEnabled)
                }
            } header: {
                Text(String(localized: "Sounds"))
            }
            .onAppear {
                customSounds = SoundChoice.installedCustomSounds()
            }

            Section {
                Toggle(isOn: $dictation.mediaPauseEnabled) {
                    SettingsRowLabel(
                        title: SettingsRow.pauseMedia.title,
                        info: String(localized: "Pauses music and videos while you dictate and resumes them afterwards. Uses the macOS media controls, which not every app supports.")
                    )
                }
                .settingsRow(.pauseMedia)

                Toggle(SettingsRow.lowerOtherApps.title, isOn: $dictation.audioDuckingEnabled)
                    .settingsRow(.lowerOtherApps)

                LabeledContent {
                    HStack(spacing: LeiseSpacing.m) {
                        Image(systemName: "speaker.slash")
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        Slider(value: $dictation.audioDuckingLevel, in: 0...0.5, step: 0.05)
                            .frame(minWidth: 120, maxWidth: 180)
                            .accessibilityLabel(String(localized: "Volume while dictating"))
                            .accessibilityValue(duckingLevelText)
                        Text(duckingLevelText)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 40, alignment: .trailing)
                            .accessibilityHidden(true)
                    }
                } label: {
                    SettingsRowLabel(
                        title: String(localized: "Volume while dictating"),
                        info: String(localized: "The share of your current volume that other apps keep while you dictate. 0% mutes them.")
                    )
                }
                .disabled(!dictation.audioDuckingEnabled)
            } header: {
                Text(String(localized: "Media"))
            }
        }
        .onDisappear {
            if audioDevice.isPreviewActive {
                audioDevice.stopPreview()
            }
        }
    }

    private var duckingLevelText: String {
        dictation.audioDuckingLevel.formatted(.percent.precision(.fractionLength(0)))
    }

    // MARK: Microphone

    private var inputSelection: Binding<String?> {
        Binding(
            get: { audioDevice.selectedDeviceUID },
            set: { newValue in
                if let newValue {
                    audioDevice.selectInputDeviceAsPrimary(newValue)
                } else {
                    audioDevice.clearInputDevicePriorityList()
                }
            }
        )
    }

    private var inputPicker: some View {
        Picker(SettingsRow.microphone.title, selection: inputSelection) {
            Text(audioDevice.inputDevices.isEmpty
                ? String(localized: "No Microphone Available")
                : String(localized: "System Default")
            )
            .tag(nil as String?)
            if !audioDevice.inputDevices.isEmpty {
                Divider()
            }
            ForEach(audioDevice.inputDevices) { device in
                Text(audioDevice.displayName(for: device)).tag(device.uid as String?)
            }
        }
        .settingsRow(.microphone)
    }

    private var canTestMicrophone: Bool {
        audioDevice.isPreviewActive || (!dictation.needsMicPermission && !audioDevice.inputDevices.isEmpty)
    }

    private var levelRow: some View {
        LabeledContent {
            HStack(spacing: LeiseSpacing.m) {
                LevelMeter(
                    level: audioDevice.previewAudioLevel,
                    isActive: audioDevice.isPreviewActive,
                    tint: LeiseColor.live
                )
                Button(audioDevice.isPreviewActive ? String(localized: "Stop") : String(localized: "Test")) {
                    if audioDevice.isPreviewActive {
                        audioDevice.stopPreview()
                        AccessibilityNotification.Announcement(String(localized: "Microphone off")).post()
                    } else {
                        audioDevice.startPreview()
                        AccessibilityNotification.Announcement(String(localized: "Microphone on")).post()
                    }
                }
                .disabled(!canTestMicrophone)
            }
        } label: {
            SettingsRowLabel(
                title: SettingsRow.microphoneTest.title,
                subtitle: String(localized: "The microphone is only on while testing.")
            )
        }
        .settingsRow(.microphoneTest)
    }
}

// MARK: - Level meter

/// The input level as a row of thin bars: flat when nothing listens, Microphone
/// Orange while testing, Record Red while the recorder runs.
struct LevelMeter: View {
    let level: Float
    var isActive: Bool
    var tint: Color
    var barCount = 20

    private static let barWidth: CGFloat = 3
    private static let height: CGFloat = 26
    private static let restingHeight: CGFloat = 0.12

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 0.3 : nil, paused: !isActive)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: LeiseSpacing.xs) {
                ForEach(0..<barCount, id: \.self) { index in
                    Capsule()
                        .fill(fill(forBar: index))
                        .frame(width: Self.barWidth, height: Self.height * relativeHeight(forBar: index, time: time))
                }
            }
            .frame(height: Self.height)
        }
        .leiseAnimation(LeiseMotion.ui, value: isActive)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Input level"))
        .accessibilityValue(isActive
            ? clampedLevel.formatted(.percent.precision(.fractionLength(0)))
            : String(localized: "Off"))
    }

    private var clampedLevel: Double {
        Double(min(max(level, 0), 1))
    }

    private var idleFill: AnyShapeStyle {
        contrast == .increased ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.quaternary)
    }

    private func fill(forBar index: Int) -> AnyShapeStyle {
        guard isActive else { return idleFill }
        guard reduceMotion else { return AnyShapeStyle(tint) }
        // Reduce Motion: a still segment meter; only the number of lit bars changes.
        let lit = Int((clampedLevel * Double(barCount)).rounded())
        return index < lit ? AnyShapeStyle(tint) : idleFill
    }

    private func relativeHeight(forBar index: Int, time: Double) -> CGFloat {
        guard isActive else { return Self.restingHeight }
        guard !reduceMotion else { return 0.6 }
        let wobble = 0.55 + 0.45 * sin(time * 8 + Double(index) * 0.9)
        return CGFloat(min(max(Self.restingHeight + clampedLevel * wobble, 0.08), 1))
    }
}

// MARK: - Microphone status

/// Problems with the microphone, each as symbol plus words.
private struct MicrophoneStatusRows: View {
    @ObservedObject var audioDevice: AudioDeviceService

    /// How long the "microphone disconnected" notice stays.
    private static let disconnectNoticeHold: Duration = .seconds(5)

    var body: some View {
        if audioDevice.inputDevices.isEmpty {
            StatusLabel(kind: .error, text: String(localized: "No microphone connected. Connect one to choose or test it."))
        }

        if let message = audioDevice.selectedDeviceStatusMessage {
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
        }

        if let error = audioDevice.previewError {
            StatusLabel(kind: .error, text: error.localizedDescription)
        }

        if let name = audioDevice.disconnectedDeviceName {
            Label(
                String(localized: "Microphone disconnected. Leise uses the system default for now."),
                systemImage: "mic.slash"
            )
            .foregroundStyle(.secondary)
            .task(id: name) {
                try? await Task.sleep(for: Self.disconnectNoticeHold)
                if audioDevice.disconnectedDeviceName == name {
                    audioDevice.disconnectedDeviceName = nil
                }
            }
        }
    }
}

// MARK: - Backup microphones

private struct FallbackMicrophonesGroup: View {
    @ObservedObject var audioDevice: AudioDeviceService

    @State private var isExpanded = false
    @State private var draggedItem: AudioInputDevicePriorityItem?
    @Environment(\.settingsHighlightedRow) private var highlightedRow

    private var items: [AudioInputDevicePriorityItem] {
        audioDevice.inputDevicePriorityList
    }

    /// The list is worth showing once it holds more than the primary
    /// microphone, or when its only entry is disconnected.
    private var showsList: Bool {
        guard items.count == 1, let item = items.first else { return items.count > 1 }
        return !audioDevice.isInputDevicePriorityItemAvailable(item)
    }

    private var fallbackCount: Int {
        max(items.count - 1, 0)
    }

    private var disconnectedCount: Int {
        items.filter { !audioDevice.isInputDevicePriorityItemAvailable($0) }.count
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            if showsList {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    MicrophonePriorityRow(
                        index: index,
                        item: item,
                        audioDevice: audioDevice
                    )
                    .onDrag {
                        draggedItem = item
                        return NSItemProvider(object: item.uid as NSString)
                    }
                    .onDrop(
                        of: ["public.text"],
                        delegate: MicrophonePriorityDropDelegate(
                            item: item,
                            audioDevice: audioDevice,
                            draggedItem: $draggedItem
                        )
                    )
                }
            } else {
                Text(String(localized: "Add microphones Leise should use when your main one is missing."))
                    .foregroundStyle(.secondary)
            }

            HStack {
                if disconnectedCount > 1 {
                    Button(String(localized: "Remove Disconnected")) {
                        audioDevice.removeDisconnectedInputDevicePriorityItems()
                    }
                }
                Spacer()
                Menu {
                    ForEach(audioDevice.inputDevicePriorityCandidates) { device in
                        Button(audioDevice.displayName(for: device)) {
                            audioDevice.addInputDeviceToPriorityList(device)
                        }
                    }
                } label: {
                    Label(String(localized: "Add Backup Microphone"), systemImage: "plus")
                }
                .fixedSize()
                .disabled(audioDevice.inputDevicePriorityCandidates.isEmpty)
            }
        } label: {
            HStack {
                Text(SettingsRow.fallbackMicrophones.title)
                Spacer()
                if fallbackCount > 0 {
                    Text(fallbackCount.formatted())
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
        }
        .settingsRow(.fallbackMicrophones)
        .onChange(of: highlightedRow) { _, row in
            if row == .fallbackMicrophones {
                withLeiseAnimation(LeiseMotion.shape) { isExpanded = true }
            }
        }
    }
}

private struct MicrophonePriorityRow: View {
    let index: Int
    let item: AudioInputDevicePriorityItem
    @ObservedObject var audioDevice: AudioDeviceService

    private var isAvailable: Bool { audioDevice.isInputDevicePriorityItemAvailable(item) }
    private var canMoveUp: Bool { index > 0 }
    private var canMoveDown: Bool { index < audioDevice.inputDevicePriorityList.count - 1 }

    var body: some View {
        HStack(spacing: LeiseSpacing.s) {
            Text("\(index + 1).")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(minWidth: 20, alignment: .trailing)

            Text(audioDevice.displayName(for: item))
                .lineLimit(1)
                .truncationMode(.middle)

            if !isAvailable {
                Text(String(localized: "Disconnected"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: LeiseSpacing.s)

            Button {
                audioDevice.removeInputDevicePriorityItem(item)
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help(String(localized: "Forget microphone"))
            .accessibilityLabel(String(localized: "Forget microphone"))

            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button(String(localized: "Move Up"), action: moveUp)
                .disabled(!canMoveUp)
            Button(String(localized: "Move Down"), action: moveDown)
                .disabled(!canMoveDown)
        }
        .accessibilityElement(children: .combine)
        .modifier(MicrophonePriorityAccessibilityActions(
            canMoveUp: canMoveUp,
            canMoveDown: canMoveDown,
            moveUp: moveUp,
            moveDown: moveDown
        ))
    }

    private func moveUp() {
        guard let index = audioDevice.inputDevicePriorityList.firstIndex(of: item), index > 0 else { return }
        audioDevice.moveInputDevicePriorityItems(from: IndexSet(integer: index), to: index - 1)
    }

    private func moveDown() {
        guard let index = audioDevice.inputDevicePriorityList.firstIndex(of: item),
              index < audioDevice.inputDevicePriorityList.count - 1 else { return }
        audioDevice.moveInputDevicePriorityItems(from: IndexSet(integer: index), to: index + 2)
    }
}

private struct MicrophonePriorityAccessibilityActions: ViewModifier {
    let canMoveUp: Bool
    let canMoveDown: Bool
    let moveUp: () -> Void
    let moveDown: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if canMoveUp && canMoveDown {
            content
                .accessibilityAction(named: Text(String(localized: "Move Up")), moveUp)
                .accessibilityAction(named: Text(String(localized: "Move Down")), moveDown)
        } else if canMoveUp {
            content
                .accessibilityAction(named: Text(String(localized: "Move Up")), moveUp)
        } else if canMoveDown {
            content
                .accessibilityAction(named: Text(String(localized: "Move Down")), moveDown)
        } else {
            content
        }
    }
}

private struct MicrophonePriorityDropDelegate: DropDelegate {
    let item: AudioInputDevicePriorityItem
    let audioDevice: AudioDeviceService
    @Binding var draggedItem: AudioInputDevicePriorityItem?

    func dropEntered(info: DropInfo) {
        guard let draggedItem,
              draggedItem != item,
              let fromIndex = audioDevice.inputDevicePriorityList.firstIndex(of: draggedItem),
              let toIndex = audioDevice.inputDevicePriorityList.firstIndex(of: item) else { return }

        let destination = toIndex > fromIndex ? toIndex + 1 : toIndex
        withLeiseAnimation(LeiseMotion.shape) {
            audioDevice.moveInputDevicePriorityItems(from: IndexSet(integer: fromIndex), to: destination)
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedItem = nil
        return true
    }
}

// MARK: - Sounds

/// Start, Fertig, Fehler: which sound plays, with a preview button.
private struct SoundEventPicker: View {
    let event: SoundEvent
    let soundService: SoundService
    @Binding var customSounds: [String]
    @State private var selection: String

    private static let importTag = "import-custom-sound"

    init(event: SoundEvent, soundService: SoundService, customSounds: Binding<[String]>) {
        self.event = event
        self.soundService = soundService
        self._customSounds = customSounds
        self._selection = State(initialValue: soundService.choice(for: event).storageKey)
    }

    private var title: String {
        switch event {
        case .recordingStarted: String(localized: "Start")
        case .transcriptionSuccess: String(localized: "Done")
        case .error: String(localized: "Error")
        }
    }

    var body: some View {
        LabeledContent {
            HStack(spacing: LeiseSpacing.s) {
                Button {
                    soundService.preview(SoundChoice(storageKey: selection))
                } label: {
                    Image(systemName: "play.fill")
                }
                .buttonStyle(.borderless)
                .disabled(SoundChoice(storageKey: selection) == .none)
                .help(String(localized: "Listen to “\(title)”"))
                .accessibilityLabel(String(localized: "Listen to “\(title)”"))

                Picker(title, selection: $selection) {
                    Text(String(localized: "Leise (Default)")).tag(event.defaultChoice.storageKey)

                    Section {
                        ForEach(SoundChoice.bundledSounds.filter { $0.name != event.fileName }, id: \.name) { sound in
                            Text(sound.displayName).tag(SoundChoice.bundled(sound.name).storageKey)
                        }
                    } header: {
                        Text(verbatim: "Leise")
                    }

                    Section(String(localized: "Your Sounds")) {
                        ForEach(customSounds, id: \.self) { name in
                            Text(name).tag(SoundChoice.custom(name).storageKey)
                        }
                        Text(String(localized: "Custom Sound…")).tag(Self.importTag)
                    }

                    Section(String(localized: "System Sounds")) {
                        ForEach(SoundChoice.systemSounds, id: \.self) { name in
                            Text(name).tag(SoundChoice.system(name).storageKey)
                        }
                    }

                    Divider()
                    Text(String(localized: "No Sound")).tag(SoundChoice.none.storageKey)
                }
                .labelsHidden()
                .fixedSize()
            }
        } label: {
            Text(title)
        }
        .onChange(of: selection) { oldValue, newValue in
            if newValue == Self.importTag {
                selection = oldValue
                importCustomSound()
                return
            }
            let choice = SoundChoice(storageKey: newValue)
            soundService.updateChoice(for: event, choice: choice)
            soundService.preview(choice)
        }
    }

    private func importCustomSound() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = SoundChoice.allowedContentTypes
        panel.allowsMultipleSelection = false
        panel.message = String(localized: "Choose a sound file")
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            MainActor.assumeIsolated {
                do {
                    let filename = try soundService.importCustomSound(from: url)
                    customSounds = SoundChoice.installedCustomSounds()
                    selection = SoundChoice.custom(filename).storageKey
                } catch {
                    NSSound.beep()
                }
            }
        }
    }
}
