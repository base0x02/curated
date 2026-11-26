import SwiftUI

// See Less and Snooze, as on the Mac: See Less keeps about one video per day window (the most viewed), and Snooze stops
// a creator's downloads for a while. Picked here, sent to the Mac at the next sync (tried quietly at once).

enum CreatorBreakSymbol {
    static let snooze = "zzz"
    static let seeLess = "tortoise.fill"
}

/// The badge on a creator's avatar while they're snoozed (Zzz) or seen less of (a turtle).
struct CreatorBreakBadge: View {
    @Environment(AppState.self) private var app
    let username: String
    let size: CGFloat

    var body: some View {
        let state = app.breakState(username)
        if let symbol = state.snoozed ? CreatorBreakSymbol.snooze : state.seeLess ? CreatorBreakSymbol.seeLess : nil {
            let badge = max(14, size * 0.42)
            Image(systemName: symbol)
                .font(.system(size: badge * 0.55, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: badge, height: badge)
                .background(state.snoozed ? Color.indigo : Color.green, in: Circle())
                .overlay { Circle().strokeBorder(Color(.systemBackground), lineWidth: max(1, badge / 10)) }
                .offset(x: badge * 0.2, y: badge * 0.15)
        }
    }
}

/// Settings → Sync → See Less / Snooze: pick a creator, then See Less or Snooze, after a question.
struct CreatorBreaksView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var picked: Creator?
    @State private var search = ""

    private var creators: [Creator] {
        let all = app.breakableCreators
        guard !search.isEmpty else { return all }
        return all.filter { $0.displayName.localizedCaseInsensitiveContains(search) || $0.handle.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(creators) { creator in
                        Button { picked = creator } label: { row(creator) }
                            .foregroundStyle(.primary)
                            .accessibilityIdentifier("break-\(creator.username)")
                    }
                } header: {
                    if !app.macHasCreatorBreaks {
                        Text("Sync once with Curated 2.4 on your Mac to see who's snoozed. Choices made now are sent then.")
                            .textCase(nil)
                    }
                } footer: {
                    Text("See Less downloads only a creator's most-viewed new video from each of their download windows. Snooze stops downloading them for \(app.snoozeDays) days. Your Mac gets these at the next sync.")
                }
            }
            .searchable(text: $search, prompt: "Creators")
            .navigationTitle("See Less / Snooze")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .overlay {
                if app.breakableCreators.isEmpty {
                    ContentUnavailableView("No Creators Yet", systemImage: "person.2", description: Text("Sync with your Mac to see its creators here."))
                }
            }
            .confirmationDialog(picked.map { "See less of \($0.displayName), or snooze them?" } ?? "",
                                isPresented: Binding(get: { picked != nil }, set: { if !$0 { picked = nil } }),
                                titleVisibility: .visible, presenting: picked) { creator in
                let state = app.breakState(creator.username)
                if state.seeLess {
                    Button("See More Again") { app.setBreak(creator.username, seeLess: false) }
                } else {
                    Button("See Less") { app.setBreak(creator.username, seeLess: true) }
                }
                if state.snoozed {
                    Button("Wake Up") { app.setBreak(creator.username, snoozed: false) }
                } else {
                    Button("Snooze for \(app.snoozeDays) Days") { app.setBreak(creator.username, snoozed: true) }
                }
                Button("Cancel", role: .cancel) {}
            } message: { creator in
                Text("See Less downloads only their most-viewed new video from each \(creator.days)-day window. Snooze downloads nothing of theirs for \(app.snoozeDays) days. Videos already here stay.")
            }
        }
    }

    private func row(_ creator: Creator) -> some View {
        let state = app.breakState(creator.username)
        return HStack(spacing: 12) {
            AvatarView(username: creator.username, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(creator.displayName).lineLimit(1)
                if let status = status(state) {
                    Text(status).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if state.waiting {
                Image(systemName: "clock.arrow.circlepath").foregroundStyle(.secondary).accessibilityLabel("Next sync")
            }
        }
        .contentShape(Rectangle())
    }

    private func status(_ state: CreatorBreakState) -> String? {
        var parts: [String] = []
        if state.snoozePending {
            parts.append("Snoozed at the next sync")
        } else if state.snoozed, let until = state.snoozedUntil {
            parts.append("Snoozed until \(until.formatted(date: .abbreviated, time: .omitted))")
        }
        if state.seeLess { parts.append("See Less") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
