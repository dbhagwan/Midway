import SwiftUI

/// Vector silhouette of the Snapchat ghost for the Login Kit and Creative
/// Kit buttons. NOTE: before shipping, swap for Snap's official button
/// assets per their brand guidelines — this is a faithful placeholder so
/// the button reads correctly in development builds.
struct SnapGhostShape: Shape {
    func path(in rect: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }

        // Right half, top-center → bottom-center; the left half mirrors it.
        let segments: [(CGPoint, CGPoint, CGPoint)] = [
            // (control1, control2, destination)
            (p(0.66, 0.02), p(0.78, 0.12), p(0.78, 0.30)),   // dome
            (p(0.78, 0.42), p(0.78, 0.50), p(0.79, 0.57)),   // side
            (p(0.82, 0.61), p(0.94, 0.63), p(0.96, 0.68)),   // wing out
            (p(0.98, 0.74), p(0.89, 0.79), p(0.78, 0.79)),   // wing curl
            (p(0.71, 0.79), p(0.71, 0.92), p(0.62, 0.92)),   // lobe
            (p(0.55, 0.92), p(0.56, 0.84), p(0.50, 0.84)),   // center notch
        ]

        func mirror(_ point: CGPoint) -> CGPoint {
            CGPoint(x: rect.minX + rect.maxX - point.x, y: point.y)
        }

        var path = Path()
        let start = p(0.50, 0.02)
        path.move(to: start)
        var current = start
        var drawn: [(from: CGPoint, c1: CGPoint, c2: CGPoint)] = []
        for (c1, c2, destination) in segments {
            path.addCurve(to: destination, control1: c1, control2: c2)
            drawn.append((current, c1, c2))
            current = destination
        }
        for segment in drawn.reversed() {
            path.addCurve(to: mirror(segment.from),
                          control1: mirror(segment.c2),
                          control2: mirror(segment.c1))
        }
        path.closeSubpath()
        return path
    }
}

/// The ghost glyph styled like the app icon: white fill, hairline outline.
struct SnapGhostGlyph: View {
    var size: CGFloat = 20

    var body: some View {
        ZStack {
            SnapGhostShape()
                .fill(.white)
            SnapGhostShape()
                .stroke(.black, lineWidth: max(1, size * 0.06))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

#Preview {
    HStack(spacing: 20) {
        SnapGhostGlyph(size: 20)
        SnapGhostGlyph(size: 44)
        SnapGhostGlyph(size: 88)
    }
    .padding(40)
    .background(Color(red: 1, green: 0.99, blue: 0))
}
