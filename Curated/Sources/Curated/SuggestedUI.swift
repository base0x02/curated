import SwiftUI

/// Settings → Downloads → Suggested Short Videos: a card for each platform with its switch, how many to keep, and
/// how the last look at its feed went (with a way to sign in when that's what's wrong).
struct SuggestedSettingsCards: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(Suggested.platforms) { platform in
                    SuggestedPlatformCard(platform: platform)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            if model.settings.suggested.anyOn {
                HStack {
                    Button("Get Suggestions Now", systemImage: "sparkles") { model.downloadSuggested() }
                        .disabled(model.isDownloading)
                    if model.downloadingSuggested { ProgressView().controlSize(.small) }
                }
            }
        }
    }
}

private struct SuggestedPlatformCard: View {
    @Environment(AppModel.self) private var model
    let platform: Platform

    var body: some View {
        let on = model.settings.suggested.isOn(platform)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                PlatformIcon(platform: platform, size: platform == .tiktok ? 22 : 24).frame(width: 28, height: 28)
                Text(platform == .tiktok ? "TikTok For You" : "YouTube Shorts").font(.body.weight(.medium))
                Spacer()
                Toggle("", isOn: Binding(get: { on }, set: { model.setSuggested(platform, on: $0) }))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
            }
            Picker("Keep", selection: Binding(get: { model.settings.suggested.count(platform) },
                                              set: { model.settings.suggested.set(platform, count: $0) })) {
                ForEach(Suggested.counts, id: \.self) { Text("\($0) video\($0 == 1 ? "" : "s")").tag($0) }
            }
            .disabled(!on)
            if on { status }
        }
        .card()
        .frame(maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder private var status: some View {
        if let status = model.suggestedStatus(platform) {
            switch status.state {
            case .ok:
                Label("Signed in · checked \(status.at.formatted(.relative(presentation: .named)))",
                      systemImage: "checkmark.circle.fill")
                    .font(.caption).foregroundStyle(.secondary)
                    .symbolRenderingMode(.multicolor)
            case .signedOut, .locked:
                VStack(alignment: .leading, spacing: 6) {
                    Label(status.state == .locked ? "Locked out" : "Signed out", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.semibold)).foregroundStyle(.orange)
                    if let message = status.message {
                        Text(message).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Button(signInLabel(locked: status.state == .locked)) { model.openSignIn(platform, locked: status.state == .locked) }
                        .controlSize(.small)
                }
            case .failed:
                Label(status.message ?? "Couldn't read the feed", systemImage: "exclamationmark.circle")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else if platform == .tiktok {
            Button("Sign In to TikTok…") { model.openSignIn(.tiktok) }.controlSize(.small)
        } else if model.settings.youtubeCookieBrowser == .none {
            Text("Pick the browser you're signed in to YouTube in under Sign-In above.")
                .font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func signInLabel(locked: Bool) -> String {
        switch platform {
        case .tiktok: locked ? "Open TikTok…" : "Sign In to TikTok…"
        default: "Open YouTube in \(model.settings.youtubeCookieBrowser == .none ? "Your Browser" : model.settings.youtubeCookieBrowser.label)"
        }
    }
}

/// Adding a suggested creator to the regular list, in a category.
struct FollowSuggestedSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let creator: Creator
    @State private var category: UUID?

    var body: some View {
        let library = model.library(for: creator.id)
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                if let library { AvatarView(library: library, size: 48) }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Add \(library?.displayName ?? creator.username) to your creators").font(.headline)
                    Text("\(creator.platform.name) · @\(creator.username)").font(.callout).foregroundStyle(.secondary)
                }
            }
            Picker("Category", selection: $category) {
                Text("None").tag(UUID?.none)
                ForEach(model.categories) { category in
                    Label(category.name, systemImage: category.symbol).tag(UUID?.some(category.id))
                }
            }
            Text("Their suggested videos move to them, and their recent videos download like any creator's.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Add Creator") {
                    model.followSuggested(creator.id, category: category)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 400)
    }
}

extension View {
    /// The suggestion prompts (sign in, delete leftovers, turn off), the TikTok sign-in sheet and Add to Creators.
    func suggestedPrompts() -> some View { modifier(SuggestedPrompts()) }
}

private struct SuggestedPrompts: ViewModifier {
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        @Bindable var model = model
        content
            #if DEBUG
            // CURATED_TEST_TIKTOK_SIGNIN=1 opens the TikTok sign-in sheet, for snapshots.
            .onAppear {
                if ProcessInfo.processInfo.environment["CURATED_TEST_TIKTOK_SIGNIN"] != nil { model.openSignIn(.tiktok) }
            }
            #endif
            .alert(title, isPresented: Binding(get: { model.suggestedPrompt != nil }, set: { if !$0 { model.suggestedPrompt = nil } }),
                   presenting: model.suggestedPrompt) { prompt in
                switch prompt {
                case .signIn(let platform, _, let locked):
                    // After the alert has gone, so the sheet or the next question can show.
                    Button(platform == .tiktok ? (locked ? "Open TikTok" : "Sign In") : "Open YouTube") {
                        DispatchQueue.main.async { model.openSignIn(platform, locked: locked) }
                    }
                    Button("Turn Off Suggestions", role: .destructive) {
                        DispatchQueue.main.async { model.setSuggested(platform, on: false) }
                    }
                    Button("Not Now", role: .cancel) {}
                case .leftovers(let platform, _):
                    Button("Delete Them", role: .destructive) { model.deleteSuggested(platform) }
                    Button("Turn Suggestions On") { model.setSuggested(platform, on: true) }
                    Button("Not Now", role: .cancel) {}
                case .turnOff(let platform, _):
                    Button("Turn Off and Delete", role: .destructive) { model.turnOffSuggested(platform) }
                    Button("Cancel", role: .cancel) {}
                }
            } message: { prompt in
                switch prompt {
                case .signIn(_, let message, _):
                    Text(message + " Suggested videos are paused until then.")
                case .leftovers(let platform, let count):
                    Text("Suggested \(platform.name) videos are turned off, but \(count) of them are still here. Delete them? Your phones drop them at their next sync.")
                case .turnOff(let platform, let count):
                    Text("The \(count) suggested \(platform.name) video\(count == 1 ? "" : "s") here will be deleted, and your phones drop them at their next sync.")
                }
            }
            .sheet(item: Binding(get: { model.tiktokSignInURL.map(IdentifiedURL.init) },
                                 set: { model.tiktokSignInURL = $0?.url })) { item in
                TikTokSignInSheet(url: item.url) {
                    model.tiktokSignInURL = nil
                    // Try again with the new sign-in.
                    if model.settings.suggested.tiktok, !model.isDownloading { model.downloadSuggested() }
                }
            }
            .sheet(item: $model.followingSuggested) { creator in
                FollowSuggestedSheet(creator: creator)
            }
    }

    private var title: String {
        switch model.suggestedPrompt {
        case .signIn(let platform, _, let locked)?:
            locked ? "\(platform.name) has locked you out" : "Sign in to \(platform.name)"
        case .leftovers?: "Delete suggested videos?"
        case .turnOff(let platform, _)?: "Turn off suggested \(platform.name) videos?"
        case nil: ""
        }
    }
}

private struct IdentifiedURL: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}
