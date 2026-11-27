import SwiftUI

/// The pill preview for settings that embed it directly. New code uses
/// `IndicatorAppearanceSection`, which includes this preview.
struct IndicatorPreviewView: View {
    @ObservedObject private var dictation = ServiceContainer.shared.dictationViewModel

    var body: some View {
        LeisePillPreviewStrip(
            anchor: dictation.indicatorPillAnchor,
            visibility: dictation.notchIndicatorVisibility
        )
        .padding(LeiseSpacing.m)
    }
}

/// The notch / overlay / minimal style choice is gone: the pill is the only
/// indicator. Kept empty until the settings that embed it are replaced by
/// `IndicatorAppearanceSection`.
struct IndicatorStylePicker: View {
    var body: some View {
        EmptyView()
    }
}
