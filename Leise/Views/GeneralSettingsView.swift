import SwiftUI

// The old "Allgemein" page is gone: its rows moved to Diktat and Audio.
// What remains here is the permission UI the pages share.

/// The permissions Leise still needs, at the top of a page. Shows nothing
/// once both are granted.
struct PermissionsSection: View {
    @ObservedObject var dictation: DictationViewModel

    var body: some View {
        if dictation.needsMicPermission || dictation.needsAccessibilityPermission {
            Section {
                if dictation.needsMicPermission {
                    PermissionStatusRow(kind: .microphone) { dictation.requestMicPermission() }
                }
                if dictation.needsAccessibilityPermission {
                    PermissionStatusRow(kind: .accessibility) { dictation.requestAccessibilityPermission() }
                }
            } header: {
                Text(String(localized: "Permissions"))
            }
        }
    }
}

/// A missing permission as a status row with the button that fixes it.
struct PermissionStatusRow: View {
    enum Kind {
        case microphone
        case accessibility

        var title: String {
            switch self {
            case .microphone: String(localized: "Microphone")
            case .accessibility: String(localized: "Accessibility")
            }
        }

        var problem: String {
            switch self {
            case .microphone: String(localized: "No access: Leise can’t hear you")
            case .accessibility: String(localized: "No access: Leise can’t insert text")
            }
        }
    }

    let kind: Kind
    let grant: () -> Void

    var body: some View {
        LabeledContent {
            HStack(spacing: LeiseSpacing.m) {
                StatusLabel(kind: .error, text: kind.problem)
                Button(String(localized: "Grant Access"), action: grant)
            }
        } label: {
            Text(kind.title)
        }
    }
}
