import AppKit
import SwiftUI

// Design tokens for Leise. The values mirror DESIGN.md (repo root), which is
// the source of truth; docs/design/redesign-preview.html shows them in use.
// Neutrals (text, backgrounds, separators) deliberately stay system semantic
// colors so Dark Mode, Increase Contrast and Reduce Transparency work for free.

/// Brand colors. Each one has exactly one job.
enum LeiseColor {
    /// Petrol. Selection, links, switches, symbols. Backed by the AccentColor asset.
    static let tint = Color.accentColor
    /// Filled surfaces that carry white text: primary buttons, the selected sidebar row.
    static let tintFill = Color("LeiseTintFill")
    /// Only while the microphone is live for dictation, like the macOS mic dot.
    static let live = Color("LeiseLive")
    /// The recorder is running, something failed, or an action is destructive.
    static let record = Color("LeiseRecord")
    /// Ready, inserted, granted. Use it on symbols, never as text color.
    static let ready = Color("LeiseReady")

    static var liveNS: NSColor { NSColor(named: "LeiseLive") ?? .systemOrange }
    static var recordNS: NSColor { NSColor(named: "LeiseRecord") ?? .systemRed }
    static var readyNS: NSColor { NSColor(named: "LeiseReady") ?? .systemGreen }
}

/// The 4-pt spacing scale.
enum LeiseSpacing {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
    static let xxxl: CGFloat = 32
}

/// Four radii. Pills and the indicator are capsules (radius = height / 2).
enum LeiseRadius {
    static let control: CGFloat = 6
    static let group: CGFloat = 10
    static let panel: CGFloat = 14
    static let window: CGFloat = 16
}

/// Motion tokens. Every animation reports a state change; Reduce Motion
/// falls back to a plain crossfade.
enum LeiseMotion {
    /// Hover and press feedback.
    static let micro = Animation.easeOut(duration: 0.15)
    /// Page changes, switches, small layout changes.
    static let ui = Animation.easeOut(duration: 0.2)
    /// The indicator pill opening, closing and resizing; drawers.
    static let shape = Animation.spring(duration: 0.28, bounce: 0.12)
    /// Success moments, numbers, the setup mark.
    static let moment = Animation.spring(duration: 0.3, bounce: 0.2)
    /// What every animation becomes under Reduce Motion.
    static let reduced = Animation.easeInOut(duration: 0.2)

    static func adaptive(_ animation: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? reduced : animation
    }

    /// Reads the system setting directly, for AppKit code paths without a SwiftUI environment.
    @MainActor static var systemReduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
}

extension View {
    /// `.animation(_:value:)` with a Leise token that respects Reduce Motion.
    func leiseAnimation<V: Equatable>(_ animation: Animation, value: V) -> some View {
        modifier(LeiseAnimationModifier(animation: animation, value: value))
    }
}

private struct LeiseAnimationModifier<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation
    let value: V

    func body(content: Content) -> some View {
        content.animation(LeiseMotion.adaptive(animation, reduceMotion: reduceMotion), value: value)
    }
}

/// `withAnimation` with a Leise token that respects Reduce Motion.
@MainActor
func withLeiseAnimation<Result>(_ animation: Animation, _ body: () throws -> Result) rethrows -> Result {
    try withAnimation(LeiseMotion.adaptive(animation, reduceMotion: LeiseMotion.systemReduceMotion), body)
}
