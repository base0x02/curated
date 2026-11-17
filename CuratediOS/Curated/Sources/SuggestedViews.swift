import SwiftUI

/// Shown with a suggested creator's video: adds them to the Mac's creators, in a category of the user's choosing
/// (FollowSuggestedSheet). Once asked for while the Mac was out of reach, it says it's waiting for the next sync.
struct SuggestedFollowButton: View {
    @Environment(AppState.self) private var app
    @Environment(Router.self) private var router
    let creatorKey: String

    var body: some View {
        if isSuggestedKey(creatorKey) {
            if app.isFollowPending(creatorKey) {
                Label("Next sync", systemImage: "clock.arrow.circlepath")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .accessibilityLabel("Will be added to your creators at the next sync")
            } else {
                Button { router.followingSuggested = creatorKey } label: {
                    Label("Add", systemImage: "person.crop.circle.badge.plus")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.suggestedPink, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add to your creators")
                .accessibilityIdentifier("followSuggested")
            }
        }
    }
}

/// Adding a suggested creator to the Mac's creators: who, and which category.
struct FollowSuggestedSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    let creatorKey: String
    @State private var category: String?
    @State private var sending = false
    @State private var message: String?

    var body: some View {
        let creator = app.library(creatorKey)?.creator
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        AvatarView(username: creatorKey, size: 56)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(creator?.displayName ?? "@\(creatorHandle(creatorKey))").font(.headline)
                            Text("\(creator?.siteName ?? (isYouTubeKey(creatorKey) ? "YouTube" : "TikTok")) · @\(creatorHandle(creatorKey))")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                Section {
                    Picker("Category", selection: $category) {
                        Text("None").tag(String?.none)
                        ForEach(app.categories) { category in
                            Label(category.name, systemImage: category.symbol ?? "folder").tag(String?.some(category.id))
                        }
                    }
                } footer: {
                    Text("Your Mac adds them to your creators and downloads their recent videos. Their suggested videos move to them.")
                }
                if let message {
                    Section { Text(message) }
                }
            }
            .navigationTitle("Add to Creators")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(message == nil ? "Cancel" : "Done") { dismiss() }
                }
                if message == nil {
                    ToolbarItem(placement: .confirmationAction) {
                        if sending {
                            ProgressView()
                        } else {
                            Button("Add") {
                                sending = true
                                Task {
                                    message = await app.followSuggested(creatorKey, category: category)
                                    sending = false
                                }
                            }
                            .accessibilityIdentifier("followSuggestedConfirm")
                        }
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// A suggested creator's key, for presenting a sheet.
struct SuggestedKey: Identifiable {
    let id: String
}
