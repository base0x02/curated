import SwiftUI

/// The first thing an unpaired phone sees: the logo over slowly drifting color, an orb that pulses like AirDrop while
/// it looks for Curated on the network, and a glass card to pair (a found Mac, or its address, and the 6-digit code).
/// After pairing, the orb turns into the first sync's progress ring, and the screen fades away when it's done.
struct OnboardingView: View {
    @Environment(AppState.self) private var app
    let onFinish: () -> Void

    private enum Phase: Equatable {
        case connect, pairing, syncing
        /// Synced. A message means nothing came down (an empty Mac, or an error) and the screen waits for Continue.
        case done(String?)
    }

    @State private var phase = Phase.connect
    @State private var found: [FoundMac] = []
    @State private var searching = false
    @State private var selected: FoundMac?
    @State private var showAddress = false
    @State private var address = ""
    @State private var code = ""
    @State private var error: String?
    @State private var shakes = 0
    @State private var appeared = false
    @State private var headerHeight: CGFloat = 0
    @State private var cardHeight: CGFloat = 0
    @FocusState private var codeFocused: Bool
    @FocusState private var addressFocused: Bool

    var body: some View {
        ZStack {
            AuroraBackground().ignoresSafeArea()
            GeometryReader { geo in
                // The orb gets what's left after the header and card (measured), between 120 and 260 points, so it all
                // fits on a short screen like iPhone Duo's outer display.
                let orbSize = min(260, max(120, geo.size.height - 56 - 52 - headerHeight - cardHeight))
                ScrollView {
                    VStack(spacing: 26) {
                        // Their own height whatever's offered: the orb is sized from these, and being offered a little
                        // too little would cost the text a line, resize the orb, and go round forever.
                        header
                            .fixedSize(horizontal: false, vertical: true)
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headerHeight = $0 }
                        DiscoveryOrb(mode: orbMode, progress: app.syncProgress)
                            .scaleEffect(orbSize / 260)
                            .frame(width: orbSize, height: orbSize)
                            .opacity(appeared ? 1 : 0)
                            .scaleEffect(appeared ? 1 : 0.8)
                        card
                            .fixedSize(horizontal: false, vertical: true)
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { cardHeight = $0 }
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 40)
                    }
                    .frame(maxWidth: 460)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 28)
                    .frame(maxWidth: .infinity, minHeight: geo.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .task { await keepSearching() }
        .onAppear {
            withAnimation(.spring(duration: 1, bounce: 0.25).delay(0.15)) { appeared = true }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 12) {
            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(height: 58)
                .accessibilityLabel("Curated")
                .accessibilityAddTraits(.isHeader)
            Text("Your Mac picks the videos.\nThis \(UIDevice.current.localizedModel) plays them.")
                .font(.title3.weight(.medium))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .opacity(appeared ? 1 : 0)
        .scaleEffect(appeared ? 1 : 0.92)
        .offset(y: appeared ? 0 : 16)
    }

    private var orbMode: DiscoveryOrb.Mode {
        switch phase {
        case .connect: found.isEmpty ? .searching : .found
        case .pairing: .working
        case .syncing: .syncing
        case .done: .done
        }
    }

    // MARK: Card

    private var card: some View {
        VStack(alignment: .leading, spacing: 18) {
            switch phase {
            case .connect, .pairing: connect
            case .syncing: syncing
            case .done(let message): done(message)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .animation(.spring(duration: 0.45), value: phase)
    }

    private var connect: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Connect to your Mac").font(.title2.weight(.bold))
                Text("On your Mac, open **Curated** › **Phone Sync** › **Pair a Phone**, then enter the code it shows.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            macs

            VStack(alignment: .leading, spacing: 8) {
                Text("Pairing code").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                CodeBoxes(code: $code, focused: $codeFocused)
                    .modifier(Shake(amount: CGFloat(shakes)))
                    .disabled(phase == .pairing)
                if phase == .pairing {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Pairing with \(selected.flatMap { showAddress ? nil : $0.name } ?? "your Mac")…")
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
                } else if let error {
                    Text(error).font(.footnote).foregroundStyle(Color.logoRed)
                        .transition(.opacity)
                }
            }
        }
        // No Pair button: the last digit starts pairing, like a verification code (or a Mac turning up once it's in).
        .onChange(of: canPair) { _, ready in
            if ready { Task { await pair() } }
        }
    }

    /// Found Macs as chips, or the search; the address field hides behind a button.
    private var macs: some View {
        VStack(alignment: .leading, spacing: 10) {
            if found.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Looking for your Mac on this Wi-Fi…").font(.subheadline).foregroundStyle(.secondary)
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(found) { mac in
                            let isSelected = selected == mac && !showAddress
                            Button {
                                withAnimation(.snappy) {
                                    selected = mac
                                    showAddress = false
                                }
                            } label: {
                                Label(mac.name, systemImage: "laptopcomputer")
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .foregroundStyle(isSelected ? .white : .primary)
                                    .background(isSelected ? AnyShapeStyle(Color.curatedBlue) : AnyShapeStyle(.primary.opacity(0.08)),
                                                in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .transition(.scale.combined(with: .opacity))
                        }
                    }
                }
            }
            if showAddress {
                TextField("192.168.1.20:8765", text: $address)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($addressFocused)
                    .padding(.horizontal, 14)
                    .frame(height: 46)
                    .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .accessibilityIdentifier("addressField")
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            Button(showAddress ? "Pick a Mac on this Wi-Fi instead" : "Enter your Mac's address instead") {
                withAnimation(.snappy) { showAddress.toggle() }
                if showAddress { addressFocused = true }
            }
            .font(.footnote.weight(.semibold))
            .tint(.curatedBlue)
        }
    }

    private var syncing: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Syncing with \(app.pairing?.macName ?? "your Mac")").font(.title2.weight(.bold))
            Text(app.syncStep.isEmpty ? "Getting ready…" : app.syncStep)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .contentTransition(.opacity)
                .animation(.easeInOut, value: app.syncStep)
            if let progress = app.syncProgress {
                Text(progress.formatted(.percent.precision(.fractionLength(0))))
                    .font(.title3.monospacedDigit().weight(.semibold))
                    .contentTransition(.numericText())
                    .animation(.snappy, value: progress)
            }
        }
    }

    @ViewBuilder private func done(_ message: String?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(message == nil ? "You're all set" : "Paired with \(app.pairing?.macName ?? "your Mac")")
                .font(.title2.weight(.bold))
            if let message {
                Text(message).font(.subheadline).foregroundStyle(.secondary)
                Button("Continue", action: onFinish)
                    .buttonStyle(.borderedProminent)
                    .tint(.curatedBlue)
                    .padding(.top, 4)
            } else {
                Text("Your videos are ready.").font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Pairing

    private var target: (String, Int)? {
        if showAddress { return parseMacAddress(address) }
        return selected.map { ($0.host, $0.port) }
    }

    private var canPair: Bool { target != nil && code.count == 6 && phase == .connect }

    /// Searches until a Mac turns up, then checks every few seconds for others.
    private func keepSearching() async {
        while !Task.isCancelled && app.pairing == nil {
            searching = true
            let macs = await Discovery.find()
            searching = false
            withAnimation(.spring(duration: 0.5)) { found = macs }
            if selected == nil || !macs.contains(selected!) { selected = macs.first }
            try? await Task.sleep(for: .seconds(macs.isEmpty ? 1.5 : 6))
        }
    }

    private func pair() async {
        guard let (host, port) = target else { return }
        codeFocused = false
        addressFocused = false
        withAnimation { error = nil; phase = .pairing }
        if let message = await app.pair(host: host, port: port, code: code) {
            withAnimation {
                error = message
                phase = .connect
                // Cleared for another try; it would otherwise start again with the same code.
                code = ""
            }
            withAnimation(.linear(duration: 0.45)) { shakes += 1 }
            codeFocused = true
            return
        }
        withAnimation(.spring(duration: 0.6)) { phase = .syncing }
        let message = await app.sync()
        withAnimation(.spring(duration: 0.6)) { phase = .done(app.libraries.isEmpty ? message : nil) }
        if !app.libraries.isEmpty {
            try? await Task.sleep(for: .seconds(1.4))
            onFinish()
        }
    }
}

// MARK: - Pieces

extension Color {
    /// The app's blue (the Mac's system accent), as a fixed color for gradients.
    static let curatedBlue = Color(red: 0x0A / 255, green: 0x84 / 255, blue: 0xFF / 255)
}

/// Slow, blurred color drifting behind everything, in the palette picked in Settings (by default the logo's red and
/// cyan and the app's blue), on near-black (or near-white in light mode). Behind Home it's fainter (`intensity`) and redrawn less often, since it moves slowly
/// and stays on screen. It stands still while it's off screen (under the player) or the app isn't active.
///
/// In Low Power, each blob is blurred once into an image and only those images move, at half the frame rate, so a
/// frame is cheap to draw; otherwise the blobs are blurred together on every frame.
struct AuroraBackground: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppState.self) private var app
    @Environment(Router.self) private var router
    var intensity = 1.0
    /// Seconds between frames; nil for every frame.
    var frameInterval: Double?
    @State private var onScreen = false

    var body: some View {
        let dark = scheme == .dark
        let palette = app.palette
        let colors = palette.blobs.map { (AuroraPalette.shade($0.0, dark: dark), $0.1) }
        let alpha = AuroraPalette.strength(dark: dark) * intensity
        let lowPower = app.lowPower
        let interval = lowPower ? frameInterval.map { $0 * 2 } : frameInterval
        ZStack {
            dark ? palette.darkBase : palette.lightBase
            GeometryReader { geo in
                let size = max(geo.size.width, geo.size.height)
                let diameters = [size * 0.75, size * 0.7, size * 0.85, size * 0.6]
                let blobs = lowPower ? (0..<4).map { AuroraBlob.image(colors[$0].0, alpha * colors[$0].1, diameter: diameters[$0]) } : []
                // Settings covers it without it leaving the screen as far as `onDisappear` goes, and this is the app's
                // biggest battery drain, so it stops there too.
                TimelineView(.animation(minimumInterval: interval, paused: !onScreen || scenePhase != .active || router.settingsShown)) { context in
                    let t = context.date.timeIntervalSinceReferenceDate
                    let spots = [
                        CGPoint(x: 0.22 + 0.16 * sin(t / 7), y: 0.2 + 0.1 * cos(t / 9)),
                        CGPoint(x: 0.82 + 0.14 * cos(t / 8), y: 0.38 + 0.14 * sin(t / 6.5)),
                        CGPoint(x: 0.45 + 0.2 * sin(t / 11), y: 0.82 + 0.1 * cos(t / 7.5)),
                        CGPoint(x: 0.65 + 0.2 * cos(t / 13), y: 0.62 + 0.16 * sin(t / 10)),
                    ]
                    if lowPower {
                        ZStack {
                            ForEach(0..<4, id: \.self) { i in
                                Image(uiImage: blobs[i].image)
                                    .resizable()
                                    .frame(width: blobs[i].side, height: blobs[i].side)
                                    .position(x: spots[i].x * geo.size.width, y: spots[i].y * geo.size.height)
                            }
                        }
                        .frame(width: geo.size.width, height: geo.size.height)
                    } else {
                        ZStack {
                            ForEach(0..<4, id: \.self) { i in
                                Circle()
                                    .fill(RadialGradient(colors: [colors[i].0.opacity(alpha * colors[i].1), colors[i].0.opacity(0)],
                                                         center: .center, startRadius: 0, endRadius: diameters[i] / 2))
                                    .frame(width: diameters[i], height: diameters[i])
                                    .position(x: spots[i].x * geo.size.width, y: spots[i].y * geo.size.height)
                            }
                        }
                        .frame(width: geo.size.width, height: geo.size.height)
                        .blur(radius: 50)
                        .drawingGroup()
                    }
                }
            }
        }
        .onAppear { onScreen = true }
        .onDisappear { onScreen = false }
    }
}

/// One aurora blob, its gradient and blur drawn once at low resolution (it's all soft edges) and kept.
@MainActor
enum AuroraBlob {
    struct Rendered {
        let image: UIImage
        /// Points across, blur included.
        let side: CGFloat
    }

    /// Room around the circle for the blur to spread into.
    private static let blurRadius: CGFloat = 50
    private static var cache: [String: Rendered] = [:]

    static func image(_ color: Color, _ alpha: Double, diameter: CGFloat) -> Rendered {
        let key = "\(color.description)|\(alpha)|\(Int(diameter))"
        if let cached = cache[key] { return cached }
        let side = diameter + blurRadius * 4
        let renderer = ImageRenderer(content:
            Circle()
                .fill(RadialGradient(colors: [color.opacity(alpha), color.opacity(0)], center: .center,
                                     startRadius: 0, endRadius: diameter / 2))
                .frame(width: diameter, height: diameter)
                .blur(radius: blurRadius)
                .frame(width: side, height: side)
        )
        renderer.scale = 0.5
        let rendered = Rendered(image: renderer.uiImage ?? UIImage(), side: side)
        // Palettes, light and dark, and window sizes only come in a few combinations.
        if cache.count > 64 { cache.removeAll() }
        cache[key] = rendered
        return rendered
    }
}

/// A glass orb with a Mac in it. Searching, rings pulse out of it like AirDrop; found, they slow down; pairing and
/// syncing, a gradient ring spins or fills around it; done, a checkmark.
struct DiscoveryOrb: View {
    enum Mode { case searching, found, working, syncing, done }
    let mode: Mode
    let progress: Double?

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [glow.opacity(0.5), .clear], center: .center, startRadius: 20, endRadius: 120))
                    .frame(width: 240, height: 240)
                if mode == .searching || mode == .found {
                    let period = mode == .searching ? 2.4 : 4.2
                    ForEach(0..<3, id: \.self) { i in
                        let phase = (t / period + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                        Circle()
                            .stroke(LinearGradient(colors: [.logoRed, .logoCyan], startPoint: .topLeading, endPoint: .bottomTrailing),
                                    lineWidth: 1.5)
                            .frame(width: 100, height: 100)
                            .scaleEffect(1 + phase * 1.3)
                            .opacity((1 - phase) * 0.85)
                    }
                }
                if mode == .working || mode == .syncing {
                    Circle().stroke(.primary.opacity(0.1), lineWidth: 5).frame(width: 124, height: 124)
                    Circle()
                        .trim(from: 0, to: mode == .syncing ? max(0.04, progress ?? 0.3) : 0.3)
                        .stroke(AngularGradient(colors: [.logoRed, .logoCyan, .curatedBlue, .logoRed], center: .center),
                                style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .frame(width: 124, height: 124)
                        // Spins while it can't tell how far along it is; fills from the top when it can.
                        .rotationEffect(.degrees(mode == .syncing && progress != nil ? -90 : t * 260))
                        .animation(.snappy, value: progress)
                }
                Image(systemName: icon)
                    .font(.system(size: 38, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 100, height: 100)
                    .glassCircle()
                    .scaleEffect(1 + 0.03 * sin(t * 2))  // Breathing.
            }
            .frame(width: 260, height: 260)
        }
        .animation(.spring(duration: 0.5), value: mode)
        .accessibilityHidden(true)
    }

    private var icon: String {
        switch mode {
        case .searching: "laptopcomputer"
        case .found: "laptopcomputer.and.iphone"
        case .working: "lock.open"
        case .syncing: "arrow.down"
        case .done: "checkmark"
        }
    }

    private var glow: Color {
        switch mode {
        case .done: .logoCyan
        case .syncing, .working: .curatedBlue
        default: .logoRed
        }
    }
}

/// Six boxes for the pairing code, filled from a hidden number field (which also takes the code from Messages).
struct CodeBoxes: View {
    @Binding var code: String
    var focused: FocusState<Bool>.Binding

    var body: some View {
        ZStack {
            TextField("", text: $code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused(focused)
                .foregroundStyle(.clear)
                .tint(.clear)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("codeField")
                .accessibilityLabel("Pairing code")
                .onChange(of: code) { _, new in
                    let digits = String(new.filter(\.isNumber).prefix(6))
                    if digits != new { code = digits }
                }
            HStack(spacing: 8) {
                ForEach(0..<6, id: \.self) { i in
                    let digits = Array(code)
                    let digit = i < digits.count ? String(digits[i]) : ""
                    let active = focused.wrappedValue && i == min(digits.count, 5)
                    Text(digit)
                        .font(.title2.monospacedDigit().weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(.primary.opacity(digit.isEmpty ? 0.05 : 0.09),
                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(active ? Color.curatedBlue : .primary.opacity(0.12), lineWidth: active ? 2 : 1)
                        }
                        .scaleEffect(digit.isEmpty ? 1 : 1.04)
                        .animation(.spring(duration: 0.25, bounce: 0.5), value: digit)
                }
            }
            .allowsHitTesting(false)
        }
        .frame(height: 56)
    }
}

/// A side-to-side shake, for a wrong code.
struct Shake: GeometryEffect {
    var amount: CGFloat
    var animatableData: CGFloat {
        get { amount }
        set { amount = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 10 * sin(amount * .pi * 4), y: 0))
    }
}

extension View {
    /// Liquid Glass on iOS 26, a thin material before that.
    @ViewBuilder func glassCard() -> some View {
        let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)
        if #available(iOS 26, *) {
            glassEffect(.regular, in: shape)
        } else {
            background(.ultraThinMaterial, in: shape)
        }
    }

    @ViewBuilder func glassCircle() -> some View {
        if #available(iOS 26, *) {
            glassEffect(.regular, in: Circle())
        } else {
            background(.ultraThinMaterial, in: Circle())
        }
    }
}
