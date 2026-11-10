package local.curated.phone

/** The same mixes as the Mac app (Library.swift). */
object Queues {
    /** A fresh queue for a mix, Watch Later, bookmarks, or a creator's videos. */
    fun build(mode: PlaybackMode, state: AppState): List<Video> = when (mode) {
        // Bookmarked videos are kept for their own list, not mixed in.
        is PlaybackMode.Automix -> state.handPickedFirst(
            automix(
                mode.picked?.let { state.automixLibraries(it, mode.form) } ?: state.automixLibraries(mode.category, mode.form),
                state.played + state.bookmarkedIds,
            ),
        )
        is PlaybackMode.VineAutomix -> automix(state.vineLibraries, state.played + state.bookmarkedIds)
        is PlaybackMode.Latest -> state.handPickedFirst(latest(state.mixLibraries(mode.category, VideoForm.LONG), state.played))
        is PlaybackMode.Top -> top(
            mode.picked?.let { state.mixLibraries(it, VideoForm.SHORT) } ?: state.mixLibraries(mode.category, VideoForm.SHORT),
            state.played, PlaybackMode.topCount(mode.category),
        )
        is PlaybackMode.WatchLater -> state.watchLaterVideos(mode.form)
        is PlaybackMode.Bookmarks -> state.bookmarkedVideos(mode.form)
        is PlaybackMode.Creator -> state.library(mode.username, mode.form)?.let { if (mode.form == VideoForm.LONG) state.longVideos(it) else it.videos }.orEmpty()
    }

    /** Every unwatched video, newest first: for long videos, where a round-robin mix doesn't suit. */
    fun latest(libraries: List<CreatorLibrary>, played: Set<String>): List<Video> =
        libraries.flatMap { it.videos }.filter { it.id !in played }.sortedByDescending { it.date }

    /** Unplayed videos only. Round-robin across creators (random order), each creator newest first. */
    fun automix(libraries: List<CreatorLibrary>, played: Set<String>): List<Video> {
        val lists = libraries.map { lib -> lib.videos.filter { it.id !in played } }.filter { it.isNotEmpty() }.shuffled()
        val longest = lists.maxOfOrNull { it.size } ?: 0
        return buildList {
            for (round in 0 until longest) {
                for (list in lists) if (round < list.size) add(list[round])
            }
        }
    }

    /** The most-viewed unplayed videos; if some lack view counts, the rest is filled Automix-style. */
    fun top(libraries: List<CreatorLibrary>, played: Set<String>, count: Int): List<Video> {
        val unplayed = libraries.flatMap { it.videos }.filter { it.id !in played }
        val picked = unplayed.filter { it.viewCount != null }.sortedByDescending { it.viewCount }.take(count).toMutableList()
        if (picked.size < count) {
            picked += automix(libraries, played + picked.map { it.id }).take(count - picked.size)
        }
        return picked
    }

    /** Keeps videos until their total length reaches `seconds`; the video that crosses the limit is the last one. */
    fun limitToDuration(queue: List<Video>, seconds: Double): List<Video> {
        var total = 0.0
        val result = mutableListOf<Video>()
        for (video in queue) {
            result += video
            total += video.duration ?: 0.0
            if (total >= seconds) break
        }
        return result
    }
}

/** "4:05" or "1:02:09". */
fun formatClock(seconds: Double): String {
    val total = kotlin.math.ceil(maxOf(0.0, seconds)).toLong()
    val h = total / 3600
    val m = total / 60 % 60
    val s = total % 60
    return if (h > 0) "%d:%02d:%02d".format(h, m, s) else "%d:%02d".format(m, s)
}

/** "3h 12m", "45m" or "30s", for totals. */
fun formatLength(seconds: Double): String {
    val total = Math.round(seconds)
    val h = total / 3600
    val m = total / 60 % 60
    return when {
        h > 0 && m > 0 -> "${h}h ${m}m"
        h > 0 -> "${h}h"
        m > 0 -> "${m}m"
        else -> "${total}s"
    }
}

fun formatBytes(bytes: Long): String = when {
    bytes >= 1L shl 30 -> "%.1f GB".format(bytes / (1L shl 30).toDouble())
    bytes >= 1L shl 20 -> "%.0f MB".format(bytes / (1L shl 20).toDouble())
    else -> "${bytes / 1024} KB"
}
