import SwiftUI

// Asking the Mac for things it does: adding a creator, and downloading a creator's older long videos. The phone never
// talks to YouTube or TikTok; the Mac checks what's asked and says how it went.

/// The add-creator form, as the Mac describes it (`GET /creators/form`). Every value is a string.
struct CreatorForm: Decodable {
    struct Choice: Decodable, Hashable {
        let value: String
        let label: String
    }

    struct Condition: Decodable {
        let field: String
        var equals: [String]?
        var matches: String?
        var negate: Bool?

        func holds(_ values: [String: String]) -> Bool {
            let value = values[field] ?? ""
            let result = if let equals { equals.contains(value) }
                else if let matches { value.range(of: matches, options: [.regularExpression, .caseInsensitive]) != nil }
                else { true }
            return negate == true ? !result : result
        }
    }

    struct Field: Decodable, Identifiable {
        let key: String
        let type: String
        let label: String
        var detail: String?
        var placeholder: String?
        var required: Bool?
        var choices: [Choice]?
        var min: Int?
        var max: Int?
        var defaultValue: String?
        var showIf: [[Condition]]?

        var id: String { key }
        var isKnownType: Bool { ["text", "choice", "toggle", "number"].contains(type) }

        func isShown(_ values: [String: String]) -> Bool {
            showIf.map { groups in groups.contains { $0.allSatisfy { $0.holds(values) } } } ?? true
        }

        enum CodingKeys: String, CodingKey {
            case key, type, label, detail, placeholder, required, choices, min, max, showIf
            case defaultValue = "default"
        }
    }

    let version: Int
    let fields: [Field]
}

struct AddCreatorReply: Decodable {
    var added = false
    var message: String
    var fieldErrors: [String: String]?
    var formChanged: Bool?
}

struct OlderVideo: Decodable, Identifiable, Hashable {
    let id: String
    var title: String?
    var date: Date?
    var duration: Double?
}

struct OlderVideosEvent: Decodable {
    var videos: [OlderVideo]
    var done: Bool
    var error: String?
}

struct OlderVideosReply: Decodable {
    var ok: Bool
    var started: Bool
    var message: String
}

/// What a Mac too old for these requests answers.
private func macMessage(_ error: Error) -> String {
    if let error = error as? SyncError, error.status == 404, error.message.contains("Not found") {
        return "Update Curated on your Mac to do this from here."
    }
    return error.localizedDescription
}

/// A form drawn from what the Mac sent. Only the fields showing are sent back, and the Mac has the last word on them.
struct AddCreatorView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var form: CreatorForm?
    @State private var values: [String: String] = [:]
    @State private var loadError: String?
    @State private var sending = false
    @State private var message: String?
    @State private var fieldErrors: [String: String] = [:]
    @State private var added: String?

    private var shown: [CreatorForm.Field] { (form?.fields ?? []).filter { $0.isKnownType && $0.isShown(values) } }

    private var canSend: Bool {
        !sending && form != nil && shown.allSatisfy {
            $0.required != true || !(values[$0.key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let loadError {
                    ContentUnavailableView("Can't Add a Creator", systemImage: "exclamationmark.triangle", description: Text(loadError))
                } else if form == nil {
                    ProgressView()
                } else {
                    Form {
                        if let message {
                            Section { Text(message).foregroundStyle(.red) }
                                .accessibilityIdentifier("addCreatorMessage")
                        }
                        ForEach(shown) { field in
                            Section {
                                control(field)
                            } footer: {
                                VStack(alignment: .leading, spacing: 2) {
                                    if let problem = fieldErrors[field.key] {
                                        Text(problem).foregroundStyle(.red).accessibilityIdentifier("error-\(field.key)")
                                    }
                                    if let detail = field.detail { Text(detail) }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Add Creator")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if sending {
                        ProgressView()
                    } else {
                        Button("Add") { Task { await send() } }
                            .disabled(!canSend)
                            .accessibilityIdentifier("addCreatorSend")
                    }
                }
            }
        }
        .task { await load() }
        .alert("Added", isPresented: Binding(get: { added != nil }, set: { if !$0 { added = nil } })) {
            Button("OK") { dismiss() }
        } message: {
            Text(added ?? "")
        }
    }

    @ViewBuilder private func control(_ field: CreatorForm.Field) -> some View {
        let value = Binding(get: { values[field.key] ?? field.defaultValue ?? "" }, set: {
            values[field.key] = $0
            fieldErrors[field.key] = nil
            message = nil
        })
        switch field.type {
        case "toggle":
            Toggle(field.label, isOn: Binding(get: { value.wrappedValue == "true" }, set: { value.wrappedValue = $0 ? "true" : "false" }))
                .accessibilityIdentifier("field-\(field.key)")
        case "choice":
            Picker(field.label, selection: value) {
                ForEach(field.choices ?? [], id: \.value) { Text($0.label).tag($0.value) }
            }
            .accessibilityIdentifier("field-\(field.key)")
        case "number":
            LabeledContent(field.label) {
                TextField(field.label, text: value)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .labelsHidden()
                    .accessibilityIdentifier("field-\(field.key)")
            }
        default:
            TextField(field.placeholder ?? field.label, text: value)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .accessibilityIdentifier("field-\(field.key)")
        }
    }

    private func load() async {
        do {
            guard let client = await app.macClient() else { throw SyncError(message: "Couldn't reach your Mac. Make sure Curated is open there with phone sync on.") }
            let form = try await client.creatorForm()
            if form.fields.contains(where: { $0.required == true && !$0.isKnownType }) {
                loadError = "Update Curated on this \(UIDevice.current.localizedModel) to add creators from here."
                return
            }
            // What's been typed stays, if the form was fetched again.
            var values = self.values
            for field in form.fields where values[field.key] == nil { values[field.key] = field.defaultValue ?? "" }
            self.values = values
            self.form = form
            loadError = nil
        } catch {
            loadError = macMessage(error)
        }
    }

    private func send() async {
        guard let form else { return }
        sending = true
        defer { sending = false }
        message = nil
        fieldErrors = [:]
        var sent: [String: String] = [:]
        for field in shown { sent[field.key] = values[field.key] ?? field.defaultValue ?? "" }
        do {
            guard let client = await app.macClient() else { throw SyncError(message: "Couldn't reach your Mac. Make sure Curated is open there with phone sync on.") }
            let reply = try await client.addCreator(formVersion: form.version, values: sent)
            if reply.added {
                added = reply.message
                return
            }
            fieldErrors = reply.fieldErrors ?? [:]
            // Beside the field where there is one.
            if fieldErrors.isEmpty || fieldErrors.keys.contains(where: { key in !shown.contains { $0.key == key } }) { message = reply.message }
            if reply.formChanged == true { await load() }
        } catch {
            message = macMessage(error)
        }
    }
}

/// Who `OlderVideosView` is for.
struct OlderVideosTarget: Identifiable, Hashable {
    let id: String
    let name: String
}

/// A creator's long videos on YouTube that aren't downloaded yet, listed by the Mac. Shows 40 at a time, and thumbnails
/// load as they come on screen, through the Mac. Picks are sent to the Mac, which downloads them.
struct OlderVideosView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    let target: OlderVideosTarget

    private static let perLoad = 40

    @State private var client: SyncClient?
    @State private var videos: [OlderVideo] = []
    @State private var limit = OlderVideosView.perLoad
    @State private var loading = true
    @State private var error: String?
    @State private var picked: Set<String> = []
    @State private var skipped: Set<String> = []
    @State private var heights: [String: Int] = [:]
    @State private var sending = false
    @State private var result: String?
    @State private var finished = false

    private var summary: String {
        let shown = min(limit, videos.count)
        var parts = [videos.count > shown ? "\(shown) of \(videos.count)\(loading ? "…" : "") videos" : "\(shown) video\(shown == 1 ? "" : "s")\(loading ? "…" : "")"]
        if !picked.isEmpty { parts.append("\(picked.count) selected") }
        if !skipped.isEmpty { parts.append("\(skipped.count) to skip") }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        NavigationStack {
            Group {
                if videos.isEmpty && !loading {
                    ContentUnavailableView(error == nil ? "No Older Videos" : "Couldn't List the Videos",
                                           systemImage: error == nil ? "checkmark.circle" : "exclamationmark.triangle",
                                           description: Text(error ?? "Every long video from this creator is already downloaded, watched or skipped."))
                } else if videos.isEmpty {
                    ProgressView("Asking your Mac…")
                } else {
                    grid
                }
            }
            .navigationTitle(target.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if sending {
                        ProgressView()
                    } else {
                        Button(picked.isEmpty && !skipped.isEmpty ? "Skip \(skipped.count)" : "Download\(picked.isEmpty ? "" : " \(picked.count)")") {
                            Task { await send() }
                        }
                        .disabled(picked.isEmpty && skipped.isEmpty)
                        .accessibilityIdentifier("olderSend")
                    }
                }
            }
        }
        .task { await list() }
        .alert(finished ? "Sent to Your Mac" : "Not Downloaded", isPresented: Binding(get: { result != nil }, set: { if !$0 { result = nil } })) {
            Button("OK") { if finished { dismiss() } }
        } message: {
            Text(result ?? "")
        }
    }

    private var grid: some View {
        ScrollView {
            Text(summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.top, 8)
                .accessibilityIdentifier("olderSummary")
            // Lazy, so a thumbnail is only asked for near the screen.
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 165), spacing: 12, alignment: .top)], spacing: 16) {
                ForEach(videos.prefix(limit)) { video in tile(video) }
            }
            .padding(.horizontal)
            if videos.count > limit {
                Button("Load More") { limit += Self.perLoad }
                    .padding(.vertical, 12)
                    .accessibilityIdentifier("olderLoadMore")
            } else if loading {
                ProgressView().padding(.vertical, 12)
            }
            Text("Tap to pick; press and hold to skip one or change its resolution. Videos you pick come first until you've watched them, and stay however old they are.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding()
        }
    }

    private func tile(_ video: OlderVideo) -> some View {
        let isPicked = picked.contains(video.id), isSkipped = skipped.contains(video.id)
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return Button {
            if isSkipped { skipped.remove(video.id) }
            if isPicked { picked.remove(video.id) } else { picked.insert(video.id) }
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                Color.clear
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .overlay { OlderThumbnail(id: video.id, client: client) }
                    .clipShape(shape)
                    .overlay { if isPicked { shape.strokeBorder(Color.accentColor, lineWidth: 3) } }
                    .overlay(alignment: .topTrailing) {
                        Image(systemName: isPicked ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, isPicked ? Color.accentColor : .black.opacity(0.35))
                            .padding(6)
                    }
                    .overlay {
                        if isSkipped {
                            Label("Skip", systemImage: "eye.slash")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.black.opacity(0.7), in: Capsule())
                        }
                    }
                Text(video.title ?? video.id)
                    .font(.footnote.weight(.medium))
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)
                Text(byline(video))
                    .font(.caption2)
                    .foregroundStyle(heights[video.id] == nil ? Color.secondary : Color.accentColor)
                    .lineLimit(1)
            }
            .opacity(isSkipped ? 0.45 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(video.title ?? video.id)
        .accessibilityAddTraits(isPicked ? .isSelected : [])
        .contextMenu {
            Button(isSkipped ? "Don't Skip" : "Skip · Mark as Watched", systemImage: isSkipped ? "eye" : "eye.slash") {
                if isSkipped {
                    skipped.remove(video.id)
                } else {
                    skipped.insert(video.id)
                    picked.remove(video.id)
                }
            }
            Picker("Resolution", selection: Binding(get: { heights[video.id] ?? -1 }, set: { heights[video.id] = $0 == -1 ? nil : $0 })) {
                Text("Creator's Resolution").tag(-1)
                Text("Best").tag(0)
                ForEach([1080, 720, 480, 144], id: \.self) { Text("Up to \($0)p").tag($0) }
            }
            .pickerStyle(.menu)
        }
    }

    private func byline(_ video: OlderVideo) -> String {
        let height = heights[video.id].map { $0 == 0 ? "Best" : "\($0)p" }
        return [video.date.map { $0.formatted(.relative(presentation: .named)) }, video.duration.map(formatLength), height]
            .compactMap { $0 }.joined(separator: " · ")
    }

    private func list() async {
        loading = true
        defer { loading = false }
        do {
            guard let client = await app.macClient() else { throw SyncError(message: "Couldn't reach your Mac. Make sure Curated is open there with phone sync on.") }
            self.client = client
            try await client.followOlderVideos(of: target.id) { event in
                videos += event.videos.filter { new in !videos.contains { $0.id == new.id } }
                if let problem = event.error { error = problem }
            }
        } catch is CancellationError {
        } catch let failure as URLError where failure.code == .cancelled {
        } catch {
            self.error = macMessage(error)
        }
    }

    private func send() async {
        guard let client else { return }
        sending = true
        defer { sending = false }
        do {
            let reply = try await client.requestOlderVideos(of: target.id, ids: Array(picked), skip: Array(skipped),
                                                            heights: heights.filter { picked.contains($0.key) })
            finished = reply.ok
            result = reply.message
            if reply.started {
                app.followRequestedVideos(Array(picked))
                result = picked.count == 1
                    ? "Your Mac is downloading 1 video. It'll come here when it's done, or the next time you open Curated."
                    : "Your Mac is downloading \(picked.count) videos. They'll come here when it's done, or the next time you open Curated."
            }
        } catch {
            finished = false
            result = macMessage(error)
        }
    }
}

/// A video's thumbnail, fetched through the Mac when it comes on screen and kept in memory for a while.
private struct OlderThumbnail: View {
    let id: String
    let client: SyncClient?
    @State private var image: UIImage?

    private static let cache = NSCache<NSString, UIImage>()

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Rectangle().fill(.quaternary)
            }
        }
        .task(id: id) {
            if let cached = Self.cache.object(forKey: id as NSString) {
                image = cached
                return
            }
            guard let client, let data = try? await client.olderThumbnail(id), let loaded = UIImage(data: data) else { return }
            Self.cache.setObject(loaded, forKey: id as NSString)
            image = loaded
        }
    }
}
