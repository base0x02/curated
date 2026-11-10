import SwiftUI

// Pictures drawn for Curated where no SF Symbol fits: the cleanup broom, the sound wave.

/// A broom mid-sweep, with a few sparkles where it's been: Automatic Cleanup's picture, white on a teal tile.
struct BroomGraphic: View {
    var size: CGFloat = 44

    var body: some View {
        let u = size / 44
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.25, green: 0.85, blue: 0.75), Color(red: 0.05, green: 0.6, blue: 0.6)],
                                     startPoint: .top, endPoint: .bottom))
            ZStack {
                // Handle, binding and bristles, drawn upright, then tipped into a sweep.
                Capsule().fill(.white).frame(width: 3.2 * u, height: 20 * u).offset(y: -9 * u)
                RoundedRectangle(cornerRadius: 1.2 * u).fill(.white).frame(width: 10 * u, height: 3.4 * u).offset(y: 2 * u)
                BristleShape().fill(.white).frame(width: 18 * u, height: 11 * u).offset(y: 9.5 * u)
                BristleShape().stroke(Color(red: 0.05, green: 0.6, blue: 0.6).opacity(0.55), lineWidth: 1 * u)
                    .frame(width: 18 * u, height: 11 * u).offset(y: 9.5 * u)
            }
            .rotationEffect(.degrees(32))
            .scaleEffect(0.92)
            .offset(x: 0.5 * u, y: 1.5 * u)
            Image(systemName: "sparkle").font(.system(size: 8 * u, weight: .bold)).foregroundStyle(.white)
                .offset(x: -12 * u, y: 11 * u)
            Image(systemName: "sparkle").font(.system(size: 5 * u, weight: .bold)).foregroundStyle(.white.opacity(0.85))
                .offset(x: -15 * u, y: 3 * u)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// A broom's head: narrow at the binding, flaring out to the bristle tips, with lines between the bristles.
private struct BristleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let top = rect.width * 0.28
        path.move(to: CGPoint(x: rect.midX - top, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX + top, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY), control: CGPoint(x: rect.maxX - rect.width * 0.08, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.midX - top, y: rect.minY), control: CGPoint(x: rect.minX + rect.width * 0.08, y: rect.midY))
        path.closeSubpath()
        return path
    }
}

/// A sound wave of white bars on a pink tile: uneven while volumes are left as they are, evened out while on.
struct WaveformGraphic: View {
    var evened: Bool
    var size: CGFloat = 44

    private static let rough: [CGFloat] = [0.25, 0.55, 0.95, 0.4, 0.8, 0.3, 0.6]
    private static let even: [CGFloat] = [0.45, 0.6, 0.65, 0.6, 0.65, 0.6, 0.45]

    var body: some View {
        let heights = evened ? Self.even : Self.rough
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 1, green: 0.4, blue: 0.6), Color(red: 0.75, green: 0.2, blue: 0.85)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            HStack(spacing: size * 0.045) {
                ForEach(heights.indices, id: \.self) { i in
                    Capsule().fill(.white).frame(width: size * 0.07, height: size * 0.62 * heights[i])
                }
            }
        }
        .frame(width: size, height: size)
        .animation(.spring(duration: 0.5, bounce: 0.3), value: evened)
        .accessibilityHidden(true)
    }
}
