//
//  DocumentManager.swift
//  Word&Page
//

import AppKit
import UniformTypeIdentifiers

enum SaveFormat: Int, CaseIterable {
    case wpage = 0
    case md    = 1
    case txt   = 2
    case rtf   = 3
    case html  = 4
    case pdf   = 5

    var displayName: String {
        switch self {
        case .wpage: "Word&Page Document (.wpage)"
        case .md:    "Markdown (.md)"
        case .txt:   "Plain Text (.txt)"
        case .rtf:   "Rich Text (.rtf)"
        case .html:  "HTML (.html)"
        case .pdf:   "PDF (.pdf)"
        }
    }

    var ext: String {
        switch self {
        case .wpage: "wpage"
        case .md:    "md"
        case .txt:   "txt"
        case .rtf:   "rtf"
        case .html:  "html"
        case .pdf:   "pdf"
        }
    }

    var utType: UTType {
        switch self {
        case .wpage: UTType(filenameExtension: "wpage") ?? .data
        case .md:    UTType(filenameExtension: "md") ?? .plainText
        case .txt:   .plainText
        case .rtf:   .rtf
        case .html:  .html
        case .pdf:   .pdf
        }
    }

    /// True if this format is the native format for some mode (sets fileURL on save).
    var isNative: Bool { self == .wpage || self == .md }

    static func detect(extension ext: String) -> SaveFormat {
        switch ext.lowercased() {
        case "md":    .md
        case "txt":   .txt
        case "rtf":   .rtf
        case "html":  .html
        case "pdf":   .pdf
        default:      .wpage
        }
    }
}

@MainActor
@Observable
final class DocumentManager {
    static let shared = DocumentManager()
    private init() {}

    weak var textView: PaperTextView?

    var fileURL: URL? = nil
    var isDirty: Bool = false

    /// nil = mode chooser must be shown. Set by user via the chooser, or
    /// auto-set by Open based on file extension.
    var mode: DocumentMode? = nil

    /// Toggle that drives the SwiftUI chooser overlay in ContentView.
    /// Starts false; the WindowConfigurator flips it true after the window
    /// finishes entering full screen so the chooser appears on top of the
    /// fullscreen window (not before, which prevents the fullscreen
    /// transition from happening).
    var showingModeChooser: Bool = false

    private var activePanelCoordinator: SavePanelCoordinator?

    // MARK: - Mode lifecycle

    func confirmMode(_ m: DocumentMode) {
        mode = m
        clearTextStorage()
        fileURL = nil
        isDirty = false
        showingModeChooser = false
        if let prefsMode = (NSApp.delegate as Any?) as? Preferences {
            _ = prefsMode // silence unused warning if needed
        }
    }

    /// Triggered by File → New. Reshows the chooser.
    func newDocument() {
        showingModeChooser = true
    }

    private func clearTextStorage() {
        guard let tv = textView, let storage = tv.textStorage else { return }
        let savedDelegate = tv.delegate
        tv.delegate = nil
        storage.beginEditing()
        storage.replaceCharacters(in: NSRange(location: 0, length: storage.length),
                                  with: "")
        storage.endEditing()
        tv.delegate = savedDelegate
    }

    // MARK: - Open

    func openDocument() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [SaveFormat.wpage.utType, SaveFormat.md.utType]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        let complete: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            let ext = url.pathExtension.lowercased()
            // Pick mode from extension, then load.
            if ext == "md" {
                self?.mode = .markdown
                self?.showingModeChooser = false
                try? self?.loadMarkdown(from: url)
            } else {
                self?.mode = .text
                self?.showingModeChooser = false
                try? self?.loadWpage(from: url)
            }
        }
        presentModal(panel, complete: complete)
    }

    // MARK: - Save / Save As

    func save() {
        guard let url = fileURL else {
            saveAs()
            return
        }
        // Re-save to existing URL using the native format for current mode.
        switch mode {
        case .text:     try? writeWpage(to: url)
        case .markdown: try? writeMarkdown(to: url)
        case nil:       saveAs()
        }
    }

    func saveAs() {
        let modeForFormats = mode ?? .text
        let availableFormats: [SaveFormat] = {
            switch modeForFormats {
            case .text:     return [.wpage, .txt, .rtf, .pdf]
            case .markdown: return [.md, .txt, .html, .pdf]
            }
        }()
        let initialFormat: SaveFormat = availableFormats.first ?? .wpage
        let initialName = fileURL?.lastPathComponent
            ?? "Untitled.\(initialFormat.ext)"

        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.allowsOtherFileTypes = false
        panel.isExtensionHidden = false
        panel.allowedContentTypes = [initialFormat.utType]
        panel.nameFieldStringValue = initialName

        let coordinator = SavePanelCoordinator(panel: panel,
                                               formats: availableFormats,
                                               initial: initialFormat)
        activePanelCoordinator = coordinator
        panel.accessoryView = coordinator.accessoryView

        let complete: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            defer { self?.activePanelCoordinator = nil }
            guard response == .OK, let url = panel.url else { return }
            let chosen = coordinator.selectedFormat
            let finalURL = url.pathExtension.lowercased() == chosen.ext
                ? url
                : url.deletingPathExtension().appendingPathExtension(chosen.ext)
            self?.performWrite(format: chosen, to: finalURL)
        }
        presentModal(panel, complete: complete)
    }

    // MARK: - Write dispatcher

    private func performWrite(format: SaveFormat, to url: URL) {
        do {
            switch format {
            case .wpage:
                try writeWpage(to: url)
                fileURL = url
                isDirty = false
            case .md:
                try writeMarkdown(to: url)
                fileURL = url
                isDirty = false
            case .txt:  try writeTxt(to: url)
            case .rtf:  try writeRtf(to: url)
            case .html: try writeHtml(to: url)
            case .pdf:  writePdf(to: url)
            }
        } catch {
            presentError("Could not save document", details: error.localizedDescription)
        }
    }

    // MARK: - Writers

    private func writeWpage(to url: URL) throws {
        guard let tv = textView, let storage = tv.textStorage else { return }
        var paths: [DocFile.PathEntry] = []
        let nsstr = storage.string as NSString
        var loc = 0
        var paraIndex = 0
        while loc < nsstr.length {
            let para = nsstr.paragraphRange(for: NSRange(location: loc, length: 0))
            if let path = storage.attribute(.outlinePath,
                                            at: para.location,
                                            effectiveRange: nil) as? [Int] {
                paths.append(DocFile.PathEntry(paragraphIndex: paraIndex, path: path))
            }
            let next = para.location + para.length
            if next <= loc { break }
            loc = next
            paraIndex += 1
        }
        let doc = DocFile(version: 1, text: tv.string, outlinePaths: paths)
        let data = try JSONEncoder().encode(doc)
        try data.write(to: url)
    }

    private func writeTxt(to url: URL) throws {
        guard let tv = textView else { return }
        try tv.string.write(to: url, atomically: true, encoding: .utf8)
    }

    private func writeRtf(to url: URL) throws {
        guard let tv = textView, let storage = tv.textStorage else { return }
        let range = NSRange(location: 0, length: storage.length)
        let attrs: [NSAttributedString.DocumentAttributeKey: Any] = [
            .documentType: NSAttributedString.DocumentType.rtf
        ]
        let data = try storage.data(from: range, documentAttributes: attrs)
        try data.write(to: url)
    }

    private func writeHtml(to url: URL) throws {
        // Use Apple's NSAttributedString markdown initializer to render, then
        // emit the rendered text as HTML.
        guard let tv = textView else { return }
        let markdownText = renderMarkdownText(from: tv)
        let attributed = (try? NSAttributedString(
            markdown: markdownText,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? NSAttributedString(string: markdownText)
        let range = NSRange(location: 0, length: attributed.length)
        let attrs: [NSAttributedString.DocumentAttributeKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html
        ]
        let data = try attributed.data(from: range, documentAttributes: attrs)
        try data.write(to: url)
    }

    private func writePdf(to url: URL) {
        guard let tv = textView, let storage = tv.textStorage else { return }

        let printInfo = NSPrintInfo()
        printInfo.jobDisposition = .save
        printInfo.leftMargin = 72
        printInfo.rightMargin = 72
        printInfo.topMargin = 72
        printInfo.bottomMargin = 72
        printInfo.horizontalPagination = .fit
        printInfo.verticalPagination = .automatic
        printInfo.isHorizontallyCentered = false
        printInfo.isVerticallyCentered = false
        printInfo.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url

        let contentWidth = printInfo.paperSize.width
            - printInfo.leftMargin
            - printInfo.rightMargin

        let pdfTextView = NSTextView(
            frame: NSRect(origin: .zero,
                          size: NSSize(width: contentWidth, height: 1))
        )
        pdfTextView.textStorage?.setAttributedString(storage)
        pdfTextView.isVerticallyResizable = true
        pdfTextView.isHorizontallyResizable = false
        pdfTextView.textContainer?.widthTracksTextView = true
        pdfTextView.textContainer?.containerSize =
            NSSize(width: contentWidth, height: CGFloat.greatestFiniteMagnitude)
        pdfTextView.sizeToFit()

        let op = NSPrintOperation(view: pdfTextView, printInfo: printInfo)
        op.showsPrintPanel = false
        op.showsProgressPanel = false
        op.run()
    }

    // MARK: - Markdown round-trip

    /// Walks paragraphs and emits markdown text. Outline paragraphs get
    /// leading whitespace indentation per depth; non-outline paragraphs
    /// emit as-is.
    private func renderMarkdownText(from tv: PaperTextView) -> String {
        guard let storage = tv.textStorage else { return tv.string }
        let nsstr = storage.string as NSString
        var out = ""
        var loc = 0
        while loc < nsstr.length {
            let paraRange = nsstr.paragraphRange(
                for: NSRange(location: loc, length: 0)
            )
            let raw = nsstr.substring(with: paraRange)
            let hasNewline = raw.hasSuffix("\n")
            let line = hasNewline ? String(raw.dropLast()) : raw

            if let path = storage.attribute(.outlinePath,
                                            at: paraRange.location,
                                            effectiveRange: nil) as? [Int] {
                // Indent step: 2 for bullets, 3 for numbered (since "1. " is 3 chars)
                let stepIsBullet = !line.hasPrefix("0") && !line.hasPrefix("1")
                    && line.first.map { $0 == "-" || $0 == "*" || $0 == "+" } == true
                let step = stepIsBullet ? 2 : 3
                let indent = String(repeating: " ",
                                    count: max(path.count - 1, 0) * step)
                out += indent + line
            } else {
                out += line
            }
            if hasNewline { out += "\n" }
            let next = paraRange.location + paraRange.length
            if next <= loc { break }
            loc = next
        }
        return out
    }

    private func writeMarkdown(to url: URL) throws {
        guard let tv = textView else { return }
        let text = renderMarkdownText(from: tv)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Parses markdown text into in-buffer text + outline-path map.
    /// Bullet markers (- * +) and numbered markers (1. 2. etc.) are recognized.
    private func loadMarkdown(from url: URL) throws {
        let data = try Data(contentsOf: url)
        let raw = String(data: data, encoding: .utf8) ?? ""
        applyMarkdown(raw)
        fileURL = url
        isDirty = false
    }

    private func applyMarkdown(_ raw: String) {
        guard let tv = textView, let storage = tv.textStorage else { return }
        let savedDelegate = tv.delegate
        tv.delegate = nil

        let lines = raw.components(separatedBy: "\n")
        var bufferLines: [String] = []
        var pathMap: [Int: [Int]] = [:]

        for (i, line) in lines.enumerated() {
            if let parsed = parseMarkdownListLine(line) {
                bufferLines.append(parsed.cleanLine)
                pathMap[i] = Array(repeating: 1, count: parsed.depth)
            } else {
                bufferLines.append(line)
            }
        }
        let bufferText = bufferLines.joined(separator: "\n")

        storage.beginEditing()
        storage.replaceCharacters(in: NSRange(location: 0, length: storage.length),
                                  with: bufferText)

        // Reapply current font/color/paragraphStyle across the new text.
        let fullRange = NSRange(location: 0, length: storage.length)
        if let font = tv.typingAttributes[.font] {
            storage.addAttribute(.font, value: font, range: fullRange)
        }
        if let color = tv.typingAttributes[.foregroundColor] {
            storage.addAttribute(.foregroundColor, value: color, range: fullRange)
        }
        if let para = tv.typingAttributes[.paragraphStyle] {
            storage.addAttribute(.paragraphStyle, value: para, range: fullRange)
        }

        // Apply outline path attributes per the parsed map.
        let nsstr = storage.string as NSString
        var loc = 0
        var paraIndex = 0
        while loc < nsstr.length {
            let para = nsstr.paragraphRange(for: NSRange(location: loc, length: 0))
            if let path = pathMap[paraIndex] {
                storage.addAttribute(.outlinePath, value: path, range: para)
            }
            let next = para.location + para.length
            if next <= loc { break }
            loc = next
            paraIndex += 1
        }
        storage.endEditing()

        tv.delegate = savedDelegate
        tv.applyOutlineAttributes()
    }

    private struct ParsedMarkdownLine {
        let cleanLine: String   // line with leading whitespace stripped — "- foo" or "1. foo"
        let depth: Int
    }

    private func parseMarkdownListLine(_ line: String) -> ParsedMarkdownLine? {
        // Match (whitespace)(bullet or number)( space)(rest)
        let leading = line.prefix { $0 == " " || $0 == "\t" }
        let spaces = leading.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
        let trimmed = String(line.dropFirst(leading.count))

        // Bullet marker
        if let first = trimmed.first, "-*+".contains(first),
           trimmed.dropFirst().first == " " {
            let depth = spaces / 2 + 1
            return ParsedMarkdownLine(cleanLine: "- " + String(trimmed.dropFirst(2)),
                                      depth: max(depth, 1))
        }
        // Numbered marker: 1. , 2., 10.
        let digits = trimmed.prefix(while: { $0.isNumber })
        if !digits.isEmpty,
           trimmed.dropFirst(digits.count).first == ".",
           trimmed.dropFirst(digits.count + 1).first == " " {
            let depth = spaces / 3 + 1
            let rest = String(trimmed.dropFirst(digits.count + 2))
            return ParsedMarkdownLine(cleanLine: "\(digits). " + rest,
                                      depth: max(depth, 1))
        }
        return nil
    }

    // MARK: - .wpage open

    private func loadWpage(from url: URL) throws {
        let data = try Data(contentsOf: url)
        let doc = try JSONDecoder().decode(DocFile.self, from: data)
        applyDoc(doc)
        fileURL = url
        isDirty = false
    }

    private func applyDoc(_ doc: DocFile) {
        guard let tv = textView, let storage = tv.textStorage else { return }
        let savedDelegate = tv.delegate
        tv.delegate = nil

        storage.beginEditing()
        storage.replaceCharacters(in: NSRange(location: 0, length: storage.length),
                                  with: doc.text)

        let fullRange = NSRange(location: 0, length: storage.length)
        if let font = tv.typingAttributes[.font] {
            storage.addAttribute(.font, value: font, range: fullRange)
        }
        if let color = tv.typingAttributes[.foregroundColor] {
            storage.addAttribute(.foregroundColor, value: color, range: fullRange)
        }
        if let para = tv.typingAttributes[.paragraphStyle] {
            storage.addAttribute(.paragraphStyle, value: para, range: fullRange)
        }

        let pathMap = Dictionary(uniqueKeysWithValues:
            doc.outlinePaths.map { ($0.paragraphIndex, $0.path) })
        let nsstr = storage.string as NSString
        var loc = 0
        var paraIndex = 0
        while loc < nsstr.length {
            let para = nsstr.paragraphRange(for: NSRange(location: loc, length: 0))
            if let path = pathMap[paraIndex] {
                storage.addAttribute(.outlinePath, value: path, range: para)
            }
            let next = para.location + para.length
            if next <= loc { break }
            loc = next
            paraIndex += 1
        }
        storage.endEditing()

        tv.delegate = savedDelegate
        tv.applyOutlineAttributes()
    }

    // MARK: - Panel presentation

    private func presentModal(_ panel: NSSavePanel,
                              complete: @escaping (NSApplication.ModalResponse) -> Void) {
        if let window = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first {
            panel.beginSheetModal(for: window, completionHandler: complete)
        } else {
            complete(panel.runModal())
        }
    }

    private func presentError(_ message: String, details: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = details
        alert.alertStyle = .warning
        alert.runModal()
    }
}

// MARK: - Save-panel accessory view coordinator

@MainActor
private final class SavePanelCoordinator: NSObject {
    private weak var panel: NSSavePanel?
    let accessoryView: NSView
    private let popup: NSPopUpButton
    private let formats: [SaveFormat]
    private(set) var selectedFormat: SaveFormat

    init(panel: NSSavePanel, formats: [SaveFormat], initial: SaveFormat) {
        self.panel = panel
        self.formats = formats
        self.selectedFormat = initial

        let view = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 38))
        let label = NSTextField(labelWithString: "Format:")
        label.frame = NSRect(x: 10, y: 10, width: 60, height: 22)
        view.addSubview(label)

        popup = NSPopUpButton(frame: NSRect(x: 70, y: 6, width: 340, height: 26))
        popup.addItems(withTitles: formats.map(\.displayName))
        if let idx = formats.firstIndex(of: initial) { popup.selectItem(at: idx) }
        view.addSubview(popup)

        self.accessoryView = view
        super.init()
        popup.target = self
        popup.action = #selector(formatChanged(_:))
    }

    @objc private func formatChanged(_ sender: NSPopUpButton) {
        let idx = sender.indexOfSelectedItem
        guard idx >= 0 && idx < formats.count, let panel = panel else { return }
        let format = formats[idx]
        selectedFormat = format

        let current = panel.nameFieldStringValue
        let base = (current as NSString).deletingPathExtension
        panel.nameFieldStringValue = "\(base).\(format.ext)"
        panel.allowedContentTypes = [format.utType]
    }
}

// MARK: - Native file model

private struct DocFile: Codable {
    let version: Int
    let text: String
    let outlinePaths: [PathEntry]

    struct PathEntry: Codable {
        let paragraphIndex: Int
        let path: [Int]
    }
}
