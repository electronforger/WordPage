//
//  PaperView.swift
//  Word&Page
//

import SwiftUI
import AppKit

struct PaperView: NSViewRepresentable {
    // Primitive values so SwiftUI's diffing reliably triggers updateNSView.
    let outlineStyle: OutlineStyle
    let lineSpacing: CGFloat
    let fontName: String
    let fontSize: CGFloat
    let inkColor: Color
    @Binding var text: String

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        let textView = PaperTextView(frame: .zero)
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = true
        textView.isAutomaticDashSubstitutionEnabled = true
        textView.isAutomaticTextReplacementEnabled = true
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = true
        textView.usesFindBar = true
        textView.importsGraphics = false
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 32, height: 48)
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                  height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true

        textView.string = text
        scrollView.documentView = textView

        // Make this text view discoverable to the DocumentManager so File menu
        // commands can read/write it.
        DocumentManager.shared.textView = textView

        applyDocumentAttributes(to: textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? PaperTextView else { return }
        // Note: we intentionally don't sync text-binding → textView.string here.
        // The binding only flows textView → binding (via Coordinator.textDidChange),
        // so style swaps that mutate storage can't be clobbered by a stale binding.
        applyDocumentAttributes(to: textView)
    }

    // MARK: - Unified document apply

    private func applyDocumentAttributes(to textView: PaperTextView) {
        let nsFont = NSFont(name: fontName, size: fontSize)
            ?? NSFont.systemFont(ofSize: fontSize)
        let ink = NSColor(inkColor)

        // Cache current style on the text view for keyDown handlers.
        textView.currentOutlineStyle = outlineStyle
        textView.currentLineSpacing = lineSpacing

        textView.backgroundColor = .clear
        textView.insertionPointColor = ink
        textView.textColor = ink

        let defaultPara = OutlineEngine.defaultParagraphStyle(lineSpacing: lineSpacing)
        textView.defaultParagraphStyle = defaultPara
        textView.typingAttributes = [
            .font: nsFont,
            .foregroundColor: ink,
            .paragraphStyle: defaultPara
        ]

        guard let storage = textView.textStorage, storage.length > 0 else { return }

        // Suspend the delegate so our edits don't trigger textDidChange and
        // a reentrant SwiftUI update cycle.
        let savedDelegate = textView.delegate
        textView.delegate = nil

        // Apply global font/color/default-paragraph style across the document.
        storage.beginEditing()
        let full = NSRange(location: 0, length: storage.length)
        storage.addAttribute(.font, value: nsFont, range: full)
        storage.addAttribute(.foregroundColor, value: ink, range: full)
        storage.addAttribute(.paragraphStyle, value: defaultPara, range: full)
        storage.endEditing()

        // Restore delegate before calling applyOutlineAttributes (which also
        // suspends/restores delegate internally).
        textView.delegate = savedDelegate

        // Renumber + rewrite all outline prefixes; this also overlays the
        // per-depth indented paragraph styles and the path attribute.
        textView.applyOutlineAttributes()

        // Push the updated content back to the SwiftUI binding asynchronously.
        let updatedText = storage.string
        if updatedText != text {
            DispatchQueue.main.async {
                self.text = updatedText
            }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: PaperView
        init(_ parent: PaperView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            DocumentManager.shared.isDirty = true
        }
    }
}

// MARK: - Custom NSTextView for outline behavior

final class PaperTextView: NSTextView {

    /// Current outline style, refreshed on every updateNSView.
    var currentOutlineStyle: OutlineStyle = .decimal
    /// Current line spacing, refreshed on every updateNSView.
    var currentLineSpacing: CGFloat = 0

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 /* Return */ {
            if handleOutlineReturn() { return }
        }
        super.keyDown(with: event)
    }

    // Action methods reachable via responder chain.
    @objc func outlineDeepen(_ sender: Any?) { handleOutlineDeepen() }
    @objc func outlineOutdent(_ sender: Any?) { handleOutlineOutdent() }

    // MARK: - Cmd+] : start or deepen

    private func handleOutlineDeepen() {
        guard let storage = textStorage else { return }
        let cursor = selectedRange().location
        let prevPath = OutlineEngine.previousPath(in: storage, before: cursor)
        let newPath = (prevPath ?? []) + [1]

        let para = (storage.string as NSString).paragraphRange(
            for: NSRange(location: cursor, length: 0)
        )
        let existingPrefixLen = OutlineEngine.currentPrefixLength(in: storage, paragraph: para)
        let newPrefix = OutlineEngine.format(newPath, style: currentOutlineStyle) + " "

        applyPrefix(newPrefix,
                    path: newPath,
                    paragraphLocation: para.location,
                    existingPrefixLen: existingPrefixLen,
                    originalCursor: cursor)
        applyOutlineAttributes()
    }

    // MARK: - Cmd+[ : outdent

    private func handleOutlineOutdent() {
        guard let storage = textStorage else { return }
        let cursor = selectedRange().location
        guard let currentPath = OutlineEngine.path(in: storage, at: cursor) else { return }

        let para = (storage.string as NSString).paragraphRange(
            for: NSRange(location: cursor, length: 0)
        )
        let existingPrefixLen = OutlineEngine.currentPrefixLength(in: storage, paragraph: para)

        if currentPath.count <= 1 {
            applyPrefix("",
                        path: nil,
                        paragraphLocation: para.location,
                        existingPrefixLen: existingPrefixLen,
                        originalCursor: cursor)
            applyOutlineAttributes()
            return
        }

        var newPath = Array(currentPath.dropLast())
        newPath[newPath.count - 1] += 1
        let newPrefix = OutlineEngine.format(newPath, style: currentOutlineStyle) + " "

        applyPrefix(newPrefix,
                    path: newPath,
                    paragraphLocation: para.location,
                    existingPrefixLen: existingPrefixLen,
                    originalCursor: cursor)
        applyOutlineAttributes()
    }

    private func applyPrefix(_ newPrefix: String,
                             path: [Int]?,
                             paragraphLocation: Int,
                             existingPrefixLen: Int,
                             originalCursor: Int) {
        guard let storage = textStorage else { return }
        let replaceRange = NSRange(location: paragraphLocation, length: existingPrefixLen)
        let newPrefixLen = (newPrefix as NSString).length

        setSelectedRange(replaceRange)
        insertText(newPrefix, replacementRange: replaceRange)

        let updatedPara = (storage.string as NSString).paragraphRange(
            for: NSRange(location: paragraphLocation, length: 0)
        )
        if updatedPara.length > 0 {
            storage.beginEditing()
            if let path = path {
                storage.addAttribute(.outlinePath, value: path, range: updatedPara)
                let pStyle = OutlineEngine.paragraphStyle(forDepth: path.count,
                                                          lineSpacing: currentLineSpacing)
                storage.addAttribute(.paragraphStyle, value: pStyle, range: updatedPara)
            } else {
                storage.removeAttribute(.outlinePath, range: updatedPara)
                let pStyle = OutlineEngine.defaultParagraphStyle(lineSpacing: currentLineSpacing)
                storage.addAttribute(.paragraphStyle, value: pStyle, range: updatedPara)
            }
            storage.endEditing()
        }

        let prefixEnd = paragraphLocation + existingPrefixLen
        let newCursor: Int
        if originalCursor < prefixEnd {
            newCursor = paragraphLocation + newPrefixLen
        } else {
            newCursor = originalCursor + (newPrefixLen - existingPrefixLen)
        }
        setSelectedRange(NSRange(location: newCursor, length: 0))
    }

    // MARK: - Renumber + rewrite

    /// Walks every outline paragraph in document order. Paragraphs whose visible
    /// prefix matches their stored path (in any known style) are renumbered
    /// sequentially and rewritten. Paragraphs whose prefix has been manually
    /// broken by the user are de-outlined (path attribute removed, paragraph
    /// style reset) so the user can finish deleting them.
    func applyOutlineAttributes() {
        guard let storage = textStorage, storage.length > 0 else { return }

        let savedDelegate = delegate
        delegate = nil
        defer { delegate = savedDelegate }

        let savedSelection = selectedRange()

        // Pass 1: collect outline paragraphs; validate prefix integrity.
        var lines: [(location: Int, oldPath: [Int], oldPrefixLen: Int)] = []
        var corrupted: [NSRange] = []
        let snap = (storage.string as NSString).copy() as! NSString
        var loc = 0
        while loc < snap.length {
            let para = snap.paragraphRange(for: NSRange(location: loc, length: 0))
            if let path = storage.attribute(.outlinePath,
                                            at: para.location,
                                            effectiveRange: nil) as? [Int] {
                if let prefixLen = matchedPrefixLength(in: storage,
                                                       paragraph: para,
                                                       path: path) {
                    lines.append((para.location, path, prefixLen))
                } else {
                    corrupted.append(para)
                }
            }
            let next = para.location + para.length
            if next <= loc { break }
            loc = next
        }

        storage.beginEditing()

        // Pass 2: de-outline corrupted paragraphs.
        for para in corrupted {
            storage.removeAttribute(.outlinePath, range: para)
            let pStyle = OutlineEngine.defaultParagraphStyle(lineSpacing: currentLineSpacing)
            storage.addAttribute(.paragraphStyle, value: pStyle, range: para)
        }

        // Pass 3: renumber and rewrite remaining valid outline paragraphs.
        let newPaths = OutlineEngine.renumber(paths: lines.map { $0.oldPath })
        var offset = 0
        var cursorOffset = 0
        for (i, line) in lines.enumerated() {
            let newPath = newPaths[i]
            let live = storage.string as NSString
            let currentLoc = line.location + offset
            guard currentLoc < live.length else { continue }

            let para = live.paragraphRange(for: NSRange(location: currentLoc, length: 0))
            let oldPrefixLen = line.oldPrefixLen
            let newPrefix = OutlineEngine.format(newPath, style: currentOutlineStyle) + " "
            let newPrefixLen = (newPrefix as NSString).length
            let replaceRange = NSRange(location: para.location, length: oldPrefixLen)

            let existing = (storage.string as NSString).substring(with: replaceRange)
            if existing != newPrefix {
                storage.replaceCharacters(in: replaceRange, with: newPrefix)
            }

            let updated = (storage.string as NSString).paragraphRange(
                for: NSRange(location: para.location, length: 0)
            )
            storage.addAttribute(.outlinePath, value: newPath, range: updated)
            let pStyle = OutlineEngine.paragraphStyle(forDepth: newPath.count,
                                                     lineSpacing: currentLineSpacing)
            storage.addAttribute(.paragraphStyle, value: pStyle, range: updated)
            if let font = typingAttributes[.font] {
                storage.addAttribute(.font, value: font, range: updated)
            }
            if let color = typingAttributes[.foregroundColor] {
                storage.addAttribute(.foregroundColor, value: color, range: updated)
            }

            let delta = newPrefixLen - oldPrefixLen
            if line.location < savedSelection.location {
                cursorOffset += delta
            }
            offset += delta
        }

        storage.endEditing()

        let newCursor = savedSelection.location + cursorOffset
        let clamped = min(max(newCursor, 0), storage.length)
        setSelectedRange(NSRange(location: clamped, length: 0))
    }

    /// Returns the length of the visible prefix if its leading text matches
    /// `format(path, …) + " "` in any known outline style; otherwise nil
    /// (meaning the prefix has been manually broken).
    private func matchedPrefixLength(in storage: NSTextStorage,
                                     paragraph: NSRange,
                                     path: [Int]) -> Int? {
        guard paragraph.length > 0 else { return nil }
        let nsstr = storage.string as NSString
        for style in OutlineStyle.allCases {
            let expected = (OutlineEngine.format(path, style: style) + " ") as NSString
            guard expected.length <= paragraph.length else { continue }
            let leading = nsstr.substring(with: NSRange(location: paragraph.location,
                                                       length: expected.length))
            if leading == (expected as String) {
                return expected.length
            }
        }
        return nil
    }

    // MARK: - Return : continue / end outline

    private func handleOutlineReturn() -> Bool {
        guard let storage = textStorage else { return false }
        let cursor = selectedRange().location
        guard let currentPath = OutlineEngine.path(in: storage, at: cursor) else {
            return false
        }
        let nsstr = storage.string as NSString
        let para = nsstr.paragraphRange(for: NSRange(location: cursor, length: 0))
        let prefixLen = OutlineEngine.currentPrefixLength(in: storage, paragraph: para)

        let endsWithNewline = para.length > 0 &&
            nsstr.character(at: para.location + para.length - 1) == 0x0A
        let contentLen = para.length - prefixLen - (endsWithNewline ? 1 : 0)

        if contentLen <= 0 {
            // Empty outline line → strip prefix, then normal newline.
            let stripRange = NSRange(location: para.location, length: prefixLen)
            setSelectedRange(stripRange)
            insertText("", replacementRange: stripRange)
            let cleared = (storage.string as NSString).paragraphRange(
                for: NSRange(location: para.location, length: 0)
            )
            if cleared.length > 0 {
                storage.beginEditing()
                storage.removeAttribute(.outlinePath, range: cleared)
                let pStyle = OutlineEngine.defaultParagraphStyle(lineSpacing: currentLineSpacing)
                storage.addAttribute(.paragraphStyle, value: pStyle, range: cleared)
                storage.endEditing()
            }
            let after = selectedRange().location
            insertText("\n", replacementRange: NSRange(location: after, length: 0))
            return true
        }

        // Continue outline: insert "\n<nextPrefix> ".
        var nextPath = currentPath
        nextPath[nextPath.count - 1] += 1
        let insertion = "\n" + OutlineEngine.format(nextPath, style: currentOutlineStyle) + " "

        let insertRange = NSRange(location: cursor, length: 0)
        insertText(insertion, replacementRange: insertRange)

        let newParaProbe = cursor + 1
        let newPara = (storage.string as NSString).paragraphRange(
            for: NSRange(location: newParaProbe, length: 0)
        )
        storage.beginEditing()
        storage.addAttribute(.outlinePath, value: nextPath, range: newPara)
        let pStyle = OutlineEngine.paragraphStyle(forDepth: nextPath.count,
                                                  lineSpacing: currentLineSpacing)
        storage.addAttribute(.paragraphStyle, value: pStyle, range: newPara)
        storage.endEditing()
        applyOutlineAttributes()
        return true
    }
}
