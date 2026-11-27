import AppKit
import SwiftUI

/// A keycap for shortcuts, e.g. the fn / 🌐 key. The large size is pressable
/// in the setup flow.
struct KeyCap: View {
    enum Size {
        case small
        case large
    }

    var label: String
    var systemImage: String?
    var size: Size = .small
    var isPressed = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var metrics: (width: CGFloat, height: CGFloat, radius: CGFloat, skirt: CGFloat, font: Font, symbol: Font, padding: CGFloat) {
        switch size {
        case .small:
            return (34, 30, LeiseRadius.control, 1.5, .system(size: 10, weight: .medium), .system(size: 9, weight: .medium), 5)
        case .large:
            return (104, 96, 18, 5, .system(size: 22, weight: .medium), .system(size: 21, weight: .regular), 15)
        }
    }

    var body: some View {
        let m = metrics
        let skirt = isPressed ? m.skirt * 0.2 : m.skirt
        VStack(alignment: .leading, spacing: 0) {
            if let systemImage {
                Image(systemName: systemImage).font(m.symbol)
            }
            Spacer(minLength: 0)
            Text(verbatim: label).font(m.font)
        }
        .foregroundStyle(.primary)
        .padding(m.padding)
        .frame(width: m.width, height: m.height, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: m.radius, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: Color.primary.opacity(0.18), radius: 0, x: 0, y: skirt)
                .overlay(
                    RoundedRectangle(cornerRadius: m.radius, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
                )
        }
        .offset(y: isPressed ? m.skirt * 0.8 : 0)
        .animation(LeiseMotion.adaptive(LeiseMotion.micro, reduceMotion: reduceMotion), value: isPressed)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: label))
    }
}

/// Status as symbol plus text. State never relies on color alone.
struct StatusLabel: View {
    enum Kind {
        case ready
        case working
        case warning
        case error
    }

    var kind: Kind
    var text: String

    var body: some View {
        Label {
            Text(text).foregroundStyle(.secondary)
        } icon: {
            switch kind {
            case .ready:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(LeiseColor.ready)
            case .working:
                ProgressView().controlSize(.mini)
            case .warning:
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(LeiseColor.live)
            case .error:
                Image(systemName: "xmark.octagon.fill").foregroundStyle(LeiseColor.record)
            }
        }
        .font(.callout)
        .labelStyle(.titleAndIcon)
    }
}

/// The real icon of an app, looked up by bundle identifier.
struct AppGlyph: View {
    var bundleIdentifier: String?
    var size: CGFloat = 20

    var body: some View {
        Image(nsImage: Self.icon(for: bundleIdentifier))
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    @MainActor
    static func icon(for bundleIdentifier: String?) -> NSImage {
        if let bundleIdentifier,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSWorkspace.shared.icon(for: .application)
    }
}

/// A settings page: a grouped form whose title becomes the window title.
struct LeiseSettingsPage<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        Form {
            content()
        }
        .formStyle(.grouped)
        .navigationTitle(title)
    }
}
