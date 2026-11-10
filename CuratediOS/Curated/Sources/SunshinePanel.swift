import SwiftUI

/// The end of a time-limited or Top mix, or of a creator's videos: the whole panel turns into a quiet daybreak. It opens
/// on a twilight sky with a few stars; over about three seconds the sun rises from behind layered hills, the sky warms
/// to morning and the stars fade, then the message fades up. After that only the clouds drift and the sun's glow
/// breathes, slowly. Takes no touches, so swiping back to the previous video still works. With Reduce Motion it shows
/// the finished scene, standing still. Android's `SunshinePanel.kt` draws the same scene.
struct SunshinePanel: View {
    let headline: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            let t = reduceMotion ? 30 : timeline.date.timeIntervalSince(start)
            ZStack {
                Canvas { context, size in Self.draw(&context, size: size, t: t) }
                    .opacity(Self.ease(t, delay: 0, duration: 0.8))
                // A quarter of the free space above the message, the rest below it, over the sun.
                VStack(spacing: 10) {
                    Spacer(minLength: 0)
                    let title = Self.ease(t, delay: 1.8, duration: 1.2)
                    Text(headline)
                        .font(.system(.largeTitle, weight: .semibold))
                        .foregroundStyle(.white)
                        .opacity(title)
                        .offset(y: (1 - title) * 10)
                    let subtitle = Self.ease(t, delay: 2.3, duration: 1.2)
                    Text("Time to enjoy some sunshine")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.85))
                        .opacity(subtitle)
                        .offset(y: (1 - subtitle) * 10)
                    Spacer(minLength: 0)
                    Spacer(minLength: 0)
                    Spacer(minLength: 0)
                }
                .shadow(color: .black.opacity(0.18), radius: 10, y: 2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .onAppear { start = Date() }
    }

    // MARK: Timing

    /// Ease-out from 0 to 1.
    static func ease(_ t: Double, delay: Double, duration: Double) -> Double {
        let x = min(max((t - delay) / duration, 0), 1)
        return 1 - pow(1 - x, 3)
    }

    /// Ease-in-out from 0 to 1, for the sunrise: it starts and settles gently.
    static func easeInOut(_ t: Double, delay: Double, duration: Double) -> Double {
        let x = min(max((t - delay) / duration, 0), 1)
        return x * x * (3 - 2 * x)
    }

    // MARK: Colors

    /// A color that can be mixed, so the scene can move from twilight to morning.
    struct RGB {
        let r, g, b: Double
        init(_ r: Double, _ g: Double, _ b: Double) { self.r = r; self.g = g; self.b = b }
        func mix(_ other: RGB, _ amount: Double) -> RGB {
            RGB(r + (other.r - r) * amount, g + (other.g - g) * amount, b + (other.b - b) * amount)
        }
        var color: Color { Color(red: r, green: g, blue: b) }
        func color(_ opacity: Double) -> Color { Color(red: r, green: g, blue: b).opacity(opacity) }
    }

    // Twilight → morning.
    static let skyTop = (RGB(0.08, 0.11, 0.24), RGB(0.35, 0.57, 0.80))
    static let skyMiddle = (RGB(0.22, 0.22, 0.40), RGB(0.63, 0.76, 0.89))
    static let skyHorizon = (RGB(0.55, 0.36, 0.44), RGB(1.00, 0.84, 0.67))
    /// Back to front, each with a twilight and a morning color. The farther ones fade into the haze.
    static let hills: [(night: RGB, day: RGB, base: Double, height: Double, haze: Double, seed: Double)] = [
        (RGB(0.28, 0.25, 0.39), RGB(0.56, 0.66, 0.66), -0.02, 0.025, 0.45, 1.3),
        (RGB(0.17, 0.17, 0.29), RGB(0.34, 0.50, 0.44), 0.045, 0.03, 0.2, 4.1),
        (RGB(0.09, 0.10, 0.17), RGB(0.17, 0.32, 0.27), 0.12, 0.035, 0, 7.7),
    ]
    static let sunCore = RGB(1, 0.98, 0.90)
    static let sunEdge = RGB(1, 0.85, 0.55)
    static let glow = RGB(1, 0.80, 0.55)

    // MARK: Drawing

    static func draw(_ context: inout GraphicsContext, size: CGSize, t: Double) {
        let w = Double(size.width), h = Double(size.height)
        let horizon = h * 0.72
        // How far the morning has come: 0 at twilight, 1 once the sun is up.
        let light = easeInOut(t, delay: 0.2, duration: 3.4)
        let top = skyTop.0.mix(skyTop.1, light)
        let middle = skyMiddle.0.mix(skyMiddle.1, light)
        let low = skyHorizon.0.mix(skyHorizon.1, light)
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(
            Gradient(stops: [.init(color: top.color, location: 0), .init(color: middle.color, location: 0.5),
                             .init(color: low.color, location: 0.74)]),
            startPoint: .zero, endPoint: CGPoint(x: 0, y: h)))

        // Stars, fading as it gets light.
        let stars = 1 - ease(t, delay: 0.4, duration: 2.4)
        if stars > 0 {
            for i in 0..<28 {
                let x = noise(Double(i) * 1.7) * w
                let y = noise(Double(i) * 3.1 + 0.5) * h * 0.5
                let size = 0.6 + noise(Double(i) * 5.3) * 0.9
                let twinkle = 0.75 + 0.25 * sin(t * 1.3 + Double(i))
                context.fill(circle(CGPoint(x: x, y: y), size), with: .color(.white.opacity(0.75 * stars * twinkle)))
            }
        }

        // The sun's glow and the sun, rising from behind the hills.
        let r = min(w, h) * 0.085
        let sun = CGPoint(x: w / 2, y: horizon + r * 1.6 - light * (r * 1.6 + h * 0.11))
        let breathe = 1 + 0.04 * sin(t * 2 * .pi / 8)
        let glowRadius = r * 6 * breathe
        context.fill(circle(sun, glowRadius), with: .radialGradient(
            Gradient(colors: [glow.color(0.55 * light), glow.color(0.18 * light), .clear]),
            center: sun, startRadius: 0, endRadius: glowRadius))
        context.fill(circle(sun, r * 1.25), with: .radialGradient(
            Gradient(colors: [sunEdge.color(0.5), sunEdge.color(0)]), center: sun, startRadius: r * 0.9, endRadius: r * 1.25))
        context.fill(circle(sun, r), with: .radialGradient(
            Gradient(colors: [sunCore.color, sunCore.color, sunEdge.color]), center: sun, startRadius: 0, endRadius: r))

        // Soft wisps of cloud, catching the light as it comes.
        let cloud = RGB(0.62, 0.55, 0.72).mix(RGB(1, 0.95, 0.90), light)
        let drift = t / 150
        drawWisp(&context, x: wrap(0.18 + drift, w, r * 4), y: h * 0.2, r: r, color: cloud)
        drawWisp(&context, x: wrap(0.7 + drift * 1.4, w, r * 4), y: h * 0.33, r: r * 0.75, color: cloud)

        // The hills, back to front, rising a little into place (the far ones less, for depth).
        for (i, hill) in hills.enumerated() {
            let rise = (1 - ease(t, delay: 0.1 * Double(i), duration: 1.8)) * h * 0.03 * Double(i + 1)
            let color = hill.night.mix(hill.day, light).mix(low, hill.haze)
            context.fill(ridge(w: w, h: h, base: horizon + h * hill.base + rise, height: h * hill.height, seed: hill.seed),
                         with: .color(color.color))
            // Morning haze lying in front of the far hills.
            if i == 0 {
                let band = horizon + h * 0.02
                context.fill(Path(CGRect(x: 0, y: band - h * 0.06, width: w, height: h * 0.12)), with: .linearGradient(
                    Gradient(colors: [low.color(0), low.color(0.35 * light), low.color(0)]),
                    startPoint: CGPoint(x: 0, y: band - h * 0.06), endPoint: CGPoint(x: 0, y: band + h * 0.06)))
            }
        }
    }

    /// A gently rolling hilltop at `base`, filled down past the bottom of the panel.
    private static func ridge(w: Double, h: Double, base: Double, height: Double, seed: Double) -> Path {
        var path = Path()
        let steps = max(Int(w / 6), 24)
        for step in 0...steps {
            let x = w * Double(step) / Double(steps)
            let u = x / w * 2 * .pi
            let y = base - height * (0.6 * sin(u * 0.9 + seed) + 0.4 * sin(u * 2.3 + seed * 1.7))
            if step == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        path.addLine(to: CGPoint(x: w, y: h * 1.5))
        path.addLine(to: CGPoint(x: 0, y: h * 1.5))
        path.closeSubpath()
        return path
    }

    /// A long, soft-edged streak of cloud.
    private static func drawWisp(_ context: inout GraphicsContext, x: Double, y: Double, r: Double, color: RGB) {
        for (dx, dy, scale, opacity) in [(0.0, 0.0, 1.0, 0.45), (r * 1.4, r * 0.25, 0.7, 0.35)] {
            var layer = context
            layer.translateBy(x: x + dx, y: y + dy)
            layer.scaleBy(x: 1, y: 0.16)
            let radius = r * 3 * scale
            layer.fill(circle(.zero, radius), with: .radialGradient(
                Gradient(colors: [color.color(opacity), color.color(0)]), center: .zero, startRadius: 0, endRadius: radius))
        }
    }

    /// A steady pseudo-random number from 0 to 1, so the stars sit in the same places on every frame.
    private static func noise(_ seed: Double) -> Double {
        let x = sin(seed * 12.9898) * 43758.5453
        return x - x.rounded(.down)
    }

    /// An x position moving from left to right across the width, starting again off the left edge.
    private static func wrap(_ progress: Double, _ width: Double, _ margin: Double) -> Double {
        progress.truncatingRemainder(dividingBy: 1) * (width + margin * 2) - margin
    }

    private static func circle(_ center: CGPoint, _ r: Double) -> Path {
        Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
    }
}

extension Playback {
    /// Whether the queue ends with the sunshine panel (a time-limited or Top mix, or a creator) rather than the
    /// caught-up card.
    var endsInSunshine: Bool {
        if timeLimitMinutes != nil || mode?.topLimit != nil { return true }
        switch mode {
        case .creator, .longCreator: return true
        default: return false
        }
    }
}
