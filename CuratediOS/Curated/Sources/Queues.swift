import SwiftUI

/// The same mixes as the Mac and Android apps.
enum Queues {
    /// A fresh queue for a mix, Watch Later, bookmarks, or a creator's videos.
    @MainActor
    static func build(_ mode: PlaybackMode, _ app: AppState) -> [Video] {
        switch mode {
        // Bookmarked videos are kept for their own list, not mixed in.
        case .automix(let category, let picked):
            automix(picked.map { app.automixLibraries(picked: $0) } ?? app.automixLibraries(in: category),
                    played: app.played.union(app.bookmarkedIDs))
        case .vineAutomix: automix(app.vineLibraries, played: app.played.union(app.bookmarkedIDs))
        case .top(let category, let picked):
            top(picked.map { app.mixLibraries(picked: $0, form: .short) } ?? app.libraries(in: category), played: app.played,
                count: PlaybackMode.topCount(category))
        case .watchLater: app.watchLaterVideos()
        case .bookmarks: app.bookmarkedVideos()
        case .creator(let username): app.library(username)?.videos ?? []
        case .longCreator(let username): app.library(username, form: .long).map(app.longVideos) ?? []
        case .latest(let category): app.handPickedFirst(latest(app.mixLibraries(in: category, form: .long), played: app.played))
        case .longAutomix(let category, let picked):
            app.handPickedFirst(automix(picked.map { app.mixLibraries(picked: $0, form: .long) } ?? app.longAutomixLibraries(in: category),
                                        played: app.played.union(app.bookmarkedIDs)))
        case .longWatchLater: app.watchLaterVideos(.long)
        case .longBookmarks: app.bookmarkedVideos(.long)
        }
    }

    /// Every unwatched video, newest first: for long videos, where a round-robin mix doesn't suit.
    static func latest(_ libraries: [CreatorLibrary], played: Set<String>) -> [Video] {
        libraries.flatMap(\.videos).filter { !played.contains($0.id) }.sorted { $0.date > $1.date }
    }

    /// Unplayed videos only. Round-robin across creators (random order), each creator newest first.
    static func automix(_ libraries: [CreatorLibrary], played: Set<String>) -> [Video] {
        let lists = libraries.map { $0.videos.filter { !played.contains($0.id) } }.filter { !$0.isEmpty }.shuffled()
        let longest = lists.map(\.count).max() ?? 0
        var queue: [Video] = []
        for round in 0..<longest {
            for list in lists where round < list.count { queue.append(list[round]) }
        }
        return queue
    }

    /// The most-viewed unplayed videos; if some lack view counts, the rest is filled Automix-style.
    static func top(_ libraries: [CreatorLibrary], played: Set<String>, count: Int) -> [Video] {
        let unplayed = libraries.flatMap(\.videos).filter { !played.contains($0.id) }
        var picked = Array(unplayed.filter { $0.viewCount != nil }.sorted { $0.viewCount! > $1.viewCount! }.prefix(count))
        if picked.count < count {
            picked += automix(libraries, played: played.union(picked.map(\.id))).prefix(count - picked.count)
        }
        return picked
    }

    /// Keeps videos until their total length reaches `seconds`; the video that crosses the limit is the last one.
    static func limit(_ queue: [Video], toSeconds seconds: Double) -> [Video] {
        var total = 0.0
        var result: [Video] = []
        for video in queue {
            result.append(video)
            total += video.duration ?? 0
            if total >= seconds { break }
        }
        return result
    }
}

/// "4:05" or "1:02:09".
func formatClock(_ seconds: Double) -> String {
    let total = Int(max(0, seconds).rounded(.up))
    let h = total / 3600, m = total / 60 % 60, s = total % 60
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
}

/// "3h 12m", "45m" or "30s", for totals.
func formatLength(_ seconds: Double) -> String {
    let total = Int(seconds.rounded())
    let h = total / 3600, m = total / 60 % 60
    if h > 0 { return m > 0 ? "\(h)h \(m)m" : "\(h)h" }
    return m > 0 ? "\(m)m" : "\(total)s"
}

func formatBytes(_ bytes: Int) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
}

extension View {
    /// The speed button while the video's category stays at 1×.
    func speedLock(_ locked: Bool) -> some View {
        disabled(locked)
            .opacity(locked ? 0.55 : 1)
            .accessibilityHint(locked ? "This category always plays at 1×" : "")
    }
}

/// "1x", "1.5x", "2x".
func formatSpeed(_ speed: Float) -> String {
    (speed.rounded() == speed ? "\(Int(speed))" : "\(speed)") + "×"
}
