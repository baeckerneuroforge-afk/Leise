import CoreGraphics
import Foundation

/// Legacy indicator styles. The pill (stored as `.minimal`) is the only
/// indicator now; `.notch` and `.overlay` remain so values stored by older
/// versions decode and can be migrated (see
/// `DictationViewModel.migrateLegacyIndicatorSettings`).
enum IndicatorStyle: String, CaseIterable {
    case notch
    case overlay
    case minimal
}

/// When the indicator pill is on screen.
enum NotchIndicatorVisibility: String, CaseIterable {
    /// The quiet idle bar stays visible and grows while dictating.
    case always
    /// The pill rises when dictation starts and sinks away afterwards.
    case duringActivity
    case never
}

enum NotchIndicatorContent: String, CaseIterable {
    case indicator
    case timer
    case waveform
    case profile
    case none
}

enum NotchIndicatorDisplay: String, CaseIterable {
    case activeScreen
    case primaryScreen
    case builtInScreen
}

enum OverlayPosition: String, CaseIterable {
    case top
    case bottom
}

/// One of the three fixed spots along the bottom of the screen where the
/// indicator pill rests. The user drags the pill between them.
enum IndicatorAnchor: String, CaseIterable, Sendable {
    case left
    case center
    case right

    var localizedName: String {
        switch self {
        case .left:
            String(localized: "Left")
        case .center:
            String(localized: "Center")
        case .right:
            String(localized: "Right")
        }
    }

    /// The neighbouring anchor in reading direction, used by the VoiceOver
    /// adjustable action. Returns `self` at either end.
    func moved(by step: Int) -> IndicatorAnchor {
        let all = Self.allCases
        guard let index = all.firstIndex(of: self) else { return self }
        let next = min(max(index + step, 0), all.count - 1)
        return all[next]
    }
}

/// How the indicator presents a feedback message ("toast").
enum IndicatorFeedbackKind: Equatable, Sendable {
    /// The text landed somewhere: the bars fold into a check.
    case success
    /// Neutral information with its own symbol.
    case info
    /// The user stopped the dictation: a neutral cross, no shake.
    case cancelled
    /// Something failed: a red cross and a short head shake.
    case error
}

/// The app a finished dictation was inserted into, for "In Mail eingefügt".
struct IndicatorInsertionTarget: Equatable, Sendable {
    let appName: String?
    let bundleIdentifier: String?
}

extension IndicatorStyle {
    var supportsTranscriptPreview: Bool {
        self != .minimal
    }

    var transcriptPreviewBaseFontSize: CGFloat {
        switch self {
        case .notch:
            12
        case .overlay:
            13
        case .minimal:
            12
        }
    }

    var transcriptPreviewBaseExpandedHeight: CGFloat {
        switch self {
        case .notch:
            80
        case .overlay:
            100
        case .minimal:
            0
        }
    }

    func scaledTranscriptPreviewMetric(_ baseMetric: CGFloat, fontSize: CGFloat) -> CGFloat {
        guard supportsTranscriptPreview, transcriptPreviewBaseFontSize > 0 else {
            return 0
        }

        return (baseMetric * fontSize / transcriptPreviewBaseFontSize).rounded(.up)
    }
}
