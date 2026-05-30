# Word&Page

A minimalist full-screen writing app for macOS. Like an old-fashioned typewriter, with the modern convenience of Delete, Undo, and a robust outliner.

## Features

- **Full-screen, distraction-free.** No toolbars. The system menu auto-hides; mouse to the top of the screen to reveal it.
- **Two round dials, lower-right.** Drag vertically to adjust **paper width** and **font size** on the fly. Both are visual-only and reset each launch.
- **Outliner.** Press `⌘]` at any line to start or deepen an outline; `⌘[` to outdent. Return continues the same level; Return on an empty outline line ends the outline. Sibling rows auto-renumber on insert / delete / indent / outdent.
- **Five outline styles**, live-switchable from Settings:
  - Decimal (`1`, `1.1`, `1.1.1`)
  - Legal (`1.`, `1.1.`, `1.1.1.`)
  - Alpha-numeric (`1`, `A`, `i`, `a`)
  - Harvard (`I.`, `A.`, `1.`, `a.`, `i.`)
  - Bulleted (`•`, `◦`, `▪`)
- **Custom backgrounds.** Drop in a photo for either the canvas or the paper from Settings → Appearance.
- **Persistent preferences.** Colors, font, line spacing, save behavior, outline style, and chosen images all persist via `UserDefaults` / Application Support.
- **Native `.wpage` format** preserves text plus per-paragraph outline structure.
- **Export to `.txt`, `.rtf`, `.pdf`** via the format picker in the Save dialog.

## Requirements

- macOS 26 (Tahoe) or newer
- Xcode 26+ (for building from source)

## Build

Open `Word&Page/Word&Page.xcodeproj` in Xcode and press `⌘R`.

If you'd prefer not to build from source, see [Releases](../../releases) for a packaged `.dmg`.

## Project layout

| File | Responsibility |
|---|---|
| `Word_PageApp.swift` | App entry; full-screen launch; File / Outline menu commands |
| `ContentView.swift` | Paper + knobs + image/color backdrops |
| `PaperView.swift` | `NSTextView` wrapper with outline keyboard handling, prefix rendering, indentation |
| `OutlineEngine.swift` | Path formatting per style; renumbering counter-stack; paragraph-style builder |
| `DocumentManager.swift` | New / Open / Save / Save As with format-picker dialog; `.txt` / `.rtf` / `.pdf` export |
| `Preferences.swift` | `@Observable` settings store with disk persistence + image overrides |
| `PreferencesView.swift` | Tabbed Settings window (Appearance / Typography / Behavior) |
| `Knob.swift` | Reusable circular vertical-drag dial control |

## License

Apache 2.0 — see [LICENSE](LICENSE).
