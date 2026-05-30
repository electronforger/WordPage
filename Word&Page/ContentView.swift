//
//  ContentView.swift
//  Word&Page
//

import SwiftUI

struct ContentView: View {
    @Environment(Preferences.self) private var prefs
    @State private var text: String = ""

    /// Transient knob state — never persisted. Paper width starts at 850 every
    /// launch; font size starts at the persisted Preferences value.
    @State private var paperWidth: CGFloat = 850
    @State private var fontSizeOverride: CGFloat? = nil

    private var effectiveFontSize: CGFloat {
        fontSizeOverride ?? prefs.fontSize
    }

    var body: some View {
        @Bindable var prefs = prefs
        ZStack {
            PaperView(
                outlineStyle: prefs.outlineStyle,
                lineSpacing: prefs.lineSpacing,
                fontName: prefs.fontName,
                fontSize: effectiveFontSize,
                inkColor: prefs.inkColor,
                text: $text
            )
            .frame(width: paperWidth)
            .background { paperBackdrop }
            .clipped()
            .shadow(color: .black.opacity(0.35), radius: 18, y: 6)
            .animation(.easeOut(duration: 0.12), value: paperWidth)

            GeometryReader { proxy in
                VStack(spacing: 22) {
                    Knob(
                        value: $paperWidth,
                        range: prefs.paperWidthRange,
                        label: "WIDTH",
                        formatted: "\(Int(paperWidth))"
                    )
                    Knob(
                        value: Binding(
                            get: { effectiveFontSize },
                            set: { fontSizeOverride = $0 }
                        ),
                        range: prefs.fontSizeRange,
                        label: "SIZE",
                        formatted: "\(Int(effectiveFontSize))pt"
                    )
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.black.opacity(0.18))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
                        )
                )
                .position(
                    x: proxy.size.width - 70,
                    y: proxy.size.height * 0.72
                )
            }
        }
        .background { canvasBackdrop }
        .onChange(of: prefs.fontSize) { _, _ in
            // Slider in Settings is the source of truth — drop any knob override.
            fontSizeOverride = nil
        }
    }

    @ViewBuilder
    private var canvasBackdrop: some View {
        Group {
            if let img = prefs.backgroundImage {
                Image(nsImage: img)
                    .resizable()
                    .scaledToFill()
            } else {
                prefs.backgroundColor
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var paperBackdrop: some View {
        Group {
            if let img = prefs.paperImage {
                Image(nsImage: img)
                    .resizable()
                    .scaledToFill()
            } else {
                prefs.paperColor
            }
        }
        .allowsHitTesting(false)
    }
}

#Preview {
    ContentView()
        .environment(Preferences())
        .frame(width: 1200, height: 800)
}
