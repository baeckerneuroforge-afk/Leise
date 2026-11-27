import AppKit
import SwiftUI

/// Geometry of the five-bar Leise mark: a spoken word's envelope, loud first,
/// then quieter. The same bars are the app icon, the menu bar glyph and the
/// indicator's live waveform.
enum LeiseMarkShape {
    static let restingHeights: [CGFloat] = [0.55, 1.0, 0.72, 0.45, 0.26]
    /// A distinct static shape for "listening" under Reduce Motion, so the
    /// state never depends on motion or color alone.
    static let listeningHeights: [CGFloat] = [0.9, 0.55, 1.0, 0.65, 0.85]
    static let barCount = 5
    /// Bar width and gap relative to the mark's height.
    static let barWidthRatio: CGFloat = 0.17
    static let gapRatio: CGFloat = 0.13

    /// Bar rectangles centered in `rect`, using the rect's height as the tallest bar.
    static func barRects(in rect: CGRect, heights: [CGFloat] = restingHeights) -> [CGRect] {
        let fullHeight = rect.height
        let barWidth = fullHeight * barWidthRatio
        let gap = fullHeight * gapRatio
        let totalWidth = barWidth * CGFloat(heights.count) + gap * CGFloat(heights.count - 1)
        var x = rect.midX - totalWidth / 2
        return heights.map { relative in
            let height = max(barWidth, fullHeight * relative)
            defer { x += barWidth + gap }
            return CGRect(x: x, y: rect.midY - height / 2, width: barWidth, height: height)
        }
    }

    /// Heights for a live voice level (0...1) at time `t`. Mirrors the preview:
    /// every bar follows the level with its own phase, never fully flat.
    static func liveHeights(level: Double, time t: Double) -> [CGFloat] {
        let clamped = min(max(level, 0), 1)
        return (0 ..< barCount).map { index in
            let wobble = 0.6 + 0.4 * sin(t * 10.3 + Double(index) * 1.9)
            return CGFloat(min(max(0.2 + 0.8 * clamped * wobble, 0.12), 1))
        }
    }

    /// Heights for the "transcribing" wave: a crest travels across the bars.
    static func waveHeights(time t: Double) -> [CGFloat] {
        (0 ..< barCount).map { index in
            let phase = (t / 0.9) * 2 * .pi - Double(index) * 0.62
            return CGFloat(0.22 + 0.73 * (0.5 + 0.5 * sin(phase)))
        }
    }

    /// Draws the mark into an image, e.g. for the menu bar.
    static func image(
        size: CGSize,
        heights: [CGFloat] = restingHeights,
        color: NSColor = .black,
        isTemplate: Bool = true
    ) -> NSImage {
        let image = NSImage(size: size, flipped: false) { bounds in
            color.setFill()
            let markRect = bounds.insetBy(dx: 0, dy: bounds.height * 0.11)
            for bar in barRects(in: markRect, heights: heights) {
                NSBezierPath(roundedRect: bar, xRadius: bar.width / 2, yRadius: bar.width / 2).fill()
            }
            return true
        }
        image.isTemplate = isTemplate
        return image
    }
}

/// The Leise mark as a SwiftUI view.
///
/// Size it with `.frame(height:)`; the width follows from the bar ratios.
struct LeiseMark: View {
    enum Mode: Equatable {
        case resting
        /// Bars follow a voice level between 0 and 1.
        case live(level: Double)
        /// A crest travels across the bars while Leise transcribes.
        case wave
        /// Static listening shape, used automatically under Reduce Motion.
        case listening
    }

    var mode: Mode = .resting
    var color: Color = LeiseColor.tint

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var animates: Bool {
        guard !reduceMotion else { return false }
        switch mode {
        case .live, .wave: return true
        case .resting, .listening: return false
        }
    }

    var body: some View {
        TimelineView(.animation(paused: !animates)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            Canvas { canvas, size in
                let rect = CGRect(origin: .zero, size: size)
                for bar in LeiseMarkShape.barRects(in: rect, heights: heights(at: time)) {
                    canvas.fill(Path(roundedRect: bar, cornerRadius: bar.width / 2), with: .color(color))
                }
            }
        }
        .aspectRatio(Self.aspectRatio, contentMode: .fit)
        .accessibilityHidden(true)
    }

    private func heights(at time: Double) -> [CGFloat] {
        switch mode {
        case .resting:
            return LeiseMarkShape.restingHeights
        case .listening:
            return LeiseMarkShape.listeningHeights
        case let .live(level):
            return reduceMotion ? LeiseMarkShape.listeningHeights : LeiseMarkShape.liveHeights(level: level, time: time)
        case .wave:
            return reduceMotion ? Array(repeating: 0.6, count: LeiseMarkShape.barCount) : LeiseMarkShape.waveHeights(time: time)
        }
    }

    /// Width divided by height for the five bars.
    static var aspectRatio: CGFloat {
        let bars = CGFloat(LeiseMarkShape.barCount)
        return bars * LeiseMarkShape.barWidthRatio + (bars - 1) * LeiseMarkShape.gapRatio
    }
}
