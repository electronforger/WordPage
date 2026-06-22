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

        // 4a. Strikethrough: ~~text~~
        applyStrikethrough(storage: storage,
                           text: text,
                           fullRange: fullRange,
                           baseColor: baseColor,
                           showInvisibles: showInvisibles)

        // 4b. Blockquote: > text
        applyBlockquotes(storage: storage,
                         text: text,
                         nsstr: nsstr,
                         fullRange: fullRange,
                         baseFont: baseFont,
                         baseColor: baseColor,
                         showInvisibles: showInvisibles)

        // 4c. Links and images: [text](url) and ![alt](src)
        applyLinks(storage: storage,
                   text: text,
                   fullRange: fullRange,
                   baseColor: baseColor,
                   baseFont: baseFont,
                   showInvisibles: showInvisibles)

        // 4d. Line-start list markers: -, *, +, and 1. (when not already
        // handled by the outline system). Always dimmed (never collapsed)
        // since they're the structural cue for the line being a list item.
        applyListMarkers(storage: storage,
                         text: text,
                         fullRange: fullRange,
                         baseColor: baseColor)

        // 5. Inline code: `code` — scale the monospace point size so its
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

    // MARK: - Strikethrough

    private static func applyStrikethrough(storage: NSTextStorage,
                                           text: String,
                                           fullRange: NSRange,
                                           baseColor: NSColor,
                                           showInvisibles: Bool) {
        guard let regex = try? NSRegularExpression(
            pattern: #"~~([^~\n]+)~~"#,
            options: []
        ) else { return }
        regex.enumerateMatches(in: text, range: fullRange) { match, _, _ in
            guard let match = match else { return }
            let innerRange = match.range(at: 1)
            storage.addAttribute(.strikethroughStyle,
                                 value: NSUnderlineStyle.single.rawValue,
                                 range: innerRange)
            storage.addAttribute(.strikethroughColor,
                                 value: baseColor,
                                 range: innerRange)
            let leftRange = NSRange(location: match.range.location, length: 2)
            let rightRange = NSRange(
                location: match.range.location + match.range.length - 2,
                length: 2
            )
            styleMarker(storage: storage, range: leftRange,
                        baseColor: baseColor, showInvisibles: showInvisibles)
            styleMarker(storage: storage, range: rightRange,
                        baseColor: baseColor, showInvisibles: showInvisibles)
        }
    }

    // MARK: - Blockquotes

    private static func applyBlockquotes(storage: NSTextStorage,
                                         text: String,
                                         nsstr: NSString,
                                         fullRange: NSRange,
                                         baseFont: NSFont,
                                         baseColor: NSColor,
                                         showInvisibles: Bool) {
        guard let regex = try? NSRegularExpression(
            pattern: #"^>\s"#,
            options: [.anchorsMatchLines]
        ) else { return }

        let italicFont = italic(of: baseFont)
        let bigMarkerFont = NSFontManager.shared.convert(
            NSFont(name: baseFont.fontName,
                   size: baseFont.pointSize * 1.6) ?? baseFont,
            toHaveTrait: .boldFontMask
        )
        let accent = NSColor(srgbRed: 251.0 / 255.0,
                             green: 188.0 / 255.0,
                             blue: 95.0 / 255.0,
                             alpha: 1.0)

        regex.enumerateMatches(in: text, range: fullRange) { match, _, _ in
            guard let match = match else { return }
            let para = nsstr.paragraphRange(
                for: NSRange(location: match.range.location, length: 0)
            )

            // Hanging-indent paragraph style: the `>` glyph hangs near the
            // left margin; content is indented; wrapped lines align to the
            // content indent. Adds vertical breathing room above and below.
            let pStyle = NSMutableParagraphStyle()
            pStyle.firstLineHeadIndent = 8
            pStyle.headIndent = 44
            pStyle.paragraphSpacingBefore = baseFont.pointSize * 0.55
            pStyle.paragraphSpacing = baseFont.pointSize * 0.45
            storage.addAttribute(.paragraphStyle, value: pStyle, range: para)

            // Italicize + slightly mute the content past `> `.
            let contentStart = match.range.location + match.range.length
            let contentLen = max(0, para.location + para.length - contentStart)
            if contentLen > 0 {
                let contentRange = NSRange(location: contentStart,
                                           length: contentLen)
                storage.addAttribute(.font, value: italicFont, range: contentRange)
                storage.addAttribute(.foregroundColor,
                                     value: baseColor.withAlphaComponent(0.78),
                                     range: contentRange)
            }

            // The `>` itself becomes a large ghosted accent glyph — the visual
            // "quote mark" cue the user expected.
            let markerRange = NSRange(location: match.range.location, length: 1)
            storage.addAttribute(.font, value: bigMarkerFont, range: markerRange)
            storage.addAttribute(.foregroundColor,
                                 value: accent.withAlphaComponent(0.45),
                                 range: markerRange)

            // The space between `>` and content: respect the invisibles toggle.
            let trailing = NSRange(location: match.range.location + 1,
                                   length: 1)
            styleMarker(storage: storage, range: trailing,
                        baseColor: baseColor, showInvisibles: showInvisibles)
        }
    }

    // MARK: - Links and images

    private static func applyLinks(storage: NSTextStorage,
                                   text: String,
                                   fullRange: NSRange,
                                   baseColor: NSColor,
                                   baseFont: NSFont,
                                   showInvisibles: Bool) {
        let accent = NSColor(srgbRed: 251.0 / 255.0,
                             green: 188.0 / 255.0,
                             blue: 95.0 / 255.0,
                             alpha: 1.0)
        // Image:   !\[alt\]\(src\)
        // Link:    \[text\]\(url\)
        let combined = #"(!?)\[([^\]\n]+)\]\(([^)\n]+)\)"#
        guard let regex = try? NSRegularExpression(
            pattern: combined,
            options: []
        ) else { return }
        let italicFont = italic(of: baseFont)
        let nsstr = text as NSString
        regex.enumerateMatches(in: text, range: fullRange) { match, _, _ in
            guard let match = match else { return }
            let bang = match.range(at: 1)
            let inner = match.range(at: 2)
            let urlRange = match.range(at: 3)
            let isImage = bang.length > 0

            if isImage {
                // Image alt text — read as descriptive placeholder, not a link.
                // Italic + a muted grey distinguishes it from link text.
                storage.addAttribute(.font, value: italicFont, range: inner)
                storage.addAttribute(
                    .foregroundColor,
                    value: baseColor.withAlphaComponent(0.55),
                    range: inner
                )
            } else {
                // Link text — accent + underline + actually clickable.
                storage.addAttribute(.foregroundColor, value: accent, range: inner)
                storage.addAttribute(.underlineStyle,
                                     value: NSUnderlineStyle.single.rawValue,
                                     range: inner)
                storage.addAttribute(.underlineColor,
                                     value: accent.withAlphaComponent(0.7),
                                     range: inner)
                // Wire up the URL so the link is actually live.
                if urlRange.location != NSNotFound {
                    let urlText = nsstr.substring(with: urlRange)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if let url = URL(string: urlText) {
                        storage.addAttribute(.link, value: url, range: inner)
                    }
                }
            }

            // Dim the punctuation surrounding it: ! [ ] ( url )
            if bang.length > 0 {
                styleMarker(storage: storage, range: bang,
                            baseColor: baseColor, showInvisibles: showInvisibles)
            }
            let openBracket = NSRange(location: inner.location - 1, length: 1)
            let closeBracket = NSRange(location: inner.location + inner.length,
                                       length: 1)
            let openParen = NSRange(location: closeBracket.location + 1,
                                    length: 1)
            let closeParen = NSRange(
                location: match.range.location + match.range.length - 1,
                length: 1
            )
            styleMarker(storage: storage, range: openBracket,
                        baseColor: baseColor, showInvisibles: showInvisibles)
            styleMarker(storage: storage, range: closeBracket,
                        baseColor: baseColor, showInvisibles: showInvisibles)
            styleMarker(storage: storage, range: openParen,
                        baseColor: baseColor, showInvisibles: showInvisibles)
            styleMarker(storage: storage, range: closeParen,
                        baseColor: baseColor, showInvisibles: showInvisibles)
            styleMarker(storage: storage, range: urlRange,
                        baseColor: baseColor, showInvisibles: showInvisibles)
        }
    }

    // MARK: - Line-start list markers

    /// Dims `-`, `*`, `+`, and `\d+.` markers at the start of a line so
    /// manually typed lists still read like lists. Always dim — never
    /// collapsed — since the marker is the only cue that the line is a list.
    private static func applyListMarkers(storage: NSTextStorage,
                                         text: String,
                                         fullRange: NSRange,
                                         baseColor: NSColor) {
        // Bullets
        if let bulletRegex = try? NSRegularExpression(
            pattern: #"^[ \t]*([-*+]) "#,
            options: [.anchorsMatchLines]
        ) {
            bulletRegex.enumerateMatches(in: text, range: fullRange) { match, _, _ in
                guard let match = match else { return }
                let markerRange = match.range(at: 1)
                let trailing = NSRange(
                    location: markerRange.location + markerRange.length,
                    length: 1
                )
                dim(storage: storage, range: markerRange, baseColor: baseColor)
                dim(storage: storage, range: trailing, baseColor: baseColor)
            }
        }
        // Numbered
        if let numRegex = try? NSRegularExpression(
            pattern: #"^[ \t]*(\d+\.) "#,
            options: [.anchorsMatchLines]
        ) {
            numRegex.enumerateMatches(in: text, range: fullRange) { match, _, _ in
                guard let match = match else { return }
                let markerRange = match.range(at: 1)
                let trailing = NSRange(
                    location: markerRange.location + markerRange.length,
                    length: 1
                )
                dim(storage: storage, range: markerRange, baseColor: baseColor)
                dim(storage: storage, range: trailing, baseColor: baseColor)
            }
        }
    }

    private static func dim(storage: NSTextStorage,
                            range: NSRange,
                            baseColor: NSColor) {
        guard range.location != NSNotFound, range.length > 0 else { return }
        storage.addAttribute(.foregroundColor,
                             value: baseColor.withAlphaComponent(0.35),
                             range: range)
    }

    // MARK: - Font helpers

    private static func bold(of font: NSFont) -> NSFont {
        NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
    }

    private static func italic(of font: NSFont) -> NSFont {
        NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
    }
}
