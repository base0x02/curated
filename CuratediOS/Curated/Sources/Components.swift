import AVFoundation
import AVKit
import SwiftUI

/// Platform colors, as on the Mac: TikTok's logo cyan and magenta, and YouTube red.
extension Color {
    static let tikTokCyan = Color(red: 0x25 / 255, green: 0xF4 / 255, blue: 0xEE / 255)
    static let tikTokMagenta = Color(red: 0xFE / 255, green: 0x2C / 255, blue: 0x55 / 255)
    static let youTubeRed = Color(red: 0xFF / 255, green: 0x45 / 255, blue: 0x3A / 255)
    /// The green of the classic Vine logo.
    static let vineGreen = Color(red: 0x00 / 255, green: 0xB4 / 255, blue: 0x88 / 255)
}

/// Avatar outline: YouTube red, Vine green, or TikTok's cyan-to-magenta.
func platformRing(_ creatorKey: String) -> AnyShapeStyle {
    if isYouTubeKey(creatorKey) { return AnyShapeStyle(Color.youTubeRed) }
    if creatorKey.hasPrefix(vineKeyPrefix) { return AnyShapeStyle(Color.vineGreen) }
    return AnyShapeStyle(LinearGradient(colors: [.tikTokCyan, .tikTokMagenta], startPoint: .topLeading, endPoint: .bottomTrailing))
}

extension Creator {
    /// Creator names in queues.
    var tint: Color { isYouTube ? .youTubeRed : isVine ? .vineGreen : .tikTokCyan }
}

struct AvatarView: View {
    @Environment(AppState.self) private var app
    let username: String
    let size: CGFloat
    /// Caught-up creators: grayscale and faded, so the ones with something new stand out.
    var dimmed = false

    var body: some View {
        Group {
            if let image = UIImage(contentsOfFile: app.store.avatarFile(username).path) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    // Vine authors without a picture get Vine green.
                    Circle().fill(username.hasPrefix(vineKeyPrefix) ? Color.vineGreen.gradient : Color.accentColor.gradient)
                    // A Vine author's key is a number, so their name's first letter.
                    Text((username.hasPrefix(vineKeyPrefix) ? app.library(username)?.creator.displayName ?? "" : creatorHandle(username))
                        .prefix(1).uppercased())
                        .font(.system(size: size * 0.45, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay { Circle().strokeBorder(platformRing(username), lineWidth: max(1.5, size / 24)) }
        .grayscale(dimmed ? 1 : 0)
        .opacity(dimmed ? 0.45 : 1)
        .accessibilityHidden(true)
    }
}

/// An app-icon-style count for an avatar's corner. Hidden at zero.
struct UnplayedBadge: View {
    let count: Int

    var body: some View {
        if count > 0 {
            Text(count > 99 ? "99+" : "\(count)")
                .font(.system(size: 11, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .frame(minWidth: 20)
                .background(Color.accentColor, in: Capsule())
                .padding(2)
                .background(Color(.systemBackground), in: Capsule())
        }
    }
}

/// A plain count, like a list badge.
struct CountBadge: View {
    let count: Int

    var body: some View {
        if count > 0 {
            Text("\(count)")
                .font(.subheadline.weight(.medium))
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()  // A tight row truncates the title beside it instead of wrapping the digits.
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color.primary.opacity(0.1), in: Capsule())
        }
    }
}

private let thumbnailCache = NSCache<NSURL, UIImage>()

/// A frame from half a second in, like the Mac's thumbnails.
struct ThumbnailView: View {
    let url: URL
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Rectangle().fill(.quaternary)
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            }
        }
        .task(id: url) {
            if let cached = thumbnailCache.object(forKey: url as NSURL) {
                image = cached
                return
            }
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 180, height: 320)
            if let (cg, _) = try? await generator.image(at: CMTime(seconds: 0.5, preferredTimescale: 600)) {
                let ui = UIImage(cgImage: cg)
                thumbnailCache.setObject(ui, forKey: url as NSURL)
                image = ui
            }
        }
    }
}

/// A video's first frame at full-screen size: what slides in during a swipe, and covers the player until it draws.
struct VideoStill: View {
    let url: URL
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color.black
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
            }
        }
        .task(id: url) { image = await Self.load(url) }
    }

    private static let cache: NSCache<NSURL, UIImage> = {
        let cache = NSCache<NSURL, UIImage>()
        cache.countLimit = 8
        return cache
    }()

    /// Loads (or returns the cached) first frame. Call it ahead of time so a swipe has it ready.
    @discardableResult
    static func load(_ url: URL) async -> UIImage? {
        if let cached = cache.object(forKey: url as NSURL) { return cached }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        generator.maximumSize = CGSize(width: 1080, height: 1920)
        guard let (cg, _) = try? await generator.image(at: .zero) else { return nil }
        let image = UIImage(cgImage: cg)
        cache.setObject(image, forKey: url as NSURL)
        return image
    }
}

struct VideoRow: View {
    @Environment(AppState.self) private var app
    let video: Video
    let isCurrent: Bool
    let showCreator: Bool

    var body: some View {
        let played = app.isPlayed(video)
        let saved = app.isSavedForLater(video)
        HStack(alignment: .top, spacing: 12) {
            ThumbnailView(url: app.store.videoFile(video))
                .frame(width: 54, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .opacity(played && !isCurrent ? 0.45 : 1)
                .overlay {
                    if isCurrent {
                        RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.accentColor, lineWidth: 2)
                        Image(systemName: "play.fill").foregroundStyle(.white).shadow(radius: 3)
                    }
                }
            VStack(alignment: .leading, spacing: 4) {
                if showCreator {
                    let creator = app.library(video.creator)?.creator
                    Text(creator?.displayName ?? "@\(creatorHandle(video.creator))")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(creator?.tint ?? .tikTokCyan)
                }
                Text(video.caption.isEmpty ? "No caption" : video.caption)
                    .font(.subheadline)
                    .foregroundStyle(video.caption.isEmpty || played ? .secondary : .primary)
                    .lineLimit(3)
                HStack(spacing: 4) {
                    if played {
                        Label("Watched", systemImage: "checkmark.circle.fill")
                        Text("·")
                    } else if saved {
                        Label("Later", systemImage: "tray.and.arrow.down.fill")
                        Text("·")
                    }
                    Text(metaText)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    private var metaText: String {
        var parts = [video.date.formatted(.relative(presentation: .named))]
        if let views = video.viewCount { parts.append("\(views.formatted(.number.notation(.compactName))) views") }
        if let duration = video.duration { parts.append(formatClock(duration)) }
        return parts.joined(separator: " · ")
    }
}

/// The shared AVPlayer drawn into a layer. The on-screen one also drives picture in picture.
struct VideoSurface: UIViewRepresentable {
    let playback: Playback
    var gravity: AVLayerVideoGravity = .resizeAspect
    /// Whether this layer can be the one picture in picture uses (not the mini player's thumbnail).
    var pip = true
    /// Called on the main thread when the layer draws its first frame of a new video.
    var onReadyForDisplay: (() -> Void)?

    func makeUIView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        playback.show(on: view.playerLayer)
        view.playerLayer.videoGravity = gravity
        view.backgroundColor = .clear
        view.onReadyForDisplay = onReadyForDisplay
        view.readyObservation = view.playerLayer.observe(\.isReadyForDisplay, options: [.new]) { [weak view] layer, _ in
            guard layer.isReadyForDisplay else { return }
            DispatchQueue.main.async { view?.onReadyForDisplay?() }
        }
        // PiP follows whichever player layer is in the window (see PlayerLayerView.didMoveToWindow). The mini player's
        // thumbnail stays out of it: it's still there, hidden, under an open player, and PiP tied to it can't start.
        if pip { view.pipPlayback = playback }
        let playback = playback
        view.onDismantle = { [weak view] in
            if let layer = view?.playerLayer { playback.detachPip(from: layer) }
        }
        return view
    }

    func updateUIView(_ view: PlayerLayerView, context: Context) {
        view.playerLayer.videoGravity = gravity
        view.onReadyForDisplay = onReadyForDisplay
    }

    static func dismantleUIView(_ view: PlayerLayerView, coordinator: ()) {
        view.onDismantle?()
    }
}

/// The playing video scaled to fill and heavily blurred, behind the real one, so the space around it (and under the
/// controls) carries its colors instead of black bars, like a newscast's blurred fill. It takes no part in picture in
/// picture. Low Power leaves it out (plain black), since blurring the video live is costly.
struct VideoBackdrop: View {
    @Environment(AppState.self) private var app
    let playback: Playback

    var body: some View {
        if !app.lowPower { LiveBackdrop(playback: playback) }
    }
}

/// A second layer on the same player under a live blur, so it stays in step for free.
private struct LiveBackdrop: UIViewRepresentable {
    let playback: Playback

    func makeUIView(context: Context) -> BackdropView {
        let view = BackdropView()
        playback.show(on: view.playerLayer)
        return view
    }

    func updateUIView(_ view: BackdropView, context: Context) {}

    final class BackdropView: UIView {
        let playerLayer = AVPlayerLayer()
        private let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
        private let dim = UIView()

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .black
            clipsToBounds = true
            isUserInteractionEnabled = false
            playerLayer.videoGravity = .resizeAspectFill
            layer.addSublayer(playerLayer)
            dim.backgroundColor = UIColor.black.withAlphaComponent(0.35)
            addSubview(blur)
            addSubview(dim)
        }

        required init?(coder: NSCoder) { fatalError() }

        override func layoutSubviews() {
            super.layoutSubviews()
            // Overscanned so the blur doesn't fade to black at the edges.
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            playerLayer.frame = bounds.insetBy(dx: -bounds.width * 0.15, dy: -bounds.height * 0.15)
            CATransaction.commit()
            blur.frame = bounds
            dim.frame = bounds
        }
    }
}

final class PlayerLayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    var onDismantle: (() -> Void)?
    var onReadyForDisplay: (() -> Void)?
    var readyObservation: NSKeyValueObservation?
    /// Set when this layer may drive picture in picture: it takes PiP over on joining a window and lets go on leaving
    /// it, so PiP is always tied to the player on screen, whichever was built last.
    weak var pipPlayback: Playback?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard let pipPlayback else { return }
        if window != nil { pipPlayback.attachPip(to: playerLayer) } else { pipPlayback.detachPip(from: playerLayer) }
    }
}

extension View {
    /// Liquid Glass on iOS 26 and later, a material everywhere else.
    @ViewBuilder
    func glassBackground<S: Shape>(in shape: S, interactive: Bool = false, tint: Color? = nil) -> some View {
        if #available(iOS 26, *) {
            self.glassEffect(interactive ? Glass.regular.tint(tint).interactive() : Glass.regular.tint(tint), in: shape)
        } else {
            self.background(tint.map { AnyShapeStyle($0.opacity(0.8)) } ?? AnyShapeStyle(.ultraThinMaterial), in: shape)
        }
    }
}

/// The short-video progress bar, which scrubs like TikTok's: touch it and slide along, and the video pauses and follows
/// the finger, the bar thickens and the time shows above it. Playback picks up again on release if it was playing.
struct ScrubBar: View {
    @Environment(Playback.self) private var playback
    let length: Double
    /// White over video; the sideways tray draws it in the text color.
    var color: Color = .white
    @State private var scrubbing: Double?
    @State private var wasPlaying = false

    var body: some View {
        let shown = scrubbing ?? playback.position
        let fraction = min(1, max(0, shown / length))
        let thickness: CGFloat = scrubbing == nil ? 3 : 6
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(color.opacity(0.25))
                Capsule().fill(color).frame(width: geometry.size.width * fraction)
            }
            .frame(height: thickness)
            .frame(maxHeight: .infinity)
            // Taller than the bar, so it's easy to catch with a finger.
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        if scrubbing == nil {
                            wasPlaying = playback.isPlaying
                            playback.pause()
                        }
                        let time = min(1, max(0, drag.location.x / geometry.size.width)) * length
                        scrubbing = time
                        playback.seek(to: time)
                    }
                    .onEnded { _ in
                        scrubbing = nil
                        if wasPlaying { playback.resume() }
                    }
            )
        }
        .frame(height: 20)
        .overlay(alignment: .top) {
            if scrubbing != nil {
                Text("\(formatClock(shown)) / \(formatClock(length))")
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
                    .offset(y: -40)
                    .allowsHitTesting(false)
            }
        }
        .animation(.snappy(duration: 0.15), value: scrubbing == nil)
        .onChange(of: playback.current?.id) { scrubbing = nil }
        .accessibilityElement()
        .accessibilityLabel("Progress")
        .accessibilityValue("\(formatClock(shown)) of \(formatClock(length))")
        .accessibilityAdjustableAction { direction in
            let step = direction == .increment ? 5.0 : -5.0
            playback.seek(to: min(length, max(0, playback.position + step)))
        }
    }
}
