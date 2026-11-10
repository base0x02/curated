import SwiftUI
import UIKit

// The aurora's palettes and the holiday wordmarks, as on the Mac (Aurora.swift and LogoView there) and Android
// (Themes.kt).

/// What's behind Home: the aurora in one of its palettes, or in a holiday's.
enum BackgroundStyle: String, CaseIterable, Identifiable {
    case aurora, holiday

    var id: Self { self }
    var label: String { self == .aurora ? "Aurora" : "Holiday" }
    var palettes: [AuroraPalette] { self == .aurora ? AuroraPalette.aurora : AuroraPalette.holiday }
}

/// The aurora's colors: four blobs drifting over a near-black base (near-white in light mode).
struct AuroraPalette: Identifiable, Equatable {
    let id: String
    let name: String
    /// Each blob's color and how strong it is, in the order of `AuroraBackground`'s drifts.
    let blobs: [(UIColor, Double)]
    let darkBase: Color
    let lightBase: Color

    static func == (a: Self, b: Self) -> Bool { a.id == b.id }

    /// Picks `id` from `palettes`, or the first one.
    static func named(_ id: String?, in palettes: [Self]) -> Self { palettes.first { $0.id == id } ?? palettes[0] }

    /// How strong the blobs are at full intensity; light mode is stronger so the colors don't wash out.
    static func strength(dark: Bool) -> Double { dark ? 0.6 : 0.7 }

    /// A blob's color as drawn: as is in dark mode; richer in light mode, where blending into white pales it.
    static func shade(_ color: UIColor, dark: Bool) -> Color {
        guard !dark else { return Color(color) }
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return Color(UIColor(hue: h, saturation: min(1, s * 1.3), brightness: b * 0.92, alpha: a))
    }

    private static func rgb(_ r: Double, _ g: Double, _ b: Double) -> UIColor {
        UIColor(red: r, green: g, blue: b, alpha: 1)
    }

    private static func base(_ r: Double, _ g: Double, _ b: Double) -> Color { Color(red: r, green: g, blue: b) }

    /// The logo's red and cyan and the app's blue, with a little violet.
    static let curated = Self(id: "curated", name: "Curated", blobs: [
        (UIColor(Color.logoRed), 1), (UIColor(Color.logoCyan), 1), (UIColor(Color.curatedBlue), 1),
        (rgb(0.55, 0.3, 0.95), 0.7),
    ], darkBase: base(0.03, 0.03, 0.06), lightBase: base(0.96, 0.96, 0.98))

    static let aurora: [Self] = [
        curated,
        Self(id: "northernLights", name: "Northern Lights", blobs: [
            (rgb(0.2, 0.9, 0.5), 1), (rgb(0.1, 0.7, 0.8), 1), (rgb(0.5, 0.3, 0.9), 1), (rgb(0.15, 0.35, 0.85), 0.7),
        ], darkBase: base(0.02, 0.04, 0.06), lightBase: base(0.95, 0.97, 0.97)),
        Self(id: "ocean", name: "Ocean", blobs: [
            (rgb(0.0, 0.6, 0.7), 1), (rgb(0.3, 0.85, 0.9), 1), (rgb(0.05, 0.25, 0.75), 1), (rgb(0.2, 0.75, 0.55), 0.7),
        ], darkBase: base(0.02, 0.04, 0.07), lightBase: base(0.95, 0.97, 0.98)),
        Self(id: "sunset", name: "Sunset", blobs: [
            (rgb(1, 0.4, 0.35), 1), (rgb(1, 0.6, 0.2), 1), (rgb(0.85, 0.25, 0.6), 1), (rgb(0.45, 0.25, 0.8), 0.7),
        ], darkBase: base(0.06, 0.03, 0.05), lightBase: base(0.98, 0.96, 0.95)),
        Self(id: "forest", name: "Forest", blobs: [
            (rgb(0.35, 0.6, 0.25), 1), (rgb(0.8, 0.7, 0.3), 0.8), (rgb(0.1, 0.45, 0.3), 1), (rgb(0.55, 0.7, 0.55), 0.7),
        ], darkBase: base(0.03, 0.05, 0.03), lightBase: base(0.96, 0.97, 0.95)),
        Self(id: "blossom", name: "Blossom", blobs: [
            (rgb(1, 0.55, 0.7), 1), (rgb(0.75, 0.6, 0.95), 1), (rgb(0.9, 0.35, 0.5), 1), (rgb(1, 0.75, 0.6), 0.7),
        ], darkBase: base(0.06, 0.03, 0.05), lightBase: base(0.98, 0.96, 0.97)),
    ]

    static let holiday: [Self] = [
        // Glowing jack-o'-lanterns and lamps in a misty blue night.
        Self(id: "halloween", name: "Halloween", blobs: [
            (rgb(1, 0.45, 0.05), 1), (rgb(0.25, 0.4, 0.5), 1), (rgb(0.95, 0.3, 0.05), 0.9), (rgb(1, 0.7, 0.2), 0.7),
        ], darkBase: base(0.03, 0.05, 0.07), lightBase: base(0.97, 0.95, 0.92)),
        // A haunted house under a violet sky and a lavender moon, with a pumpkin's orange.
        Self(id: "halloween2", name: "Halloween 2", blobs: [
            (rgb(0.55, 0.25, 0.8), 1), (rgb(0.85, 0.75, 0.95), 0.9), (rgb(0.3, 0.1, 0.45), 1), (rgb(1, 0.6, 0.15), 0.6),
        ], darkBase: base(0.06, 0.03, 0.09), lightBase: base(0.97, 0.95, 0.99)),
        // Pumpkin, harvest gold, cranberry and brown on warm tan.
        Self(id: "thanksgiving", name: "Thanksgiving", blobs: [
            (rgb(0.9, 0.5, 0.15), 1), (rgb(0.95, 0.75, 0.3), 1), (rgb(0.75, 0.2, 0.15), 0.9), (rgb(0.5, 0.3, 0.15), 0.8),
        ], darkBase: base(0.07, 0.05, 0.03), lightBase: base(0.96, 0.92, 0.85)),
        // Red ornaments and golden bokeh on frosted blue pine.
        Self(id: "christmas1", name: "Christmas 1", blobs: [
            (rgb(0.8, 0.08, 0.12), 1), (rgb(1, 0.75, 0.4), 1), (rgb(0.45, 0.6, 0.75), 1), (rgb(0.15, 0.35, 0.3), 0.7),
        ], darkBase: base(0.03, 0.05, 0.08), lightBase: base(0.95, 0.96, 0.97)),
        // Red, green and white.
        Self(id: "christmas2", name: "Christmas 2", blobs: [
            (rgb(0.85, 0.1, 0.15), 1), (rgb(0.1, 0.6, 0.25), 1), (rgb(1, 1, 1), 0.7), (rgb(0.05, 0.4, 0.2), 0.8),
        ], darkBase: base(0.04, 0.05, 0.04), lightBase: base(0.96, 0.97, 0.96)),
        // Snowy whites and ice blues; the light base is a cool grey so the white still shows.
        Self(id: "christmas3", name: "Christmas 3", blobs: [
            (rgb(1, 1, 1), 1), (rgb(0.75, 0.88, 1), 1), (rgb(0.85, 0.88, 0.92), 1), (rgb(0.6, 0.75, 0.95), 0.8),
        ], darkBase: base(0.08, 0.1, 0.14), lightBase: base(0.86, 0.9, 0.95)),
    ]
}

/// The holidays with their own wordmarks (`Wordmark<Name>` and, with landscape cards for the long Home,
/// `WordmarkLong<Name>` in the asset catalog), used on Home in place of the usual ones while holiday wordmarks are on.
enum Holiday: String, CaseIterable {
    case halloween, thanksgiving, christmas

    var name: String { rawValue.capitalized }
    func imageName(long: Bool = false) -> String { long ? "WordmarkLong\(name)" : "Wordmark\(name)" }

    /// October is Halloween; November is Thanksgiving, up to and including Thanksgiving Day (the fourth Thursday);
    /// Christmas runs from the day after through January 5.
    static func current(on date: Date = Date(), calendar: Calendar = .current) -> Holiday? {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = parts.year, let month = parts.month, let day = parts.day else { return nil }
        switch month {
        case 10: return .halloween
        case 11: return day <= thanksgivingDay(year: year, calendar: calendar) ? .thanksgiving : .christmas
        case 12: return .christmas
        case 1 where day <= 5: return .christmas
        default: return nil
        }
    }

    /// The day of November that's its fourth Thursday.
    static func thanksgivingDay(year: Int, calendar: Calendar = .current) -> Int {
        let first = calendar.date(from: DateComponents(year: year, month: 11, day: 1)).map { calendar.component(.weekday, from: $0) } ?? 5
        return 1 + (5 - first + 7) % 7 + 21  // weekday 5 is Thursday
    }
}
