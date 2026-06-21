//
//  DocumentMode.swift
//  Word&Page
//

import Foundation

/// Which engine governs the open document — controls the native file format,
/// the outline-prefix syntax, and the format picker contents.
enum DocumentMode: String, CaseIterable, Codable, Identifiable {
    case text
    case markdown

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .text: "Text"
        case .markdown: "Markdown"
        }
    }
}
