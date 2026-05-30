//
//  Knob.swift
//  Word&Page
//

import SwiftUI

/// A circular, draggable dial. Drag in a rotational motion around the knob
/// to change the value. Travel is 270° (–135° at min, +135° at max).
struct Knob: View {
    @Binding var value: CGFloat
    let range: ClosedRange<CGFloat>
    let label: String
    var formatted: String? = nil
    var size: CGFloat = 64

    @State private var dragStartValue: CGFloat? = nil

    /// Vertical pixels required to sweep the full value range.
    private let pixelsPerFullSweep: CGFloat = 220

    private let startAngle: CGFloat = -.pi * 3 / 4
    private let endAngle: CGFloat = .pi * 3 / 4

    private var fraction: CGFloat {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return (value - range.lowerBound) / span
    }

    private var indicatorAngle: CGFloat {
        startAngle + fraction * (endAngle - startAngle)
    }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.18), Color.black.opacity(0.45)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Circle()
                    .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)

                ArcShape(start: startAngle, end: endAngle)
                    .stroke(Color.white.opacity(0.18),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .padding(5)

                ArcShape(start: startAngle, end: indicatorAngle)
                    .stroke(Color.white.opacity(0.75),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .padding(5)

                Circle()
                    .fill(Color.white)
                    .frame(width: 6, height: 6)
                    .offset(
                        x: cos(indicatorAngle) * (size / 2 - 12),
                        y: sin(indicatorAngle) * (size / 2 - 12)
                    )
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
            .gesture(rotationGesture)

            VStack(spacing: 1) {
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                Text(formatted ?? "\(Int(value))")
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
    }

    private var rotationGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { g in
                let start = dragStartValue ?? value
                if dragStartValue == nil { dragStartValue = value }
                let span = range.upperBound - range.lowerBound
                // Drag up (negative translation.height) increases the value.
                let delta = -g.translation.height / pixelsPerFullSweep * span
                let proposed = start + delta
                value = min(max(proposed, range.lowerBound), range.upperBound)
            }
            .onEnded { _ in dragStartValue = nil }
    }
}

private struct ArcShape: Shape {
    let start: CGFloat
    let end: CGFloat
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let radius = min(rect.width, rect.height) / 2
        p.addArc(
            center: CGPoint(x: rect.midX, y: rect.midY),
            radius: radius,
            startAngle: .radians(Double(start)),
            endAngle: .radians(Double(end)),
            clockwise: false
        )
        return p
    }
}
