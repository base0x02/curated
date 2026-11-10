import AppKit
import SwiftUI

/// What's behind the sidebar and the queue in a window (Settings → Appearance).
enum PaneStyle: String, CaseIterable, Identifiable {
    /// The blur of whatever's behind the window.
    case glass
    /// The phones' drifting colors, in one of the `AuroraPalette.aurora` palettes.
    case aurora
    /// The same drifting colors in a holiday's palette (`AuroraPalette.holiday`).
    case holiday

    static let key = "paneStyle"
    var id: Self { self }
    var label: String {
        switch self {
        case .glass: "Transparent Glass"
        case .aurora: "Aurora"
        case .holiday: "Holiday"
        }
    }

    /// The palettes to pick from for this style, and where the pick is kept; none for glass.
    var palettes: [AuroraPalette] {
        switch self {
        case .glass: []
        case .aurora: AuroraPalette.aurora
        case .holiday: AuroraPalette.holiday
        }
    }
}

/// The aurora's colors: four blobs drifting over a near-black base (near-white in light mode).
struct AuroraPalette: Identifiable, Equatable {
    let id: String
    let name: String
    /// Each blob's color and how strong it is, in the order of `AuroraView`'s drifts.
    let blobs: [(NSColor, Double)]
    let darkBase: NSColor
    let lightBase: NSColor

    static let auroraKey = "auroraPalette"
    static let holidayKey = "holidayPalette"

    static func == (a: Self, b: Self) -> Bool { a.id == b.id }

    /// How strong the blobs are at full intensity. Light mode is stronger than it once was (0.4), so the colors don't
    /// wash out on the near-white base.
    static func strength(dark: Bool) -> Double { dark ? 0.6 : 0.7 }

    /// A blob's color as drawn: as is in dark mode; richer in light mode, where blending into white pales it.
    static func shade(_ color: NSColor, dark: Bool) -> NSColor {
        guard !dark, let rgb = color.usingColorSpace(.deviceRGB) else { return color }
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        rgb.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return NSColor(hue: h, saturation: min(1, s * 1.3), brightness: b * 0.92, alpha: a)
    }

    /// Picks `id` from `palettes`, or the first one.
    static func named(_ id: String, in palettes: [Self]) -> Self { palettes.first { $0.id == id } ?? palettes[0] }

    private static func rgb(_ r: Double, _ g: Double, _ b: Double) -> NSColor {
        NSColor(red: r, green: g, blue: b, alpha: 1)
    }

    private static let night = rgb(0.03, 0.03, 0.06), day = rgb(0.96, 0.96, 0.98)

    /// The logo's red and cyan and the app's blue, with a little violet: the phones' colors.
    static let curated = Self(id: "curated", name: "Curated", blobs: [
        (NSColor(Color.logoRed), 1), (NSColor(Color.logoCyan), 1), (NSColor(Color.curatedBlue), 1),
        (rgb(0.55, 0.3, 0.95), 0.7),
    ], darkBase: night, lightBase: day)

    static let aurora: [Self] = [
        curated,
        Self(id: "northernLights", name: "Northern Lights", blobs: [
            (rgb(0.2, 0.9, 0.5), 1), (rgb(0.1, 0.7, 0.8), 1), (rgb(0.5, 0.3, 0.9), 1), (rgb(0.15, 0.35, 0.85), 0.7),
        ], darkBase: rgb(0.02, 0.04, 0.06), lightBase: rgb(0.95, 0.97, 0.97)),
        Self(id: "ocean", name: "Ocean", blobs: [
            (rgb(0.0, 0.6, 0.7), 1), (rgb(0.3, 0.85, 0.9), 1), (rgb(0.05, 0.25, 0.75), 1), (rgb(0.2, 0.75, 0.55), 0.7),
        ], darkBase: rgb(0.02, 0.04, 0.07), lightBase: rgb(0.95, 0.97, 0.98)),
        Self(id: "sunset", name: "Sunset", blobs: [
            (rgb(1, 0.4, 0.35), 1), (rgb(1, 0.6, 0.2), 1), (rgb(0.85, 0.25, 0.6), 1), (rgb(0.45, 0.25, 0.8), 0.7),
        ], darkBase: rgb(0.06, 0.03, 0.05), lightBase: rgb(0.98, 0.96, 0.95)),
        Self(id: "forest", name: "Forest", blobs: [
            (rgb(0.35, 0.6, 0.25), 1), (rgb(0.8, 0.7, 0.3), 0.8), (rgb(0.1, 0.45, 0.3), 1), (rgb(0.55, 0.7, 0.55), 0.7),
        ], darkBase: rgb(0.03, 0.05, 0.03), lightBase: rgb(0.96, 0.97, 0.95)),
        Self(id: "blossom", name: "Blossom", blobs: [
            (rgb(1, 0.55, 0.7), 1), (rgb(0.75, 0.6, 0.95), 1), (rgb(0.9, 0.35, 0.5), 1), (rgb(1, 0.75, 0.6), 0.7),
        ], darkBase: rgb(0.06, 0.03, 0.05), lightBase: rgb(0.98, 0.96, 0.97)),
    ]

    static let holiday: [Self] = [
        // Glowing jack-o'-lanterns and lamps in a misty blue night.
        Self(id: "halloween", name: "Halloween", blobs: [
            (rgb(1, 0.45, 0.05), 1), (rgb(0.25, 0.4, 0.5), 1), (rgb(0.95, 0.3, 0.05), 0.9), (rgb(1, 0.7, 0.2), 0.7),
        ], darkBase: rgb(0.03, 0.05, 0.07), lightBase: rgb(0.97, 0.95, 0.92)),
        // A haunted house under a violet sky and a lavender moon, with a pumpkin's orange.
        Self(id: "halloween2", name: "Halloween 2", blobs: [
            (rgb(0.55, 0.25, 0.8), 1), (rgb(0.85, 0.75, 0.95), 0.9), (rgb(0.3, 0.1, 0.45), 1), (rgb(1, 0.6, 0.15), 0.6),
        ], darkBase: rgb(0.06, 0.03, 0.09), lightBase: rgb(0.97, 0.95, 0.99)),
        // Pumpkin, harvest gold, cranberry and brown on warm tan.
        Self(id: "thanksgiving", name: "Thanksgiving", blobs: [
            (rgb(0.9, 0.5, 0.15), 1), (rgb(0.95, 0.75, 0.3), 1), (rgb(0.75, 0.2, 0.15), 0.9), (rgb(0.5, 0.3, 0.15), 0.8),
        ], darkBase: rgb(0.07, 0.05, 0.03), lightBase: rgb(0.96, 0.92, 0.85)),
        // Red ornaments and golden bokeh on frosted blue pine.
        Self(id: "christmas1", name: "Christmas 1", blobs: [
            (rgb(0.8, 0.08, 0.12), 1), (rgb(1, 0.75, 0.4), 1), (rgb(0.45, 0.6, 0.75), 1), (rgb(0.15, 0.35, 0.3), 0.7),
        ], darkBase: rgb(0.03, 0.05, 0.08), lightBase: rgb(0.95, 0.96, 0.97)),
        // Red, green and white.
        Self(id: "christmas2", name: "Christmas 2", blobs: [
            (rgb(0.85, 0.1, 0.15), 1), (rgb(0.1, 0.6, 0.25), 1), (rgb(1, 1, 1), 0.7), (rgb(0.05, 0.4, 0.2), 0.8),
        ], darkBase: rgb(0.04, 0.05, 0.04), lightBase: rgb(0.96, 0.97, 0.96)),
        // Snowy whites and ice blues; the light base is a cool grey so the white still shows.
        Self(id: "christmas3", name: "Christmas 3", blobs: [
            (rgb(1, 1, 1), 1), (rgb(0.75, 0.88, 1), 1), (rgb(0.85, 0.88, 0.92), 1), (rgb(0.6, 0.75, 0.95), 0.8),
        ], darkBase: rgb(0.08, 0.1, 0.14), lightBase: rgb(0.86, 0.9, 0.95)),
    ]
}

/// Behind the sidebar and the queue: the blur of whatever's behind the window or the drifting colors, in the palette
/// picked in Settings. Full screen is always the colors (the Aurora palette, for glass), since there's nothing behind
/// the window to blur.
struct PaneBackground: View {
    @AppStorage(PaneStyle.key) private var style = PaneStyle.glass
    @AppStorage(AuroraPalette.auroraKey) private var auroraPalette = AuroraPalette.curated.id
    @AppStorage(AuroraPalette.holidayKey) private var holidayPalette = AuroraPalette.holiday[0].id
    @State private var fullScreen = false

    var body: some View {
        ZStack {
            if style == .holiday {
                AuroraBackground(intensity: 0.65, palette: .named(holidayPalette, in: AuroraPalette.holiday))
            } else if fullScreen || style == .aurora {
                AuroraBackground(intensity: 0.65, palette: .named(auroraPalette, in: AuroraPalette.aurora))
            } else {
                BehindWindowBlur()
            }
        }
        .background(FullScreenReader(fullScreen: $fullScreen))
    }
}

/// Keeps `fullScreen` in step with whether the window it's in is full screen.
private struct FullScreenReader: NSViewRepresentable {
    @Binding var fullScreen: Bool

    func makeNSView(context: Context) -> ReaderView {
        let view = ReaderView()
        view.onChange = { fullScreen = $0 }
        return view
    }

    func updateNSView(_ view: ReaderView, context: Context) {
        view.onChange = { fullScreen = $0 }
    }

    final class ReaderView: NSView {
        var onChange: ((Bool) -> Void)?
        private var observers: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            guard let window else { return }
            // "Will", so the colors are already there as the window grows into its space.
            for (name, value) in [(NSWindow.willEnterFullScreenNotification, true),
                                  (NSWindow.didExitFullScreenNotification, false)] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) {
                    [weak self] _ in self?.onChange?(value)
                })
            }
            let isFullScreen = window.styleMask.contains(.fullScreen)
            DispatchQueue.main.async { [weak self] in self?.onChange?(isFullScreen) }
        }

        deinit { observers.forEach(NotificationCenter.default.removeObserver) }
    }
}

extension Color {
    /// The app's blue (the system accent), as a fixed color for gradients. The same as on iOS.
    static let curatedBlue = Color(red: 0x0A / 255, green: 0x84 / 255, blue: 0xFF / 255)
}

/// Slow, blurred color drifting behind everything: by default the logo's red and cyan and the app's blue, on
/// near-black (or near-white in light mode), or another `AuroraPalette`. The iOS app's `AuroraBackground` (Onboarding.swift), with the same colors and motion, but
/// drawn with Core Animation so it moves without SwiftUI redrawing every frame. (A `TimelineView` doing that kept
/// clicks and hovers from reaching the player beside it.)
struct AuroraBackground: NSViewRepresentable {
    var intensity = 1.0
    var palette = AuroraPalette.curated

    func makeNSView(context: Context) -> AuroraView { AuroraView(intensity: intensity, palette: palette) }
    func updateNSView(_ view: AuroraView, context: Context) { view.palette = palette }
}

final class AuroraView: NSView {
    /// One axis of a blob's drift, as a fraction of the view: `center + amplitude * sin (or cos)(t / period)`.
    private struct Drift {
        let center, amplitude, period: Double
        var cosine = false

        func value(at t: Double) -> Double { center + amplitude * (cosine ? cos(t / period) : sin(t / period)) }
    }

    /// Where each blob drifts and how big it is; the palette gives their colors, in this order.
    private struct Path {
        let x, y: Drift
        let diameter: Double
    }

    private static let paths = [
        Path(x: Drift(center: 0.22, amplitude: 0.16, period: 7),
             y: Drift(center: 0.2, amplitude: 0.1, period: 9, cosine: true), diameter: 0.75),
        Path(x: Drift(center: 0.82, amplitude: 0.14, period: 8, cosine: true),
             y: Drift(center: 0.38, amplitude: 0.14, period: 6.5), diameter: 0.7),
        Path(x: Drift(center: 0.45, amplitude: 0.2, period: 11),
             y: Drift(center: 0.82, amplitude: 0.1, period: 7.5, cosine: true), diameter: 0.85),
        Path(x: Drift(center: 0.65, amplitude: 0.2, period: 13, cosine: true),
             y: Drift(center: 0.62, amplitude: 0.16, period: 10), diameter: 0.6),
    ]

    private let intensity: Double
    var palette: AuroraPalette {
        didSet { if palette != oldValue { rebuild() } }
    }
    private let blobLayer = CALayer()
    private var laidOutSize = CGSize.zero

    init(intensity: Double, palette: AuroraPalette) {
        self.intensity = intensity
        self.palette = palette
        super.init(frame: .zero)
        wantsLayer = true
        layerUsesCoreImageFilters = true
        blobLayer.filters = [CIFilter(name: "CIGaussianBlur", parameters: [kCIInputRadiusKey: 50])!]
        layer?.addSublayer(blobLayer)
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Top-down, like SwiftUI, so the blobs' y drift matches the phones'.
    override var isFlipped: Bool { true }

    /// Never takes clicks.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        if bounds.size != laidOutSize { rebuild() }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        rebuild()
    }

    /// Lays the blobs out for the view's size and colors, each drifting on its own path from where the phones' would
    /// be now.
    private func rebuild() {
        laidOutSize = bounds.size
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        layer?.backgroundColor = (dark ? palette.darkBase : palette.lightBase).cgColor
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        blobLayer.frame = bounds
        blobLayer.sublayers = nil
        let size = max(bounds.width, bounds.height)
        let alpha = AuroraPalette.strength(dark: dark) * intensity
        let now = Date.timeIntervalSinceReferenceDate
        for (blob, (base, opacity)) in zip(Self.paths, palette.blobs) {
            let color = AuroraPalette.shade(base, dark: dark)
            let diameter = size * blob.diameter
            let circle = CAGradientLayer()
            circle.type = .radial
            circle.startPoint = CGPoint(x: 0.5, y: 0.5)
            circle.endPoint = CGPoint(x: 1, y: 1)
            circle.colors = [color.withAlphaComponent(alpha * opacity).cgColor, color.withAlphaComponent(0).cgColor]
            circle.bounds = CGRect(x: 0, y: 0, width: diameter, height: diameter)
            circle.position = CGPoint(x: blob.x.value(at: now) * bounds.width, y: blob.y.value(at: now) * bounds.height)
            circle.add(drift(blob.x, length: bounds.width, key: "position.x", now: now), forKey: "x")
            circle.add(drift(blob.y, length: bounds.height, key: "position.y", now: now), forKey: "y")
            blobLayer.addSublayer(circle)
        }
        CATransaction.commit()
    }

    /// One full turn of `drift`, repeating forever, started where it is at `now`.
    private func drift(_ drift: Drift, length: Double, key: String, now: Double) -> CAAnimation {
        let steps = 48
        let duration = 2 * .pi * drift.period
        let animation = CAKeyframeAnimation(keyPath: key)
        animation.values = (0...steps).map { drift.value(at: Double($0) / Double(steps) * duration) * length }
        animation.calculationMode = .cubic
        animation.duration = duration
        animation.repeatCount = .infinity
        animation.timeOffset = now.truncatingRemainder(dividingBy: duration)
        animation.isRemovedOnCompletion = false
        return animation
    }
}
