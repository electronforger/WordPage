//
//  Word_PageApp.swift
//  Word&Page
//

import SwiftUI
import AppKit

@main
struct Word_PageApp: App {
    @State private var prefs = Preferences()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(prefs)
                .background(WindowConfigurator())
        }
        .windowStyle(.hiddenTitleBar)

        Settings {
            PreferencesView()
                .environment(prefs)
        }

        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New") { DocumentManager.shared.newDocument() }
                    .keyboardShortcut("n", modifiers: [.command])
                Button("Open…") { DocumentManager.shared.openDocument() }
                    .keyboardShortcut("o", modifiers: [.command])
            }
            CommandGroup(replacing: .saveItem) {
                Button("Save") { DocumentManager.shared.save() }
                    .keyboardShortcut("s", modifiers: [.command])
                Button("Save As…") { DocumentManager.shared.saveAs() }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
            }
            CommandMenu("Outline") {
                Button("Indent") {
                    NSApp.sendAction(Selector(("outlineDeepen:")), to: nil, from: nil)
                }
                .keyboardShortcut("]", modifiers: [.command])

                Button("Outdent") {
                    NSApp.sendAction(Selector(("outlineOutdent:")), to: nil, from: nil)
                }
                .keyboardShortcut("[", modifiers: [.command])
            }
            CommandGroup(after: .windowArrangement) {
                Divider()
                Button("Toggle Full Screen") {
                    NSApp.keyWindow?.toggleFullScreen(nil)
                }
                .keyboardShortcut("f", modifiers: [.command, .control])
            }
        }
    }
}

/// Forces the host window into full screen on first appearance.
private struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            if !window.styleMask.contains(.fullScreen) {
                window.toggleFullScreen(nil)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
