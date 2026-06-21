//
//  ModeChooserView.swift
//  Word&Page
//

import SwiftUI

struct ModeChooserView: View {
    let initialChoice: DocumentMode
    let onChoose: (DocumentMode) -> Void

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 6) {
                Text("New Document")
                    .font(.title2.weight(.semibold))
                Text("Pick a kind. You can always open the other later.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 18) {
                ChoiceTile(
                    icon: "doc.text",
                    title: "Text",
                    subtitle: "Plain prose with outline numbering\n(1, 1.1, I., A., …)",
                    isDefault: initialChoice == .text,
                    action: { onChoose(.text) }
                )
                ChoiceTile(
                    icon: "list.bullet.indent",
                    title: "Markdown",
                    subtitle: "Nested-list outline saved as\nstandard .md",
                    isDefault: initialChoice == .markdown,
                    action: { onChoose(.markdown) }
                )
            }
        }
        .padding(32)
        .frame(width: 520, height: 320)
    }
}

private struct ChoiceTile: View {
    let icon: String
    let title: String
    let subtitle: String
    let isDefault: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 44, weight: .light))
                Text(title)
                    .font(.title3.weight(.semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                if isDefault {
                    Text("Last used")
                        .font(.caption2)
                        .foregroundStyle(.tint)
                }
            }
            .frame(width: 200, height: 200)
            .padding(.vertical, 8)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .keyboardShortcut(isDefault ? KeyboardShortcut.defaultAction : KeyboardShortcut(.space, modifiers: [.shift, .option]))
    }
}

#Preview {
    ModeChooserView(initialChoice: .text) { _ in }
}
