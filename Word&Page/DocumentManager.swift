//
//  DocumentManager.swift
//  Word&Page
//

import AppKit
import UniformTypeIdentifiers

enum SaveFormat: Int, CaseIterable {
    case wpage = 0
    case txt   = 1
    case rtf   = 2
    case pdf   = 3

    var displayName: String {
        switch self {
        case .wpage: "Word&Page Document (.wpage)"
        case .txt:   "Plain Text (.txt)"
        case .rtf:   "Rich Text (.rtf)"
        case .pdf:   "PDF (.pdf)"
        }
    }

    var ext: String {
        switch self {
        case .wpage: "wpage"
        case .txt:   "txt"
        case .rtf:   "rtf"
        case .pdf:   "pdf"
        }
    }

    var utType: UTType {
        switch self {
        case .wpage: UTType(filenameExtension: "wpage") ?? .data
        case .txt:   .plainText
        case .rtf:   .rtf
        case .pdf:   .pdf
        }
    }

    static func detect(extension ext: String) -> SaveFormat {
        switch ext.lowercased() {
        case "txt": .txt
        case "rtf": .rtf
        case "pdf": .pdf
        default:    .wpage
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

    // Hold the save-panel coordinator while a panel is open so it isn't
    // deallocated mid-modal-session.
    private var activePanelCoordinator: SavePanelCoordinator?

    // MARK: - New / Open

    func newDocument() {
        guard let tv = textView, let storage = tv.textStorage else { return }
        let savedDelegate = tv.delegate
        tv.delegate = nil
        storage.beginEditing()
        storage.replaceCharacters(in: NSRange(location: 0, length: storage.length),
                                  with: "")
        storage.endEditing()
        tv.delegate = savedDelegate
        fileURL = nil
        isDirty = false
    }

    func openDocument() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [SaveFormat.wpage.utType]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        let complete: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            try? self?.loadDocument(from: url)
        }
        presentModal(panel, complete: complete)
    }

    // MARK: - Save / Save As

    func save() {
        if let url = fileURL {
            try? writeWpage(to: url)
        } else {
            saveAs()
        }
    }

    func saveAs() {
        let initialName = fileURL?.lastPathComponent ?? "Untitled.wpage"
        let initialFormat = SaveFormat.detect(extension: (initialName as NSString).pathExtension)

        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.allowsOtherFileTypes = false
        panel.isExtensionHidden = false
        panel.allowedContentTypes = [initialFormat.utType]
        panel.nameFieldStringValue = initialName

        let coordinator = SavePanelCoordinator(panel: panel, initial: initialFormat)
        activePanelCoordinator = coordinator
        panel.accessoryView = coordinator.accessoryView

        let complete: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            defer { self?.activePanelCoordinator = nil }
            guard response == .OK, let url = panel.url else { return }
            let chosen = coordinator.selectedFormat
            // Ensure URL has correct extension matching the chosen format.
            let finalURL = url.pathExtension.lowercased() == chosen.ext
                ? url
                : url.deletingPathExtension().appendingPathExtension(chosen.ext)
            self?.performWrite(format: chosen, to: finalURL)
        }
        presentModal(panel, complete: complete)
    }

    // MARK: - Write dispatcher

    private func performWrite(format: SaveFormat, to url: URL) {
        switch format {
        case .wpage:
            do {
                try writeWpage(to: url)
                fileURL = url
                isDirty = false
            } catch {
                presentError("Could not save document", details: error.localizedDescription)
            }
        case .txt:
            do { try writeTxt(to: url) } catch {
                presentError("Could not export text", details: error.localizedDescription)
            }
        case .rtf:
            do { try writeRtf(to: url) } catch {
                presentError("Could not export RTF", details: error.localizedDescription)
            }
        case .pdf:
            writePdf(to: url)
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

    // MARK: - Open / load (.wpage only)

    private func loadDocument(from url: URL) throws {
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

        // Apply current typing attributes (font / color / default paragraph style)
        // across the entire loaded document. Without this, paragraphs that aren't
        // outline lines end up with no font attribute and render at the system
        // default size.
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

        // Overlay outline path attributes per the saved map.
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
    private(set) var selectedFormat: SaveFormat

    init(panel: NSSavePanel, initial: SaveFormat) {
        self.panel = panel
        self.selectedFormat = initial

        let view = NSView(frame: NSRect(x: 0, y: 0, width: 380, height: 38))
        let label = NSTextField(labelWithString: "Format:")
        label.frame = NSRect(x: 10, y: 10, width: 60, height: 22)
        view.addSubview(label)

        popup = NSPopUpButton(frame: NSRect(x: 70, y: 6, width: 300, height: 26))
        popup.addItems(withTitles: SaveFormat.allCases.map(\.displayName))
        popup.selectItem(at: initial.rawValue)
        view.addSubview(popup)

        self.accessoryView = view
        super.init()
        popup.target = self
        popup.action = #selector(formatChanged(_:))
    }

    @objc private func formatChanged(_ sender: NSPopUpButton) {
        guard let format = SaveFormat(rawValue: sender.indexOfSelectedItem),
              let panel = panel else { return }
        selectedFormat = format

        // Swap the filename extension and update allowed content types.
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
