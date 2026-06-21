//
//  MarkdownLiveStyler.swift
//  Word&Page
//
//  Live inline styling for Markdown documents: headings, bold, italic, and
//  inline code render visually as the user types, while the raw markdown
//  characters stay in the buffer (just de-emphasized) so the file remains
//  valid `.md`.
//

import AppKit

enum MarkdownLiveStyler {

    static func apply(to storage: NSTextStorage,
                      baseFont: NSFont,
                      baseColor: NSColor,
                      showInvisibles: Bool = true) {
        guard storage.length > 0 else { return }
        let text = storage.string
        let nsstr = text as NSString
        let fullRange = NSRange(location: 0, length: nsstr.length)

        storage.beginEditing()
        defer { storage.endEditing() }

        // 1. Headings: `#` through `######` at line start.
        applyHeadings(storage: storage,
                      text: text,
                      nsstr: nsstr,
                      baseFont: baseFont,
                      baseColor: baseColor,
                      fullRange: fullRange,
                      showInvisibles: showInvisibles)

        // 2. Bold: **text** (also __text__)
        applyInlinePair(storage: storage,
                        text: text,
                        nsstr: nsstr,
                        fullRange: fullRange,
                        pattern: #"(\*\*|__)(?=\S)(.+?)(?<=\S)\1"#,
                        markerGroup: 1,
                        innerGroup: 2,
                        contentFont: bold(of: baseFont),
                        baseColor: baseColor,
                        showInvisibles: showInvisibles)

        // 3. Italic: *text* / _text_ (not surrounded by another asterisk/underscore)
        applyInlinePair(storage: storage,
                        text: text,
                        nsstr: nsstr,
                        fullRange: fullRange,
                        pattern: #"(?<!\*)\*(?!\*)([^*\n]+?)\*(?!\*)"#,
                        markerGroup: nil,
                        innerGroup: 1,
                        contentFont: italic(of: baseFont),
                        baseColor: baseColor,
                        markerLength: 1,
                        showInvisibles: showInvisibles)

        applyInlinePair(storage: storage,
                        text: text,
                        nsstr: nsstr,
                        fullRange: fullRange,
                        pattern: #"(?<![A-Za-z0-9_])_(?!_)([^_\n]+?)_(?![A-Za-z0-9_])"#,
                        markerGroup: nil,
                        innerGroup: 1,
                        contentFont: italic(of: baseFont),
                        baseColor: baseColor,
                        markerLength: 1,
                        showInvisibles: showInvisibles)

        // 4. Inline code: `code` — scale the monospace point size so its
        // x-height matches the body font's x-height (otherwise the mono font
        // reads visibly taller than surrounding text).
        let probe = NSFont.monospacedSystemFont(ofSize: baseFont.pointSize,
                                                weight: .regular)
        let xRatio = probe.xHeight > 0 ? baseFont.xHeight / probe.xHeight : 1.0
        // Mono fonts visually still look heftier than serifs even at matched
        // x-height (taller cap height + thicker stems). Nudge a bit further.
        let monoTrim: CGFloat = 0.9
        let monoFont = NSFont.monospacedSystemFont(
            ofSize: baseFont.pointSize * xRatio * monoTrim,
            weight: .regular
        )
        applyInlinePair(storage: storage,
                        text: text,
                        nsstr: nsstr,
                        fullRange: fullRange,
                        pattern: #"`([^`\n]+)`"#,
                        markerGroup: nil,
                        innerGroup: 1,
                        contentFont: monoFont,
                        contentBackground: NSColor.gray.withAlphaComponent(0.18),
                        baseColor: baseColor,
                        markerLength: 1,
                        showInvisibles: showInvisibles)
    }

    // MARK: - Headings

    private static func applyHeadings(storage: NSTextStorage,
                                      text: String,
                                      nsstr: NSString,
                                      baseFont: NSFont,
                                      baseColor: NSColor,
                                      fullRange: NSRange,
                                      showInvisibles: Bool) {
        // Heading scale per level (1..6). H1 biggest.
        let scales: [CGFloat] = [2.0, 1.6, 1.35, 1.2, 1.1, 1.05]
        guard let regex = try? NSRegularExpression(
            pattern: #"^(#{1,6})[ \t]"#,
            options: [.anchorsMatchLines]
        ) else { return }

        regex.enumerateMatches(in: text, range: fullRange) { match, _, _ in
            guard let match = match else { return }
            let hashRange = match.range(at: 1)
            let level = hashRange.length
            let scale = scales[max(0, min(level - 1, scales.count - 1))]
            let headingSize = baseFont.pointSize * scale
            let headingFont = NSFontManager.shared.convert(
                NSFont(name: baseFont.fontName, size: headingSize) ?? baseFont,
                toHaveTrait: .boldFontMask
            )

            // Apply heading font to the whole paragraph.
            let para = nsstr.paragraphRange(for: NSRange(location: match.range.location,
                                                        length: 0))
            // Don't clobber the foreground color — keep ink as set by global apply.
            storage.addAttribute(.font, value: headingFont, range: para)

            // De-emphasize the `#…` markers + the trailing space.
            let markerLen = hashRange.length + (match.range.length - hashRange.length)
            let markerRange = NSRange(location: match.range.location, length: markerLen)
            styleMarker(storage: storage,
                        range: markerRange,
                        baseColor: baseColor,
                        showInvisibles: showInvisibles,
                        dimSize: max(baseFont.pointSize * 0.75, 10))
        }
    }

    // MARK: - Inline pairs (bold/italic/code)

    /// Applies a content font to the inner group and dims the marker characters
    /// on each side. `markerLength` is used when there's no explicit
    /// marker capture group (e.g. italic where the marker is one char each side).
    private static func applyInlinePair(storage: NSTextStorage,
                                        text: String,
                                        nsstr: NSString,
                                        fullRange: NSRange,
                                        pattern: String,
                                        markerGroup: Int?,
                                        innerGroup: Int,
                                        contentFont: NSFont,
                                        contentBackground: NSColor? = nil,
                                        baseColor: NSColor,
                                        markerLength: Int = 0,
                                        showInvisibles: Bool) {
        guard let regex = try? NSRegularExpression(pattern: pattern,
                                                    options: []) else { return }

        regex.enumerateMatches(in: text, range: fullRange) { match, _, _ in
            guard let match = match else { return }
            let matchRange = match.range
            let innerRange = match.range(at: innerGroup)
            guard innerRange.location != NSNotFound else { return }

            // Inner content: apply the content font (and optional background).
            storage.addAttribute(.font, value: contentFont, range: innerRange)
            if let bg = contentBackground {
                storage.addAttribute(.backgroundColor, value: bg, range: innerRange)
            }

            // Marker characters: dim them.
            let lenLeft: Int
            let lenRight: Int
            if let markerGroup = markerGroup {
                let markerRange = match.range(at: markerGroup)
                lenLeft = markerRange.length
                lenRight = markerRange.length
            } else {
                lenLeft = markerLength
                lenRight = markerLength
            }

            let leftRange = NSRange(location: matchRange.location, length: lenLeft)
            let rightRange = NSRange(
                location: matchRange.location + matchRange.length - lenRight,
                length: lenRight
            )
            styleMarker(storage: storage,
                        range: leftRange,
                        baseColor: baseColor,
                        showInvisibles: showInvisibles)
            styleMarker(storage: storage,
                        range: rightRange,
                        baseColor: baseColor,
                        showInvisibles: showInvisibles)
        }
    }

    /// Either dims the marker (showInvisibles=true) or collapses it to a
    /// near-zero-width invisible glyph (showInvisibles=false).
    private static func styleMarker(storage: NSTextStorage,
                                    range: NSRange,
                                    baseColor: NSColor,
                                    showInvisibles: Bool,
                                    dimSize: CGFloat? = nil) {
        guard range.location != NSNotFound, range.length > 0 else { return }
        if showInvisibles {
            storage.addAttribute(.foregroundColor,
                                 value: baseColor.withAlphaComponent(0.35),
                                 range: range)
            if let dimSize = dimSize {
                storage.addAttribute(.font,
                                     value: NSFont.systemFont(ofSize: dimSize),
                                     range: range)
            }
        } else {
            // Hidden: clear ink and collapse to ~0pt so the markers take no
            // visible width.
            storage.addAttribute(.foregroundColor,
                                 value: NSColor.clear,
                                 range: range)
            storage.addAttribute(.font,
                                 value: NSFont.systemFont(ofSize: 0.01),
                                 range: range)
        }
    }

    // MARK: - Font helpers

    private static func bold(of font: NSFont) -> NSFont {
        NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
    }

    private static func italic(of font: NSFont) -> NSFont {
        NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
    }
}
