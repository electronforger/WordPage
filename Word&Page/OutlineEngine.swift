//
//  OutlineEngine.swift
//  Word&Page
//

import AppKit

extension NSAttributedString.Key {
    static let outlinePath = NSAttributedString.Key("wp.outlinePath")
}

enum OutlineEngine {

    // MARK: - Indentation

    static let indentPointsPerLevel: CGFloat = 28
    /// Approximate visual width of a prefix; wrapped content aligns past this.
    static let hangingIndentAfterPrefix: CGFloat = 26

    /// Paragraph style for an outline line at the given depth.
    static func paragraphStyle(forDepth depth: Int, lineSpacing: CGFloat) -> NSParagraphStyle {
        let s = NSMutableParagraphStyle()
        s.lineSpacing = lineSpacing
        let leading = CGFloat(max(depth - 1, 0)) * indentPointsPerLevel
        s.firstLineHeadIndent = leading
        s.headIndent = leading + hangingIndentAfterPrefix
        return s
    }

    /// Default paragraph style for non-outline (plain) paragraphs.
    static func defaultParagraphStyle(lineSpacing: CGFloat) -> NSParagraphStyle {
        let s = NSMutableParagraphStyle()
        s.lineSpacing = lineSpacing
        return s
    }

    // MARK: - Reading state

    /// The outline path stored on the paragraph that contains `location`, if any.
    static func path(in storage: NSTextStorage, at location: Int) -> [Int]? {
        guard storage.length > 0 else { return nil }
        let safeLoc = min(max(location, 0), storage.length - 1)
        let para = (storage.string as NSString).paragraphRange(
            for: NSRange(location: safeLoc, length: 0)
        )
        guard para.length > 0 else { return nil }
        return storage.attribute(.outlinePath, at: para.location, effectiveRange: nil) as? [Int]
    }

    /// The path stored on the paragraph that immediately precedes `location`, if any.
    static func previousPath(in storage: NSTextStorage, before location: Int) -> [Int]? {
        let nsstr = storage.string as NSString
        let currentPara = nsstr.paragraphRange(for: NSRange(location: location, length: 0))
        guard currentPara.location > 0 else { return nil }
        let prevLoc = currentPara.location - 1
        return path(in: storage, at: prevLoc)
    }

    /// How many leading characters of `paragraph` are the rendered outline prefix.
    /// Returns 0 if the paragraph isn't an outline line.
    static func currentPrefixLength(in storage: NSTextStorage, paragraph: NSRange) -> Int {
        guard paragraph.length > 0,
              storage.attribute(.outlinePath, at: paragraph.location, effectiveRange: nil) != nil
        else { return 0 }
        let nsstr = storage.string as NSString
        var i = paragraph.location
        let end = paragraph.location + paragraph.length
        // Walk forward until first space; the prefix is everything up to and including it.
        while i < end && nsstr.character(at: i) != 0x20 /* space */ {
            i += 1
        }
        if i < end { i += 1 } // include the space
        return i - paragraph.location
    }

    // MARK: - Sequential renumbering

    /// Walks the given paths in document order and returns a parallel array of
    /// paths renumbered sequentially within each level (siblings: 1, 2, 3 ...).
    /// Depth of each path is preserved.
    static func renumber(paths: [[Int]]) -> [[Int]] {
        var counters: [Int] = []
        var result: [[Int]] = []
        for old in paths {
            let depth = max(old.count, 1)
            if counters.count < depth {
                while counters.count < depth - 1 {
                    counters.append(1)
                }
                counters.append(1)
            } else if counters.count == depth {
                counters[depth - 1] += 1
            } else {
                counters = Array(counters.prefix(depth))
                counters[depth - 1] += 1
            }
            result.append(Array(counters))
        }
        return result
    }

    // MARK: - Formatting

    static func format(_ path: [Int], style: OutlineStyle) -> String {
        switch style {
        case .decimal:
            return path.map(String.init).joined(separator: ".")
        case .legal:
            return path.map(String.init).joined(separator: ".") + "."
        case .alphaNumeric:
            // Per-level glyph: 1, A, i, a, then cycle.
            let glyphs: [(Int) -> String] = [
                { String($0) },
                { toLetters($0).uppercased() },
                { toRoman($0).lowercased() },
                { toLetters($0).lowercased() }
            ]
            let depth = max(path.count - 1, 0)
            let f = glyphs[depth % glyphs.count]
            return f(path.last ?? 1)
        case .harvard:
            // Per-level glyph: I., A., 1., a., i., then cycle. Trailing period.
            let glyphs: [(Int) -> String] = [
                { toRoman($0).uppercased() },
                { toLetters($0).uppercased() },
                { String($0) },
                { toLetters($0).lowercased() },
                { toRoman($0).lowercased() }
            ]
            let depth = max(path.count - 1, 0)
            let f = glyphs[depth % glyphs.count]
            return f(path.last ?? 1) + "."
        case .bulleted:
            let bullets = ["•", "◦", "▪", "▫"]
            return bullets[(max(path.count, 1) - 1) % bullets.count]
        case .markdownBullet:
            // Visible prefix is just "-"; indentation is supplied via paragraph
            // style. Whitespace nesting is added on .md save.
            return "-"
        case .markdownNumbered:
            return "\(path.last ?? 1)."
        }
    }

    // MARK: - Helpers

    private static func toLetters(_ n: Int) -> String {
        var n = n, s = ""
        while n > 0 {
            n -= 1
            s = String(UnicodeScalar(65 + (n % 26))!) + s
            n /= 26
        }
        return s.isEmpty ? "A" : s
    }

    private static func toRoman(_ n: Int) -> String {
        let pairs: [(Int, String)] = [
            (1000,"M"),(900,"CM"),(500,"D"),(400,"CD"),
            (100,"C"),(90,"XC"),(50,"L"),(40,"XL"),
            (10,"X"),(9,"IX"),(5,"V"),(4,"IV"),(1,"I")
        ]
        var n = n, s = ""
        for (v, sym) in pairs {
            while n >= v { s += sym; n -= v }
        }
        return s.isEmpty ? "I" : s
    }
}
