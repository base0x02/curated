import SwiftUI

/// The end of a time-limited or Top mix, or of a creator's videos: the whole panel turns into a sunny morning. The sky fades in, hills roll up,
/// the sun pops up over them with a bounce, then the message and a few flowers. Clouds, birds and the sun's rays keep
/// moving after that. Takes no touches, so swiping back to the previous video still works. With Reduce Motion it
/// shows the finished scene, standing still.
struct SunshinePanel: View {
    let headline: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            let t = reduceMotion ? 30 : timeline.date.timeIntervalSince(start)
            ZStack {
                Canvas { context, size in Self.draw(&context, size: size, t: t) }
                    .opacity(ease(t, delay: 0, duration: 0.6))
                // A quarter of the free space above the message, the rest below it, over the sun.
                VStack(spacing: 12) {
                    Spacer(minLength: 0)
                    Text(headline)
                        .font(.custom("LilitaOne", size: 42, relativeTo: .largeTitle))
                        .foregroundStyle(.white)
                        .shadow(color: Color(red: 0.9, green: 0.32, blue: 0), radius: 0, y: 3)
                        .scaleEffect(max(0, spring(t, delay: 0.95, damping: 0.45, frequency: 14)))
                    Text("Time to enjoy some sunshine")
                        .font(.custom("LilitaOne", size: 26, relativeTo: .title2))
                        .foregroundStyle(Color(red: 1, green: 0.99, blue: 0.91))
                        .shadow(color: Color(red: 0.9, green: 0.32, blue: 0), radius: 0, y: 2)
                        .scaleEffect(max(0, spring(t, delay: 1.25, damping: 0.5, frequency: 14)))
                        .rotationEffect(.degrees((1 - spring(t, delay: 1.25, damping: 0.5, frequency: 14)) * -8))
                    Spacer(minLength: 0)
                    Spacer(minLength: 0)
                    Spacer(minLength: 0)
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .onAppear { start = Date() }
    }

    // MARK: Timing

    /// A spring from 0 to 1 that overshoots and settles, like SwiftUI's bouncy springs.
    private static func spring(_ t: Double, delay: Double, damping: Double, frequency: Double) -> Double {
        let time = t - delay
        guard time > 0 else { return 0 }
        let damped = frequency * (1 - damping * damping).squareRoot()
        let decay = exp(-damping * frequency * time)
        return 1 - decay * (cos(damped * time) + damping * frequency / damped * sin(damped * time))
    }

    private func spring(_ t: Double, delay: Double, damping: Double, frequency: Double) -> Double {
        Self.spring(t, delay: delay, damping: damping, frequency: frequency)
    }

    /// Ease-out from 0 to 1.
    private static func ease(_ t: Double, delay: Double, duration: Double) -> Double {
        let x = min(max((t - delay) / duration, 0), 1)
        return 1 - pow(1 - x, 3)
    }

    private func ease(_ t: Double, delay: Double, duration: Double) -> Double {
        Self.ease(t, delay: delay, duration: duration)
    }

    // MARK: Drawing

    private static let petals: [Color] = [
        Color(red: 1, green: 0.44, blue: 0.57), .white, Color(red: 0.73, green: 0.41, blue: 0.78),
        Color(red: 1, green: 0.54, blue: 0.4), Color(red: 1, green: 0.95, blue: 0.46),
    ]
    /// Where each flower sits on the front hill, as fractions of the width and of the height below the hill's top.
    private static let flowers: [(x: Double, y: Double)] = [
        (0.08, 0.55), (0.2, 0.3), (0.33, 0.7), (0.46, 0.42), (0.6, 0.72), (0.72, 0.35), (0.85, 0.62), (0.94, 0.28),
    ]

    private static func draw(_ context: inout GraphicsContext, size: CGSize, t: Double) {
        let w = Double(size.width), h = Double(size.height)
        let horizon = h * 0.74
        let full = CGRect(origin: .zero, size: size)
        context.fill(Path(full), with: .linearGradient(
            Gradient(stops: [
                .init(color: Color(red: 0.16, green: 0.71, blue: 0.96), location: 0),
                .init(color: Color(red: 0.51, green: 0.83, blue: 0.98), location: 0.55),
                .init(color: Color(red: 1, green: 0.88, blue: 0.7), location: 0.8),
            ]),
            startPoint: .zero, endPoint: CGPoint(x: 0, y: h)))

        let r = min(w, h) * 0.17
        // Clouds drift across behind the sun, wrapping around.
        let drift = t / 40
        drawCloud(&context, x: wrap(0.1 + drift, w, r * 2.4), y: h * 0.12, r: r * 0.45)
        drawCloud(&context, x: wrap(0.65 + drift * 1.6, w, r * 2.4), y: h * 0.22, r: r * 0.32)
        drawCloud(&context, x: wrap(0.4 + drift * 0.7, w, r * 2.4), y: h * 0.52, r: r * 0.38)

        // The sun: rises from behind the hills to just above them.
        let pulse = (sin(t * .pi / 1.8) + 1) / 2
        let sun = CGPoint(x: w / 2, y: horizon + r * 2.2 - spring(t, delay: 0.45, damping: 0.42, frequency: 7) * r * 3.3)
        context.fill(circle(sun, r * 3), with: .radialGradient(
            Gradient(colors: [Color(red: 1, green: 0.96, blue: 0.62).opacity(0.6), .clear]),
            center: sun, startRadius: 0, endRadius: r * 3))
        let turn = t / 24 * 2 * .pi
        for i in 0..<12 {
            let a = Double(i) * .pi / 6 + turn
            let outer = r * (i % 2 == 0 ? 1.75 : 1.5) + pulse * r * 0.12
            var ray = Path()
            ray.move(to: CGPoint(x: sun.x + cos(a) * r * 1.22, y: sun.y + sin(a) * r * 1.22))
            ray.addLine(to: CGPoint(x: sun.x + cos(a) * outer, y: sun.y + sin(a) * outer))
            context.stroke(ray, with: .color(Color(red: 1, green: 0.79, blue: 0.16)), style: StrokeStyle(lineWidth: r * 0.16, lineCap: .round))
        }
        let face = r * (1 + pulse * 0.03)
        context.fill(circle(sun, face), with: .radialGradient(
            Gradient(colors: [Color(red: 1, green: 0.96, blue: 0.62), Color(red: 1, green: 0.76, blue: 0.03), Color(red: 1, green: 0.6, blue: 0)]),
            center: sun, startRadius: 0, endRadius: face))
        drawFace(&context, sun, face)

        // Birds drift across, wrapping around.
        let flap = t / 0.7 * 2 * .pi
        let birdX = wrap(0.3 + drift * 3, w, r)
        drawBird(&context, CGPoint(x: birdX, y: h * 0.38), r * 0.22, flap)
        drawBird(&context, CGPoint(x: birdX + r * 0.6, y: h * 0.35), r * 0.17, flap + 1.3)
        drawBird(&context, CGPoint(x: birdX - r * 0.5, y: h * 0.41), r * 0.15, flap + 2.4)

        // Hills roll up from the bottom, covering the sun's start.
        var hills = context
        hills.translateBy(x: 0, y: (1 - ease(t, delay: 0.15, duration: 0.9)) * h * 0.4)
        var back = Path()
        back.move(to: CGPoint(x: 0, y: horizon - h * 0.01))
        back.addCurve(to: CGPoint(x: w, y: horizon - h * 0.05),
                      control1: CGPoint(x: w * 0.25, y: horizon - h * 0.09), control2: CGPoint(x: w * 0.55, y: horizon + h * 0.02))
        back.addLine(to: CGPoint(x: w, y: h * 1.5)); back.addLine(to: CGPoint(x: 0, y: h * 1.5)); back.closeSubpath()
        hills.fill(back, with: .color(Color(red: 0.61, green: 0.8, blue: 0.4)))
        let top = horizon + h * 0.06
        var front = Path()
        front.move(to: CGPoint(x: 0, y: top))
        front.addCurve(to: CGPoint(x: w, y: top - h * 0.03),
                       control1: CGPoint(x: w * 0.3, y: top - h * 0.07), control2: CGPoint(x: w * 0.7, y: top + h * 0.05))
        front.addLine(to: CGPoint(x: w, y: h * 1.5)); front.addLine(to: CGPoint(x: 0, y: h * 1.5)); front.closeSubpath()
        hills.fill(front, with: .color(Color(red: 0.26, green: 0.63, blue: 0.28)))
        let sway = sin(t * .pi / 1.4)
        for (i, flower) in flowers.enumerated() {
            let pop = max(0, spring(t, delay: 1.3 + Double(i) * 0.09, damping: 0.35, frequency: 20))
            drawFlower(&hills, CGPoint(x: w * flower.x, y: top + (h - top) * flower.y), r * 0.2 * pop,
                       petals[i % petals.count], degrees: sway * 8 * (i % 2 == 0 ? 1 : -1))
        }
    }

    /// An x position moving from left to right across the width, starting again off the left edge.
    private static func wrap(_ progress: Double, _ width: Double, _ margin: Double) -> Double {
        progress.truncatingRemainder(dividingBy: 1) * (width + margin * 2) - margin
    }

    private static func circle(_ center: CGPoint, _ r: Double) -> Path {
        Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
    }

    private static func drawFace(_ context: inout GraphicsContext, _ c: CGPoint, _ r: Double) {
        let brown = GraphicsContext.Shading.color(Color(red: 0.43, green: 0.3, blue: 0.25))
        context.fill(circle(CGPoint(x: c.x - r * 0.3, y: c.y - r * 0.12), r * 0.08), with: brown)
        context.fill(circle(CGPoint(x: c.x + r * 0.3, y: c.y - r * 0.12), r * 0.08), with: brown)
        let blush = GraphicsContext.Shading.color(Color(red: 1, green: 0.44, blue: 0.26).opacity(0.4))
        context.fill(circle(CGPoint(x: c.x - r * 0.5, y: c.y + r * 0.15), r * 0.13), with: blush)
        context.fill(circle(CGPoint(x: c.x + r * 0.5, y: c.y + r * 0.15), r * 0.13), with: blush)
        var smile = Path()
        smile.addArc(center: CGPoint(x: c.x, y: c.y + r * 0.05), radius: r * 0.3,
                     startAngle: .degrees(20), endAngle: .degrees(160), clockwise: false)
        context.stroke(smile, with: brown, style: StrokeStyle(lineWidth: r * 0.08, lineCap: .round))
    }

    private static func drawCloud(_ context: inout GraphicsContext, x: Double, y: Double, r: Double) {
        let white = GraphicsContext.Shading.color(.white)
        context.fill(circle(CGPoint(x: x, y: y), r), with: white)
        context.fill(circle(CGPoint(x: x + r * 1.1, y: y - r * 0.45), r * 1.3), with: white)
        context.fill(circle(CGPoint(x: x + r * 2.2, y: y), r * 0.95), with: white)
        context.fill(Path(roundedRect: CGRect(x: x, y: y - r * 0.2, width: r * 2.2, height: r * 1.2), cornerRadius: r * 0.6), with: white)
    }

    private static func drawBird(_ context: inout GraphicsContext, _ at: CGPoint, _ r: Double, _ phase: Double) {
        let lift = sin(phase) * r * 0.6
        var wing = Path()
        wing.move(to: CGPoint(x: at.x - r, y: at.y - lift))
        wing.addQuadCurve(to: at, control: CGPoint(x: at.x - r * 0.45, y: at.y - r * 0.5))
        wing.addQuadCurve(to: CGPoint(x: at.x + r, y: at.y - lift), control: CGPoint(x: at.x + r * 0.45, y: at.y - r * 0.5))
        context.stroke(wing, with: .color(Color(red: 0.22, green: 0.28, blue: 0.31)), style: StrokeStyle(lineWidth: r * 0.22, lineCap: .round))
    }

    private static func drawFlower(_ context: inout GraphicsContext, _ base: CGPoint, _ r: Double, _ color: Color, degrees: Double) {
        guard r > 0 else { return }
        var flower = context
        flower.translateBy(x: base.x, y: base.y)
        flower.rotate(by: .degrees(degrees))
        var stem = Path()
        stem.move(to: .zero)
        stem.addLine(to: CGPoint(x: 0, y: -r * 3))
        flower.stroke(stem, with: .color(Color(red: 0.18, green: 0.49, blue: 0.2)), style: StrokeStyle(lineWidth: r * 0.35, lineCap: .round))
        let head = CGPoint(x: 0, y: -r * 3)
        for i in 0..<5 {
            let a = Double(i) * 2 * .pi / 5
            flower.fill(circle(CGPoint(x: head.x + cos(a) * r * 0.7, y: head.y + sin(a) * r * 0.7), r * 0.6), with: .color(color))
        }
        flower.fill(circle(head, r * 0.45), with: .color(Color(red: 1, green: 0.7, blue: 0)))
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
