import AppKit
import Combine
import SwiftUI

// A Spotlight-like palette: a search field on top, results with the app's
// icon and two lines of text, and a footer with the keys. ↑↓ select, ↩
// inserts, ⌘C copies, Esc closes. The panel never activates Leise, so the
// app you were typing in keeps focus and receives the inserted text.

struct SelectionPaletteItem: Identifiable, Equatable {
    let id: UUID
    let title: String
    let subtitle: String?
    let iconSystemName: String?
    let searchTokens: [String]
    /// The app the text came from; its icon leads the row.
    let appBundleIdentifier: String?
    /// Short trailing metadata, such as the time.
    let detail: String?

    init(
        id: UUID,
        title: String,
        subtitle: String? = nil,
        iconSystemName: String? = nil,
        searchTokens: [String] = [],
        appBundleIdentifier: String? = nil,
        detail: String? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.iconSystemName = iconSystemName
        self.searchTokens = searchTokens
        self.appBundleIdentifier = appBundleIdentifier
        self.detail = detail
    }

    /// What VoiceOver reads for the row.
    var accessibilityText: String {
        [title, subtitle, detail].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

/// A key and what it does, for the footer.
struct SelectionPaletteHint: Hashable {
    let key: String
    let label: String
}

struct SelectionPaletteConfiguration: Equatable {
    let panelWidth: CGFloat
    let panelHeight: CGFloat
    let previewText: String?
    let previewLineLimit: Int
    let titleLineLimit: Int
    let searchPrompt: String?
    let searchAccessibilityLabel: String?
    let emptyStateTitle: String
    /// Shown when entries exist but none matches the search.
    let noMatchesTitle: String?
    let footerHints: [SelectionPaletteHint]

    init(
        panelWidth: CGFloat = 380,
        panelHeight: CGFloat = 400,
        previewText: String? = nil,
        previewLineLimit: Int = 3,
        titleLineLimit: Int = 1,
        searchPrompt: String? = nil,
        searchAccessibilityLabel: String? = nil,
        emptyStateTitle: String,
        noMatchesTitle: String? = nil,
        footerHints: [SelectionPaletteHint] = []
    ) {
        self.panelWidth = panelWidth
        self.panelHeight = panelHeight
        self.previewText = previewText
        self.previewLineLimit = previewLineLimit
        self.titleLineLimit = titleLineLimit
        self.searchPrompt = searchPrompt
        self.searchAccessibilityLabel = searchAccessibilityLabel
        self.emptyStateTitle = emptyStateTitle
        self.noMatchesTitle = noMatchesTitle
        self.footerHints = footerHints
    }

    var showsSearchField: Bool { searchPrompt != nil }
}

/// Heights shared by the SwiftUI layout and the panel frame, so the panel
/// grows and shrinks with the results while its top edge stays put.
enum SelectionPaletteMetrics {
    static let searchBarHeight: CGFloat = 54
    static let searchFontSize: CGFloat = 19
    static let footerHeight: CGFloat = 36
    static let previewHeight: CGFloat = 64
    static let rowSpacing: CGFloat = 2
    static let listPadding: CGFloat = 6
    static let emptyStateHeight: CGFloat = 64
    static let maximumVisibleRows = 5
    static let hairline: CGFloat = 1
    static let iconSize: CGFloat = 22

    static func rowHeight(titleLineLimit: Int) -> CGFloat {
        // Body text runs about 16 pt per line; rows keep 8 pt above and below.
        CGFloat(max(titleLineLimit, 1)) * 16 + LeiseSpacing.s * 2
    }

    static func height(rowCount: Int, configuration: SelectionPaletteConfiguration) -> CGFloat {
        var height: CGFloat = 0
        if configuration.previewText != nil { height += previewHeight + hairline }
        if configuration.showsSearchField { height += searchBarHeight + hairline }
        if rowCount == 0 {
            height += emptyStateHeight
        } else {
            let visibleRows = min(rowCount, maximumVisibleRows)
            height += CGFloat(visibleRows) * rowHeight(titleLineLimit: configuration.titleLineLimit)
                + CGFloat(visibleRows - 1) * rowSpacing
                + listPadding * 2
        }
        if !configuration.footerHints.isEmpty { height += hairline + footerHeight }
        return min(height, configuration.panelHeight)
    }
}

@MainActor
protocol SelectionPaletteControlling: AnyObject {
    var isVisible: Bool { get }
    func show(
        configuration: SelectionPaletteConfiguration,
        items: [SelectionPaletteItem],
        onSelect: @escaping (SelectionPaletteItem) -> Void
    )
    /// `onCopy` runs for ⌘C; controllers without copy support insert-only.
    func show(
        configuration: SelectionPaletteConfiguration,
        items: [SelectionPaletteItem],
        onSelect: @escaping (SelectionPaletteItem) -> Void,
        onCopy: ((SelectionPaletteItem) -> Void)?
    )
    func hide()
}

extension SelectionPaletteControlling {
    func show(
        configuration: SelectionPaletteConfiguration,
        items: [SelectionPaletteItem],
        onSelect: @escaping (SelectionPaletteItem) -> Void,
        onCopy: ((SelectionPaletteItem) -> Void)?
    ) {
        show(configuration: configuration, items: items, onSelect: onSelect)
    }
}

/// Keyboard commands the search field forwards instead of editing text.
enum SelectionPaletteCommand {
    case moveUp
    case moveDown
    case accept
    case cancel
}

@MainActor
final class SelectionPaletteInteractionModel: ObservableObject {
    let configuration: SelectionPaletteConfiguration

    @Published var searchText = "" {
        didSet {
            if searchText != oldValue {
                selectedIndex = 0
            }
        }
    }
    @Published private(set) var selectedIndex = 0

    private let items: [SelectionPaletteItem]
    private let onSelect: (SelectionPaletteItem) -> Void
    private let onDismiss: () -> Void
    private let onCopy: ((SelectionPaletteItem) -> Void)?

    init(
        configuration: SelectionPaletteConfiguration,
        items: [SelectionPaletteItem],
        onSelect: @escaping (SelectionPaletteItem) -> Void,
        onDismiss: @escaping () -> Void,
        onCopy: ((SelectionPaletteItem) -> Void)? = nil
    ) {
        self.configuration = configuration
        self.items = items
        self.onSelect = onSelect
        self.onDismiss = onDismiss
        self.onCopy = onCopy
    }

    var hasItems: Bool { !items.isEmpty }

    var filteredItems: [SelectionPaletteItem] {
        filteredItems(for: searchText)
    }

    func filteredItems(for searchText: String) -> [SelectionPaletteItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard configuration.showsSearchField, !query.isEmpty else {
            return items
        }

        return items.filter { item in
            item.title.localizedCaseInsensitiveContains(query)
                || (item.subtitle?.localizedCaseInsensitiveContains(query) ?? false)
                || item.searchTokens.contains(where: { $0.localizedCaseInsensitiveContains(query) })
        }
    }

    var selectedItem: SelectionPaletteItem? {
        filteredItems[safe: selectedIndex]
    }

    /// The empty state: no entries at all, or none that matches.
    var emptyStateTitle: String {
        hasItems ? (configuration.noMatchesTitle ?? configuration.emptyStateTitle) : configuration.emptyStateTitle
    }

    func handleKeyDown(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers == .command, event.charactersIgnoringModifiers?.lowercased() == "c" {
            return copySelection()
        }

        switch event.keyCode {
        case 125: // Down arrow
            moveSelection(by: 1)
            return true
        case 126: // Up arrow
            moveSelection(by: -1)
            return true
        case 36, 76: // Return, keypad enter
            acceptSelection()
            return true
        case 53: // Escape
            onDismiss()
            return true
        case 51, 117: // Delete, forward delete
            guard configuration.showsSearchField else { return false }
            deleteBackward()
            return true
        default:
            guard configuration.showsSearchField, let typedText = event.selectionPaletteTypedText else {
                return false
            }
            searchText.append(typedText)
            return true
        }
    }

    /// Commands from the search field's editor (arrow keys, Return, Esc).
    func perform(_ command: SelectionPaletteCommand) -> Bool {
        switch command {
        case .moveUp:
            moveSelection(by: -1)
        case .moveDown:
            moveSelection(by: 1)
        case .accept:
            acceptSelection()
        case .cancel:
            onDismiss()
        }
        return true
    }

    /// Inserts the item: a double click, or Return on the selection.
    func selectItem(_ item: SelectionPaletteItem) {
        onSelect(item)
    }

    /// A single click only moves the selection.
    func highlight(_ item: SelectionPaletteItem) {
        guard let index = filteredItems.firstIndex(of: item) else { return }
        selectedIndex = index
    }

    /// ⌘C: copies the selected entry. Returns false when there is nothing to copy.
    @discardableResult
    func copySelection() -> Bool {
        guard let onCopy, let item = selectedItem else { return false }
        onCopy(item)
        return true
    }

    func dismiss() {
        onDismiss()
    }

    private func moveSelection(by offset: Int) {
        guard !filteredItems.isEmpty else { return }
        let itemCount = filteredItems.count
        selectedIndex = (selectedIndex + offset + itemCount) % itemCount
    }

    private func acceptSelection() {
        guard let item = selectedItem else { return }
        onSelect(item)
    }

    private func deleteBackward() {
        guard !searchText.isEmpty else { return }
        searchText.removeLast()
    }
}

// MARK: - Views

private struct SelectionPaletteContentView: View {
    @ObservedObject var model: SelectionPaletteInteractionModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPresented = false
    @State private var hoveredItemID: UUID?

    private let announcer = AccessibilityAnnouncementService()

    /// The entrance starts this close to full size.
    private static let entranceScale: CGFloat = 0.98

    var body: some View {
        let items = model.filteredItems
        let configuration = model.configuration
        VStack(spacing: 0) {
            if let previewText = configuration.previewText {
                Text(previewText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(configuration.previewLineLimit)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, LeiseSpacing.l)
                    .frame(height: SelectionPaletteMetrics.previewHeight)
                Divider()
            }

            if let searchPrompt = configuration.searchPrompt {
                searchBar(prompt: searchPrompt, accessibilityLabel: configuration.searchAccessibilityLabel ?? searchPrompt)
                Divider()
            }

            results(items)

            if !configuration.footerHints.isEmpty {
                Divider()
                footer(configuration.footerHints)
            }
        }
        .frame(
            width: configuration.panelWidth,
            height: SelectionPaletteMetrics.height(rowCount: items.count, configuration: configuration),
            alignment: .top
        )
        .background(PaletteMaterialBackground())
        .clipShape(RoundedRectangle(cornerRadius: LeiseRadius.panel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: LeiseRadius.panel, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: SelectionPaletteMetrics.hairline)
        )
        .scaleEffect(isPresented || reduceMotion ? 1 : Self.entranceScale, anchor: .top)
        .opacity(isPresented ? 1 : 0)
        .onAppear {
            withAnimation(LeiseMotion.adaptive(LeiseMotion.shape, reduceMotion: reduceMotion)) {
                isPresented = true
            }
        }
        .onChange(of: model.selectedIndex) { _, _ in
            if let item = model.selectedItem {
                announcer.announce(item.accessibilityText)
            }
        }
    }

    private func searchBar(prompt: String, accessibilityLabel: String) -> some View {
        HStack(spacing: LeiseSpacing.s + 2) {
            Image(systemName: "magnifyingglass")
                .font(.title2)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)

            PaletteSearchField(
                text: $model.searchText,
                prompt: prompt,
                accessibilityLabel: accessibilityLabel,
                onCommand: model.perform
            )
        }
        .padding(.horizontal, LeiseSpacing.l)
        .frame(height: SelectionPaletteMetrics.searchBarHeight)
        .overlay(alignment: .bottom) {
            // The field always has focus here, so its focus line is always on.
            Rectangle()
                .fill(LeiseColor.tint)
                .frame(height: 2)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private func results(_ items: [SelectionPaletteItem]) -> some View {
        if items.isEmpty {
            Text(model.emptyStateTitle)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .frame(height: SelectionPaletteMetrics.emptyStateHeight)
                .accessibilityAddTraits(.isStaticText)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: SelectionPaletteMetrics.rowSpacing) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            row(item, isSelected: index == model.selectedIndex)
                                .id(item.id)
                        }
                    }
                    .padding(SelectionPaletteMetrics.listPadding)
                }
                .scrollIndicators(.automatic)
                .onChange(of: model.selectedIndex) { _, newValue in
                    guard let item = items[safe: newValue] else { return }
                    proxy.scrollTo(item.id)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(String(localized: "Results"))
        }
    }

    private func row(_ item: SelectionPaletteItem, isSelected: Bool) -> some View {
        let lineLimit = model.configuration.titleLineLimit
        return HStack(alignment: .top, spacing: LeiseSpacing.m) {
            rowIcon(item)

            Text(item.title)
                .lineLimit(lineLimit, reservesSpace: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let detail = item.detail {
                Text(detail)
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(isSelected ? AnyShapeStyle(Color.white.opacity(0.85)) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
            }
        }
        .foregroundStyle(isSelected ? AnyShapeStyle(Color.white) : AnyShapeStyle(.primary))
        .padding(.horizontal, LeiseSpacing.s + 2)
        .padding(.vertical, LeiseSpacing.s)
        .frame(height: SelectionPaletteMetrics.rowHeight(titleLineLimit: lineLimit))
        .background(
            RoundedRectangle(cornerRadius: LeiseRadius.group, style: .continuous)
                .fill(rowFill(isSelected: isSelected, isHovered: hoveredItemID == item.id))
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering {
                hoveredItemID = item.id
            } else if hoveredItemID == item.id {
                hoveredItemID = nil
            }
        }
        .onTapGesture(count: 2) {
            model.selectItem(item)
        }
        .simultaneousGesture(TapGesture().onEnded {
            model.highlight(item)
        })
        .leiseAnimation(LeiseMotion.micro, value: hoveredItemID == item.id)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.accessibilityText)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction {
            model.selectItem(item)
        }
    }

    @ViewBuilder
    private func rowIcon(_ item: SelectionPaletteItem) -> some View {
        if item.appBundleIdentifier == nil, let iconSystemName = item.iconSystemName {
            Image(systemName: iconSystemName)
                .frame(width: SelectionPaletteMetrics.iconSize, height: SelectionPaletteMetrics.iconSize)
                .accessibilityHidden(true)
        } else {
            AppGlyph(bundleIdentifier: item.appBundleIdentifier, size: SelectionPaletteMetrics.iconSize)
        }
    }

    private func rowFill(isSelected: Bool, isHovered: Bool) -> Color {
        if isSelected { return LeiseColor.tintFill }
        if isHovered { return Color(nsColor: .quaternarySystemFill) }
        return .clear
    }

    private func footer(_ hints: [SelectionPaletteHint]) -> some View {
        HStack(spacing: LeiseSpacing.l) {
            ForEach(hints, id: \.self) { hint in
                HStack(spacing: LeiseSpacing.xs + 2) {
                    PaletteKeyHint(key: hint.key)
                    Text(hint.label)
                }
            }
            Spacer(minLength: 0)
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.horizontal, LeiseSpacing.l)
        .frame(height: SelectionPaletteMetrics.footerHeight)
        .accessibilityElement(children: .combine)
    }
}

/// A small key label for the footer.
private struct PaletteKeyHint: View {
    let key: String

    private static let minimumSide: CGFloat = 18

    var body: some View {
        Text(verbatim: key)
            .font(.caption.weight(.medium))
            .padding(.horizontal, LeiseSpacing.xs)
            .frame(minWidth: Self.minimumSide, minHeight: Self.minimumSide)
            .background(
                RoundedRectangle(cornerRadius: LeiseRadius.control, style: .continuous)
                    .fill(Color(nsColor: .quaternarySystemFill))
            )
            .overlay(
                RoundedRectangle(cornerRadius: LeiseRadius.control, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: SelectionPaletteMetrics.hairline)
            )
    }
}

/// The menu material behind the palette. It turns opaque by itself under
/// Reduce Transparency.
private struct PaletteMaterialBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .menu
        view.blendingMode = .behindWindow
        view.state = .active
        view.maskImage = Self.roundedMask(radius: LeiseRadius.panel)
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}

    /// A stretchable mask with continuous corners, the documented way to
    /// round a behind-window material.
    private static func roundedMask(radius: CGFloat) -> NSImage {
        // Continuous corners reach about 1.53 × the radius along each edge.
        let capInset = (radius * 1.6).rounded(.up)
        let side = capInset * 2 + 1
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.addPath(Path(roundedRect: rect, cornerRadius: radius, style: .continuous).cgPath)
            context.setFillColor(NSColor.black.cgColor)
            context.fillPath()
            return true
        }
        image.capInsets = NSEdgeInsets(top: capInset, left: capInset, bottom: capInset, right: capInset)
        image.resizingMode = .stretch
        return image
    }
}

/// A real text field, so IME input, paste and the caret work, with the
/// arrow keys, Return and Esc forwarded to the palette.
private struct PaletteSearchField: NSViewRepresentable {
    @Binding var text: String
    let prompt: String
    let accessibilityLabel: String
    let onCommand: (SelectionPaletteCommand) -> Bool

    func makeNSView(context: Context) -> PaletteTextField {
        let field = PaletteTextField()
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: SelectionPaletteMetrics.searchFontSize)
        field.placeholderString = prompt
        field.lineBreakMode = .byTruncatingTail
        field.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.delegate = context.coordinator
        field.setAccessibilityLabel(accessibilityLabel)
        field.stringValue = text
        return field
    }

    func updateNSView(_ field: PaletteTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text {
            field.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: PaletteSearchField

        init(parent: PaletteSearchField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.moveUp(_:)):
                parent.onCommand(.moveUp)
            case #selector(NSResponder.moveDown(_:)):
                parent.onCommand(.moveDown)
            case #selector(NSResponder.insertNewline(_:)):
                parent.onCommand(.accept)
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onCommand(.cancel)
            default:
                false
            }
        }
    }
}

/// Takes focus as soon as it is in the panel.
private final class PaletteTextField: NSTextField {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window else { return }
            window.makeFirstResponder(self)
        }
    }
}

// MARK: - Panel

private final class SelectionPalettePanel: NSPanel {
    var keyDownHandler: ((NSEvent) -> Bool)?
    /// ⌘C; returns whether an entry was copied.
    var copyHandler: (() -> Bool)?

    /// The search field sits about a fifth of the way down the screen.
    private static let topOffsetRatio: CGFloat = 0.2

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 300),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = .floating
        collectionBehavior = FloatingPanelSpacePolicy.selectionPaletteCollectionBehavior
        isOpaque = false
        backgroundColor = .clear
        // The system shadow follows the rounded content.
        hasShadow = true
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
    }

    override var canBecomeKey: Bool { true }

    override func keyDown(with event: NSEvent) {
        if keyDownHandler?(event) == true {
            return
        }
        super.keyDown(with: event)
    }

    /// The panel never activates Leise, so it handles the editing
    /// shortcuts itself instead of relying on the main menu.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard modifiers == .command, let key = event.charactersIgnoringModifiers?.lowercased() else {
            return super.performKeyEquivalent(with: event)
        }
        switch key {
        case "c" where !hasSelectedSearchText:
            if copyHandler?() == true { return true }
            return super.performKeyEquivalent(with: event)
        case "c":
            return NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: self)
        case "v":
            return NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: self)
        case "x":
            return NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: self)
        case "a":
            return NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: self)
        default:
            return super.performKeyEquivalent(with: event)
        }
    }

    private var hasSelectedSearchText: Bool {
        guard let editor = firstResponder as? NSTextView else { return false }
        return editor.selectedRange().length > 0
    }

    func positionOnActiveScreen() {
        let screen = activeScreen() ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }

        let visibleFrame = screen.visibleFrame
        let top = visibleFrame.maxY - visibleFrame.height * Self.topOffsetRatio
        setFrameOrigin(NSPoint(x: visibleFrame.midX - frame.width / 2, y: top - frame.height))
    }

    /// Changes the height and keeps the top edge where it is.
    func setHeightKeepingTop(_ height: CGFloat) {
        var newFrame = frame
        guard abs(newFrame.height - height) > 0.5 else { return }
        let top = newFrame.maxY
        newFrame.size.height = height
        newFrame.origin.y = top - height
        setFrame(newFrame, display: true)
        invalidateShadow()
    }

    private func activeScreen() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })
    }
}

@MainActor
final class SelectionPaletteController: SelectionPaletteControlling {
    private var panel: SelectionPalettePanel?
    private var interactionModel: SelectionPaletteInteractionModel?
    private var localClickMonitor: Any?
    private var globalClickMonitor: Any?
    private var cancellables = Set<AnyCancellable>()
    private var shadowRefreshTask: Task<Void, Never>?

    /// Long enough for the LeiseMotion.shape entrance to settle.
    private static let shadowRefreshDelay: Duration = .milliseconds(320)

    var isVisible: Bool { panel != nil }

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
        hide()
        guard !items.isEmpty else { return }

        var hidingOnCopy: ((SelectionPaletteItem) -> Void)?
        if let onCopy {
            hidingOnCopy = { [weak self] item in
                self?.hide()
                onCopy(item)
            }
        }
        let interactionModel = SelectionPaletteInteractionModel(
            configuration: configuration,
            items: items,
            onSelect: { [weak self] item in
                self?.hide()
                onSelect(item)
            },
            onDismiss: { [weak self] in
                self?.hide()
            },
            onCopy: hidingOnCopy
        )
        self.interactionModel = interactionModel

        let hosting = NSHostingView(rootView: SelectionPaletteContentView(model: interactionModel))
        // The panel's frame follows the results; SwiftUI must not resize it.
        hosting.sizingOptions = []

        let panelSize = NSSize(
            width: configuration.panelWidth,
            height: SelectionPaletteMetrics.height(rowCount: items.count, configuration: configuration)
        )
        let palettePanel = SelectionPalettePanel()
        palettePanel.contentView = hosting
        hosting.frame = NSRect(origin: .zero, size: panelSize)
        hosting.autoresizingMask = [.width, .height]
        palettePanel.setContentSize(panelSize)
        palettePanel.positionOnActiveScreen()
        palettePanel.keyDownHandler = { [weak interactionModel] event in
            interactionModel?.handleKeyDown(event) ?? false
        }
        palettePanel.copyHandler = { [weak interactionModel] in
            interactionModel?.copySelection() ?? false
        }

        panel = palettePanel
        palettePanel.makeKeyAndOrderFront(nil)

        interactionModel.$searchText
            .removeDuplicates()
            .sink { [weak self, weak interactionModel] text in
                guard let interactionModel else { return }
                // `$searchText` emits before the property changes, so filter the new text.
                let rowCount = interactionModel.filteredItems(for: text).count
                self?.panel?.setHeightKeepingTop(
                    SelectionPaletteMetrics.height(rowCount: rowCount, configuration: configuration)
                )
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification, object: palettePanel)
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.hide() }
            }
            .store(in: &cancellables)

        shadowRefreshTask = Task { [weak palettePanel] in
            try? await Task.sleep(for: Self.shadowRefreshDelay)
            palettePanel?.invalidateShadow()
        }

        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            MainActor.assumeIsolated {
                if let panel = self?.panel, !panel.frame.contains(NSEvent.mouseLocation) {
                    self?.hide()
                }
            }
            return event
        }
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.hide()
            }
        }
    }

    func hide() {
        if let monitor = localClickMonitor {
            NSEvent.removeMonitor(monitor)
            localClickMonitor = nil
        }
        if let monitor = globalClickMonitor {
            NSEvent.removeMonitor(monitor)
            globalClickMonitor = nil
        }
        cancellables.removeAll()
        shadowRefreshTask?.cancel()
        shadowRefreshTask = nil
        let closingPanel = panel
        panel = nil
        interactionModel = nil
        closingPanel?.orderOut(nil)
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private extension NSEvent {
    var selectionPaletteTypedText: String? {
        let disallowedModifiers: NSEvent.ModifierFlags = [.command, .control, .option, .function]
        let modifiers = modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard modifiers.intersection(disallowedModifiers).isEmpty else {
            return nil
        }

        guard let characters, !characters.isEmpty else {
            return nil
        }

        let containsControlCharacter = characters.unicodeScalars.contains(where: { scalar in
            CharacterSet.controlCharacters.contains(scalar)
        })
        return containsControlCharacter ? nil : characters
    }
}
