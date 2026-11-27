import SwiftUI

/// Transkribieren: record something longer, or transcribe a file. The model
/// comes from Diktat; only the language can differ per task.
struct TranscribePage: View {
    @Binding var mode: TranscribeMode
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            switch mode {
            case .recording:
                AudioRecorderView(viewModel: ServiceContainer.shared.audioRecorderViewModel) {
                    mode = .file
                }
                .transition(.opacity)
            case .file:
                FileTranscriptionView()
                    .transition(.opacity)
            }
        }
        .leiseAnimation(LeiseMotion.ui, value: mode)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker(String(localized: "Kind"), selection: $mode) {
                    ForEach(TranscribeMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
        }
    }
}
