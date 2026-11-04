import AppKit
import SwiftUI

enum EditBadge {
    static let background = Color(nsColor: .windowBackgroundColor).opacity(0.85)
}

extension View {
    @ViewBuilder
    func editWobble(phase: Double, active: Bool) -> some View {
        if active {
            phaseAnimator([-0.3, 0.3], trigger: false) { view, angle in
                view.rotationEffect(.degrees(angle))
            } animation: { _ in
                .easeInOut(duration: 0.45).delay(phase)
            }
        } else {
            self
        }
    }
}

struct PlainSearchField: View {
    let prompt: LocalizedStringKey
    @Binding var text: String
    var busy = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(prompt, text: $text, prompt: Text(prompt))
                .textFieldStyle(.plain)
                .labelsHidden()
            if busy {
                ProgressView()
                    .controlSize(.small)
            } else if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.borderless)
                .help("Clear Search")
            }
        }
    }
}
