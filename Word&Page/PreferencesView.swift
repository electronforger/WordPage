//
//  PreferencesView.swift
//  Word&Page
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct PreferencesView: View {
    @Environment(Preferences.self) private var prefs

    var body: some View {
        TabView {
            AppearanceTab()
                .tabItem { Label("Appearance", systemImage: "paintpalette") }
            TypographyTab()
                .tabItem { Label("Typography", systemImage: "textformat") }
            BehaviorTab()
                .tabItem { Label("Behavior", systemImage: "slider.horizontal.3") }
        }
        .frame(width: 460, height: 320)
    }
}

private struct AppearanceTab: View {
    @Environment(Preferences.self) private var prefs

    var body: some View {
        @Bindable var prefs = prefs
        Form {
            ColorPicker("Background", selection: $prefs.backgroundColor, supportsOpacity: false)
            ColorPicker("Paper",      selection: $prefs.paperColor,      supportsOpacity: false)
            ColorPicker("Ink",        selection: $prefs.inkColor,        supportsOpacity: false)

            Section("Background Image") {
                ImageRow(
                    hasImage: prefs.backgroundImage != nil,
                    choose: { chooseImage(forBackground: true) },
                    clear:  { prefs.clearBackgroundImage() }
                )
            }

            Section("Paper Image") {
                ImageRow(
                    hasImage: prefs.paperImage != nil,
                    choose: { chooseImage(forBackground: false) },
                    clear:  { prefs.clearPaperImage() }
                )
            }

            Section {
                Button("Restore Defaults") {
                    prefs.backgroundColor = Color(red: 0.18, green: 0.18, blue: 0.20)
                    prefs.paperColor      = Color(red: 0.98, green: 0.97, blue: 0.93)
                    prefs.inkColor        = .black
                    prefs.clearBackgroundImage()
                    prefs.clearPaperImage()
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func chooseImage(forBackground: Bool) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = forBackground ? "Choose a background image" : "Choose a paper image"
        if panel.runModal() == .OK, let url = panel.url {
            if forBackground {
                prefs.setBackgroundImage(from: url)
            } else {
                prefs.setPaperImage(from: url)
            }
        }
    }
}

private struct ImageRow: View {
    let hasImage: Bool
    let choose: () -> Void
    let clear:  () -> Void

    var body: some View {
        HStack {
            Text(hasImage ? "Image selected" : "None")
                .foregroundStyle(.secondary)
            Spacer()
            Button("Choose…", action: choose)
            if hasImage {
                Button("Clear", action: clear)
            }
        }
    }
}

private struct TypographyTab: View {
    @Environment(Preferences.self) private var prefs

    private let fontChoices: [String] = [
        "New York", "Iowan Old Style", "Georgia", "Times New Roman",
        "Charter", "Palatino", "Optima",
        "Helvetica Neue", "Avenir Next", "SF Pro",
        "Menlo", "Courier New", "Courier"
    ]

    var body: some View {
        @Bindable var prefs = prefs
        Form {
            Picker("Font", selection: $prefs.fontName) {
                ForEach(fontChoices, id: \.self) { name in
                    Text(name).font(.custom(name, size: 13)).tag(name)
                }
            }

            HStack {
                Text("Size")
                Slider(value: $prefs.fontSize, in: prefs.fontSizeRange, step: 1)
                Text("\(Int(prefs.fontSize)) pt")
                    .monospacedDigit()
                    .frame(width: 50, alignment: .trailing)
            }

            HStack {
                Text("Line Spacing")
                Slider(value: $prefs.lineSpacing, in: 0...20, step: 1)
                Text("\(Int(prefs.lineSpacing))")
                    .monospacedDigit()
                    .frame(width: 50, alignment: .trailing)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

private struct BehaviorTab: View {
    @Environment(Preferences.self) private var prefs

    var body: some View {
        @Bindable var prefs = prefs
        Form {
            Picker("Save", selection: $prefs.saveBehavior) {
                ForEach(SaveBehavior.allCases) { s in
                    Text(s.displayName).tag(s)
                }
            }
            Picker("Text outline style", selection: $prefs.outlineStyle) {
                ForEach(OutlineStyle.textStyles) { s in
                    Text(s.displayName).tag(s)
                }
            }
            Picker("Markdown outline style", selection: $prefs.outlineStyleMarkdown) {
                ForEach(OutlineStyle.markdownStyles) { s in
                    Text(s.displayName).tag(s)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

#Preview {
    PreferencesView().environment(Preferences())
}
