import AppKit
import SwiftUI

extension Color {
    /// The red and cyan of the Curated logo (its dark-mode artwork), as on the phones.
    static let logoRed = Color(red: 0xE3 / 255, green: 0x31 / 255, blue: 0x51 / 255)
    static let logoCyan = Color(red: 0x6C / 255, green: 0xE7 / 255, blue: 0xE2 / 255)
    /// The Top 15 star: the logo's cyan in dark mode, its red in light mode, where the cyan is too faint.
    static let topTint = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(logoCyan) : NSColor(logoRed)
    })
}

/// One of the sidebar's mixes, as a tile like the phones' Home: its icon beside the title and a line under it. The
/// open mix's tile (`selected`) is filled with its icon's color, the icon and text turning to the window's background
/// color on it. Holding it, or Option-clicking it, runs `hold`.
struct MixTile: View {
    let symbol: String
    let tint: Color
    let title: String
    let subtitle: String
    let selected: Bool
    var hold: (() -> Void)? = nil
    let action: () -> Void
    @State private var pressing = false

    var body: some View {
        let onFill = Color(nsColor: .windowBackgroundColor)
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        // Sized to fit two across the sidebar at its narrowest.
        HStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(selected ? onFill : tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.headline).lineLimit(1).minimumScaleFactor(0.75)
                    .foregroundStyle(selected ? onFill : .primary)
                Text(subtitle).font(.caption).lineLimit(1).minimumScaleFactor(0.75)
                    .foregroundStyle(selected ? AnyShapeStyle(onFill.opacity(0.75)) : AnyShapeStyle(.secondary))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background { if selected { shape.fill(tint) } }
        .cardBackground()
        .contentShape(shape)
        .opacity(pressing ? 0.7 : 1)
        .animation(.easeOut(duration: 0.15), value: pressing)
        .onTapGesture {
            if let hold, NSEvent.modifierFlags.contains(.option) { hold() } else { action() }
        }
        .onLongPressGesture(minimumDuration: 0.45) { hold?() } onPressingChanged: { pressing = $0 }
        .help(hold == nil ? title : "\(title) · hold or Option-click to pick categories")
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { action() }
        .accessibilityActions {
            if let hold { Button("Choose Categories", action: hold) }
        }
    }
}

/// Watch Later or Bookmarks as on iOS: a square glass button with its icon in the accent color (filled with the
/// accent color while its list is open). Clicking it lists its videos in a popover; `onPick` plays from the one picked.
struct SavedButton: View {
    let symbol: String
    let title: String
    let videos: [Video]
    let selected: Bool
    /// Extra commands for the list's ⋯ menu (the iPod list's Clear List and Mark All as Watched).
    var actions: [SavedListAction] = []
    let onPick: ([Video], Int) -> Void
    @State private var showList = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 11, style: .continuous)
        Button { showList = true } label: {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(selected ? Color.white : Color.accentColor)
                .frame(width: 40, height: 40)
                .background { if selected { shape.fill(Color.accentColor) } }
                .squareGlass(shape)
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .help("\(title) · \(videos.count)")
        .accessibilityLabel(title)
        .accessibilityValue("\(videos.count)")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .popover(isPresented: $showList, arrowEdge: .trailing) {
            SavedList(title: title, videos: videos, actions: actions, close: { showList = false }) { index in
                showList = false
                onPick(videos, index)
            }
        }
    }
}

private extension View {
    @ViewBuilder func squareGlass(_ shape: RoundedRectangle) -> some View {
        if #available(macOS 26, *) {
            glassEffect(.regular.interactive(), in: shape)
        } else {
            background(.quaternary.opacity(0.6), in: shape)
        }
    }
}

/// A command in a saved list's ⋯ menu.
struct SavedListAction: Identifiable {
    let title: String
    let symbol: String
    var destructive = false
    let perform: () -> Void
    var id: String { title }
}

/// The videos in Watch Later or Bookmarks, in a popover only as tall as its rows (up to 460pt, then it scrolls).
private struct SavedList: View {
    @Environment(AppModel.self) private var model
    @Environment(Playback.self) private var playback
    let title: String
    let videos: [Video]
    var actions: [SavedListAction] = []
    var close: () -> Void = {}
    let pick: (Int) -> Void
    @State private var height: CGFloat = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("\(title) · \(videos.count)")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    if !actions.isEmpty {
                        Menu {
                            ForEach(actions) { action in
                                Button(role: action.destructive ? .destructive : nil) {
                                    action.perform()
                                    if action.destructive { close() }
                                } label: {
                                    Label(action.title, systemImage: action.symbol)
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle").font(.system(size: 15))
                        }
                        .menuStyle(.button)
                        .buttonStyle(.plain)
                        .menuIndicator(.hidden)
                        .fixedSize()
                        .disabled(videos.isEmpty)
                        .help("\(title) options")
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 4)
                if videos.isEmpty {
                    Text("Nothing here anymore.").foregroundStyle(.secondary).padding(14)
                }
                ForEach(Array(videos.enumerated()), id: \.element.id) { index, video in
                    Button { pick(index) } label: {
                        Group {
                            if video.form == .long {
                                LongVideoRow(video: video, isCurrent: playback.current?.id == video.id, showCreator: true)
                            } else {
                                VideoRow(video: video, isCurrent: playback.current?.id == video.id,
                                         isPlayed: model.isPlayed(video), isSaved: model.isSavedForLater(video),
                                         isBookmarked: model.isBookmarked(video),
                                         creator: model.library(for: video.creator, form: video.form))
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contextMenu { VideoContextMenu(video: video) }
                }
            }
            .padding(.bottom, 8)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        }
        .frame(width: 400, height: min(max(height, 60), 460))
    }
}

/// Which mix a hold or Option-click is picking cards for.
enum MixPick: Hashable {
    case automix, top
}

/// The popover from holding Automix or Top: the sidebar's cards as round glass toggles, each with its glyph and name
/// below, and on the right a red round button that starts the mix (`onStart`) from the ones that are on. On, the glyph
/// turns blue and the card's unplayed count shows as a badge. The cards with something unplayed start on. As on the
/// phones.
struct MixPicker: View {
    @Environment(AppModel.self) private var model
    let pick: MixPick
    let form: VideoForm
    let onStart: (Set<String>) -> Void
    @State private var picked: Set<String>?

    private struct Option: Identifiable {
        let id: String
        let name: String
        let symbol: String?  // nil: the Vine V
        let count: Int
    }

    /// What a card adds to the mix. As on the Automix tile, bookmarked videos stay out of Automix.
    private func count(_ key: String) -> Int {
        switch pick {
        case .automix:
            model.automixLibraries(form, picked: [key]).reduce(0) { total, lib in
                total + lib.videos.count { !model.isPlayed($0) && !model.isBookmarked($0) }
            }
        case .top:
            model.mixLibraries(form, picked: [key]).reduce(0) { $0 + model.unplayedCount($1) }
        }
    }

    /// The sidebar's cards in its order, the ones with nothing to play last. Top lists leave Vines out.
    private var options: [Option] {
        let shown = form == .short ? model.categories
            : model.categories.filter { !model.watchLibraries(.long, in: $0.id).isEmpty }
        var options = shown.map { Option(id: $0.id.uuidString, name: $0.name, symbol: $0.symbol, count: count($0.id.uuidString)) }
        if !model.uncategorizedWatchLibraries(form).isEmpty {
            options.append(Option(id: otherCard, name: shown.isEmpty ? "All Creators" : "Other Creators",
                                  symbol: "person.2", count: count(otherCard)))
        }
        if pick == .automix && form == .short && !model.vineLibraries.isEmpty {
            options.append(Option(id: vineCard, name: "Vine", symbol: nil, count: count(vineCard)))
        }
        return options.filter { $0.count > 0 } + options.filter { $0.count == 0 }
    }

    var body: some View {
        let options = options
        // Automix starts from the categories it plays by default (Settings > Playback).
        let off = pick == .automix ? model.settings.playbackRules.cards(form).automixOff : []
        let on = picked ?? Set(options.filter { $0.count > 0 && !off.contains($0.id) }.map(\.id))
        let total = options.filter { on.contains($0.id) }.reduce(0) { $0 + $1.count }
        let columns = min(4, max(2, options.count))
        let title = pick == .top ? "Top \(PlaybackMode.topCount(nil, form: form))" : "Automix"
        HStack(spacing: 18) {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(76), spacing: 8), count: columns), spacing: 14) {
                ForEach(options) { option in
                    toggle(option, isOn: on.contains(option.id)) {
                        picked = on.symmetricDifference([option.id])
                    }
                }
            }
            .padding(.top, 6)  // Room for the badges.
            Button { onStart(on) } label: {
                Image(systemName: pick == .top ? "star.fill" : "shuffle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(Color.logoRed, in: Circle())
                    .opacity(total == 0 ? 0.4 : 1)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(total == 0)
            .help(title)
            .accessibilityLabel(title)
            .keyboardShortcut(.defaultAction)
        }
        .padding(18)
    }

    private func toggle(_ option: Option, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Group {
                    if let symbol = option.symbol {
                        Image(systemName: symbol).font(.system(size: 19, weight: .semibold))
                    } else {
                        VineGlyph(height: 18)
                    }
                }
                .foregroundStyle(isOn ? Color.blue : Color.primary)
                .frame(width: 52, height: 52)
                .glassCircle()
                .overlay(alignment: .topTrailing) {
                    if isOn { UnplayedBadge(count: option.count).offset(x: 5, y: -3) }
                }
                Text(option.name)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(isOn ? .primary : .secondary)
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.snappy(duration: 0.2), value: isOn)
        .help(option.count > 0 ? "\(option.name) · \(option.count) unwatched" : "\(option.name) · nothing unwatched")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(option.name)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }
}
