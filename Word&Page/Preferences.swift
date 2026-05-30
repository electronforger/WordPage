//
//  Preferences.swift
//  Word&Page
//

import SwiftUI
import AppKit

enum OutlineStyle: String, CaseIterable, Identifiable, Codable {
    case decimal          // 1, 1.1, 1.1.1
    case legal            // 1., 1.1., 1.1.1.
    case alphaNumeric     // 1, A, i
    case harvard          // I., A., 1., a., i.
    case bulleted         // •, ◦, ▪

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .decimal: "Decimal (1.1.1)"
        case .legal: "Legal (1.1.1.)"
        case .alphaNumeric: "Alpha-numeric (1, A, i)"
        case .harvard: "Harvard (I., A., 1., a., i.)"
        case .bulleted: "Bulleted"
        }
    }
}

enum SaveBehavior: String, CaseIterable, Identifiable, Codable {
    case autosaveContinuously
    case autosaveOnPause
    case manual

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .autosaveContinuously: "Autosave continuously"
        case .autosaveOnPause: "Autosave when idle"
        case .manual: "Manual (⌘S)"
        }
    }
}

private enum DefaultsKey {
    static let backgroundColor     = "wp.backgroundColor"
    static let paperColor          = "wp.paperColor"
    static let inkColor            = "wp.inkColor"
    static let fontName            = "wp.fontName"
    static let fontSize            = "wp.fontSize"
    static let lineSpacing         = "wp.lineSpacing"
    static let saveBehavior        = "wp.saveBehavior"
    static let outlineStyle        = "wp.outlineStyle"
    static let backgroundImagePath = "wp.backgroundImagePath"
    static let paperImagePath      = "wp.paperImagePath"
}

@Observable
final class Preferences {

    // Colors
    var backgroundColor: Color {
        didSet { Self.saveColor(backgroundColor, key: DefaultsKey.backgroundColor) }
    }
    var paperColor: Color {
        didSet { Self.saveColor(paperColor, key: DefaultsKey.paperColor) }
    }
    var inkColor: Color {
        didSet { Self.saveColor(inkColor, key: DefaultsKey.inkColor) }
    }

    // Typography
    var fontName: String {
        didSet { UserDefaults.standard.set(fontName, forKey: DefaultsKey.fontName) }
    }
    var fontSize: CGFloat {
        didSet { UserDefaults.standard.set(Double(fontSize), forKey: DefaultsKey.fontSize) }
    }
    var lineSpacing: CGFloat {
        didSet { UserDefaults.standard.set(Double(lineSpacing), forKey: DefaultsKey.lineSpacing) }
    }

    // Layout knob ranges (paperWidth itself lives in ContentView — transient).
    let paperWidthRange: ClosedRange<CGFloat> = 320...1100
    let fontSizeRange: ClosedRange<CGFloat> = 10...36

    // Behavior
    var saveBehavior: SaveBehavior {
        didSet { UserDefaults.standard.set(saveBehavior.rawValue, forKey: DefaultsKey.saveBehavior) }
    }
    var outlineStyle: OutlineStyle {
        didSet { UserDefaults.standard.set(outlineStyle.rawValue, forKey: DefaultsKey.outlineStyle) }
    }

    // Image overrides
    var backgroundImage: NSImage?
    var paperImage: NSImage?
    private(set) var backgroundImagePath: String?
    private(set) var paperImagePath: String?

    init() {
        let d = UserDefaults.standard

        self.backgroundColor = Self.loadColor(key: DefaultsKey.backgroundColor)
            ?? Color(red: 0.18, green: 0.18, blue: 0.20)
        self.paperColor = Self.loadColor(key: DefaultsKey.paperColor)
            ?? Color(red: 0.98, green: 0.97, blue: 0.93)
        self.inkColor = Self.loadColor(key: DefaultsKey.inkColor)
            ?? .black

        self.fontName = d.string(forKey: DefaultsKey.fontName) ?? "New York"

        let storedSize = d.object(forKey: DefaultsKey.fontSize) as? Double
        self.fontSize = storedSize.map { CGFloat($0) } ?? 18

        let storedSpace = d.object(forKey: DefaultsKey.lineSpacing) as? Double
        self.lineSpacing = storedSpace.map { CGFloat($0) } ?? 4

        self.saveBehavior = d.string(forKey: DefaultsKey.saveBehavior)
            .flatMap { SaveBehavior(rawValue: $0) } ?? .autosaveOnPause
        self.outlineStyle = d.string(forKey: DefaultsKey.outlineStyle)
            .flatMap { OutlineStyle(rawValue: $0) } ?? .decimal

        let bgPath = d.string(forKey: DefaultsKey.backgroundImagePath)
        self.backgroundImagePath = bgPath
        self.backgroundImage = bgPath.flatMap { NSImage(contentsOfFile: $0) }

        let paperPath = d.string(forKey: DefaultsKey.paperImagePath)
        self.paperImagePath = paperPath
        self.paperImage = paperPath.flatMap { NSImage(contentsOfFile: $0) }
    }

    // MARK: - Image picker / clear

    func setBackgroundImage(from sourceURL: URL) {
        guard let dest = Self.copyImage(from: sourceURL, prefix: "bg") else { return }
        Self.removeFile(at: backgroundImagePath)
        backgroundImagePath = dest
        backgroundImage = NSImage(contentsOfFile: dest)
        UserDefaults.standard.set(dest, forKey: DefaultsKey.backgroundImagePath)
    }

    func clearBackgroundImage() {
        Self.removeFile(at: backgroundImagePath)
        backgroundImagePath = nil
        backgroundImage = nil
        UserDefaults.standard.removeObject(forKey: DefaultsKey.backgroundImagePath)
    }

    func setPaperImage(from sourceURL: URL) {
        guard let dest = Self.copyImage(from: sourceURL, prefix: "paper") else { return }
        Self.removeFile(at: paperImagePath)
        paperImagePath = dest
        paperImage = NSImage(contentsOfFile: dest)
        UserDefaults.standard.set(dest, forKey: DefaultsKey.paperImagePath)
    }

    func clearPaperImage() {
        Self.removeFile(at: paperImagePath)
        paperImagePath = nil
        paperImage = nil
        UserDefaults.standard.removeObject(forKey: DefaultsKey.paperImagePath)
    }

    // MARK: - File helpers

    private static func appSupportDirectory() -> URL {
        let dirs = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask)
        let url = dirs[0].appendingPathComponent("Word&Page", isDirectory: true)
        try? FileManager.default.createDirectory(at: url,
                                                 withIntermediateDirectories: true)
        return url
    }

    private static func copyImage(from src: URL, prefix: String) -> String? {
        let ext = src.pathExtension.isEmpty ? "img" : src.pathExtension
        let dest = appSupportDirectory()
            .appendingPathComponent("\(prefix)-\(UUID().uuidString).\(ext)")
        do {
            try FileManager.default.copyItem(at: src, to: dest)
            return dest.path
        } catch {
            return nil
        }
    }

    private static func removeFile(at path: String?) {
        guard let path = path else { return }
        try? FileManager.default.removeItem(atPath: path)
    }

    // MARK: - Color persistence

    private static func saveColor(_ color: Color, key: String) {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .white
        let components: [Double] = [
            Double(ns.redComponent),
            Double(ns.greenComponent),
            Double(ns.blueComponent),
            Double(ns.alphaComponent)
        ]
        UserDefaults.standard.set(components, forKey: key)
    }

    private static func loadColor(key: String) -> Color? {
        guard let arr = UserDefaults.standard.array(forKey: key) as? [Double],
              arr.count == 4 else { return nil }
        return Color(.sRGB, red: arr[0], green: arr[1], blue: arr[2], opacity: arr[3])
    }
}
