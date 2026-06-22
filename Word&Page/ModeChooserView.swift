//
//  ModeChooserView.swift
//  Word&Page
//

import SwiftUI

struct ModeChooserView: View {
    let initialChoice: DocumentMode
    let onChoose: (DocumentMode) -> Void

    /// Word&Page accent — warm amber.
    private let accent = Color(red: 251.0 / 255.0,
                               green: 188.0 / 255.0,
                               blue:  95.0 / 255.0)

    var body: some View {
        VStack(spacing: 28) {
            VStack(spacing: 6) {
                Text("New Document")
                    .font(.title2.weight(.semibold))
                Text("Pick a kind. You can always open the other later.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 24) {
                ChoiceTile(
                    icon: "doc.text",
                    title: "Text",
                    subtitle: "Plain prose with outline numbering\n(1, 1.1, I., A., …)",
                    isDefault: initialChoice == .text,
                    accent: accent,
                    action: { onChoose(.text) }
                )
                ChoiceTile(
                    icon: "list.bullet.indent",
                    title: "Markdown",
                    subtitle: "Nested-list outline saved as\nstandard .md",
                    isDefault: initialChoice == .markdown,
                    accent: accent,
                    action: { onChoose(.markdown) }
                )
            }
        }
        .padding(32)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.35), radius: 24, y: 10)
        }
    }
}

private struct ChoiceTile: View {
    let icon: String
    let title: String
    let subtitle: String
    let isDefault: Bool
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(.primary)
                Text(title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                if isDefault {
                    Text("Last used")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(accent)
                } else {
                    Text(" ")
                        .font(.caption2.weight(.semibold))
                }
            }
            .frame(width: 200, height: 210)
            .padding(.vertical, 4)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.gray.opacity(0.10))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(isDefault ? accent : Color.gray.opacity(0.30),
                              lineWidth: isDefault ? 2 : 1)
        }
        .modifier(DefaultActionIfNeeded(isDefault: isDefault))
    }
}

/// Apply `.keyboardShortcut(.defaultAction)` only when the tile is the
/// last-used default, so Return triggers it. Non-default tiles get no shortcut.
private struct DefaultActionIfNeeded: ViewModifier {
    let isDefault: Bool
    func body(content: Content) -> some View {
        if isDefault {
            content.keyboardShortcut(.defaultAction)
        } else {
            content
        }
    }
}

#Preview {
    ModeChooserView(initialChoice: .text) { _ in }
        .padding()
}
