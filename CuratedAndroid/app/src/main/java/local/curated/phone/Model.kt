package local.curated.phone

import org.json.JSONArray
import org.json.JSONObject
import java.time.Instant
import java.time.temporal.ChronoUnit

/** `symbol`: the SF Symbol name picked on the Mac (shown here as `categoryGlyph`); missing from older Macs. */
data class Category(val id: String, val name: String, val symbol: String? = null)

/** Short videos (TikTok, YouTube Shorts) or long ones (regular YouTube videos and playlists), as on the Mac. */
enum class VideoForm { SHORT, LONG }

/**
 * Which videos a sync downloads, the one saved in Settings. Short is what
 * phones always synced.
 */
enum class SyncForms(val label: String, val query: String) {
    Short("Short", "short"), Long("Long", "long"), All("All", "short,long");

    val includesShort: Boolean get() = this != Long
    val includesLong: Boolean get() = this != Short
    fun includes(form: VideoForm) = if (form == VideoForm.SHORT) includesShort else includesLong
}

data class Creator(
    val username: String,
    val nickname: String?,
    val days: Int,
    val category: String?,
    val hasAvatar: Boolean,
    /** A YouTube playlist (its key is "youtube-playlist@<ID>"): long videos only, in `order`. */
    val playlist: Boolean = false,
    /** A playlist's video IDs in playlist order. */
    val order: List<String> = emptyList(),
    /** A Vine author ("vine@<Vine user ID>"): short videos only, no category. */
    val vine: Boolean = false,
    /** A channel with long videos on, whose older videos can be asked for. False from Macs before API 10. */
) {
    val isYouTube: Boolean get() = isYouTubeKey(username)
    val isVine: Boolean get() = vine || username.startsWith(VINE_KEY_PREFIX)
    /** The @handle without the Mac's "youtube@" key prefix. */
    val handle: String get() = username.removePrefix(YOUTUBE_KEY_PREFIX)
    val displayName: String get() = nickname ?: "@$handle"
    /** Where it's from, for "Open in YouTube". */
    val siteName: String get() = if (isYouTube) "YouTube" else "TikTok"
    /** Its page on YouTube or TikTok. Vine authors and the Mac's Suggestions playlist have none. */
    val pageUrl: String?
        get() = when {
            isVine -> null
            playlist -> username.removePrefix("youtube-playlist@").takeIf { it != "suggestions" }?.let { "https://www.youtube.com/playlist?list=$it" }
            !isYouTube -> "https://www.tiktok.com/@$username"
            handle.startsWith("UC") -> "https://www.youtube.com/channel/$handle"
            else -> "https://www.youtube.com/@$handle"
        }
}

/** The Mac keys YouTube creators as "youtube@<handle>" (TikTok usernames can't contain "@") and TikTok ones by username. */
const val YOUTUBE_KEY_PREFIX = "youtube@"
/** The Mac keys Vine authors as "vine@<Vine user ID>". */
const val VINE_KEY_PREFIX = "vine@"

/** Home's "Other Creators" and Vine cards, alongside the category ids. */
const val OTHER_CARD = "other"
const val VINE_CARD = "vine"
/** Long videos' Playlists card, which is never in a mix, in the playback rules. */
const val PLAYLIST_CARD = "playlists"
/** YouTube channels, and YouTube playlists ("youtube-playlist@<ID>"). */
fun isYouTubeKey(creatorKey: String) = creatorKey.startsWith(YOUTUBE_KEY_PREFIX) || creatorKey.startsWith("youtube-playlist@")

data class Video(
    val id: String,
    val creator: String,
    val date: Instant,
    val caption: String,
    val duration: Double?,
    val viewCount: Long?,
    val size: Long,
    val fileExtension: String,
    val form: VideoForm = VideoForm.SHORT,
    /** Long videos: the title and description (the caption is the description, or the title when there's none). */
    val title: String = "",
    val details: String = "",
    /** Long videos: the Mac has a thumbnail for it at /poster/<id>. */
    val hasPoster: Boolean = false,
    /** Long videos picked by hand on the Mac from a creator's older videos: when. They come first until watched. */
    val pickedAt: Instant? = null,
) {
    /** For long videos: the title, or the caption if there's no title. */
    val displayTitle: String get() = title.ifEmpty { caption.ifEmpty { "Untitled" } }
}

/**
 * A creator's videos of one form that are fully downloaded on this phone: newest first, or a playlist's own order.
 * A YouTube creator with both forms has a short and a long library.
 */
/** Who `OlderVideosScreen` is for. */
data class OlderVideosTarget(val id: String, val name: String)

data class CreatorLibrary(val creator: Creator, val videos: List<Video>, val form: VideoForm = VideoForm.SHORT) {
    val id: String get() = creator.username
}

/** What the Mac sends from GET /manifest. */
data class Manifest(
    val macName: String,
    val timeLimitMinutes: Int,
    val categories: List<Category>,
    val creators: List<Creator>,
    val videos: List<Video>,
    /** The categories whose Automix also plays the Vines (a Funny category, on the Mac). */
    val vineCategories: Set<String> = emptySet(),
    /** When the Mac last finished a download. Null from Macs before API 6, and until its first download. */
    val lastDownloadAt: Instant? = null,
) {
    companion object {
        fun parse(text: String): Manifest {
            val json = JSONObject(text)
            return Manifest(
                macName = json.optString("macName", "Mac"),
                timeLimitMinutes = json.optInt("timeLimitMinutes", 10),
                categories = json.optJSONArray("categories").objects().map {
                    Category(it.getString("id"), it.getString("name"), it.optString("symbol").ifEmpty { null })
                },
                creators = json.optJSONArray("creators").objects().map {
                    Creator(
                        username = it.getString("username"),
                        nickname = it.stringOrNull("nickname")?.takeIf(String::isNotEmpty),
                        days = it.optInt("days", 3),
                        category = it.stringOrNull("category"),
                        hasAvatar = it.optBoolean("hasAvatar"),
                        playlist = it.optBoolean("playlist"),
                        order = it.optJSONArray("order")?.let { a -> (0 until a.length()).map(a::getString) }.orEmpty(),
                        vine = it.optBoolean("vine"),
                    )
                },
                videos = json.optJSONArray("videos").objects().map {
                    Video(
                        id = it.getString("id"),
                        creator = it.getString("creator"),
                        date = Instant.parse(it.getString("date")),
                        caption = it.optString("caption"),
                        duration = if (it.has("duration")) it.getDouble("duration") else null,
                        viewCount = if (it.has("viewCount")) it.getLong("viewCount") else null,
                        size = it.optLong("size"),
                        fileExtension = it.optString("fileExtension", "mp4"),
                        form = if (it.optString("form") == "long") VideoForm.LONG else VideoForm.SHORT,
                        title = it.optString("title"),
                        details = it.optString("details"),
                        hasPoster = it.optBoolean("hasPoster"),
                        pickedAt = if (it.has("pickedAt")) runCatching { Instant.parse(it.getString("pickedAt")) }.getOrNull() else null,
                    )
                },
                vineCategories = json.optJSONArray("vineCategories")?.let { a -> (0 until a.length()).map(a::getString) }.orEmpty().toSet(),
                lastDownloadAt = runCatching { Instant.parse(json.getString("lastDownloadAt")) }.getOrNull(),
            )
        }
    }
}

/**
 * Whether a video has been started, and when that last changed. Shared with the Mac, which keeps
 * the newest change for each video.
 */
data class PlayedMark(val played: Boolean, val at: Instant) {
    companion object {
        /** The Mac reads whole-second ISO 8601 dates only. */
        fun now(played: Boolean) = PlayedMark(played, Instant.now().truncatedTo(ChronoUnit.SECONDS))

        fun fromJson(json: JSONObject): Map<String, PlayedMark> = buildMap {
            for (id in json.keys()) {
                val mark = json.optJSONObject(id) ?: continue
                val at = runCatching { Instant.parse(mark.getString("at")) }.getOrNull() ?: continue
                put(id, PlayedMark(mark.optBoolean("played"), at))
            }
        }

        fun toJson(marks: Map<String, PlayedMark>): JSONObject = JSONObject().apply {
            for ((id, mark) in marks) {
                put(id, JSONObject().put("played", mark.played).put("at", mark.at.truncatedTo(ChronoUnit.SECONDS).toString()))
            }
        }
    }
}

/**
 * How far into a long video playback got, and when that last changed, merged with the Mac: the newest change wins.
 * No `seconds` means it was cleared (the video was finished), which syncs too.
 */
/**
 * What each category does in playback, shared with the Mac and other phones: the newest change on any device wins,
 * swapped through `/positions` (API 8). Categories are named by the keys of a mix's `picked` cards: a category's id,
 * `OTHER_CARD`, `VINE_CARD`, or (long videos, 1x only) `PLAYLIST_CARD`.
 */
data class PlaybackRules(
    /** When these last changed. 1970 until they're first changed, so the Mac's are taken until then. */
    val at: Instant = Instant.EPOCH,
    val short: Cards = Cards(),
    val long: Cards = Cards(),
    /** Long videos go back this far when they resume, to pick the thread up again. */
    val resumeRewindSeconds: Int = 0,
    /** Null until changed here or heard from the Mac; the manifest's until then. */
    val timeLimitMinutes: Int? = null,
) {
    data class Cards(
        /** Left out of Automix unless picked by long-pressing it. A category's own Automix still plays it. */
        val automixOff: Set<String> = emptySet(),
        /** Always plays at 1x, whatever speed is chosen; the chosen speed comes back on the next video. */
        val normalSpeed: Set<String> = emptySet(),
    ) {
        fun toJson(): JSONObject = JSONObject().put("automixOff", JSONArray(automixOff.toList())).put("normalSpeed", JSONArray(normalSpeed.toList()))

        companion object {
            private fun strings(array: JSONArray?) = (0 until (array?.length() ?: 0)).map { array!!.getString(it) }.toSet()

            fun fromJson(json: JSONObject?) = Cards(strings(json?.optJSONArray("automixOff")), strings(json?.optJSONArray("normalSpeed")))
        }
    }

    fun cards(form: VideoForm) = if (form == VideoForm.LONG) long else short

    fun toJson(): JSONObject = JSONObject()
        .put("at", at.toString())
        .put("short", short.toJson())
        .put("long", long.toJson())
        .put("resumeRewindSeconds", resumeRewindSeconds)
        .also { json -> timeLimitMinutes?.let { json.put("timeLimitMinutes", it) } }

    companion object {
        val REWIND_CHOICES = listOf(0, 5, 10, 30)
        val TIME_LIMIT_CHOICES = listOf(5, 10, 15, 20, 30, 45, 60)

        fun fromJson(json: JSONObject?): PlaybackRules? {
            val at = json?.optString("at")?.let { runCatching { Instant.parse(it) }.getOrNull() } ?: return null
            return PlaybackRules(
                at,
                Cards.fromJson(json.optJSONObject("short")),
                Cards.fromJson(json.optJSONObject("long")),
                json.optInt("resumeRewindSeconds", 0),
                if (json.has("timeLimitMinutes")) json.getInt("timeLimitMinutes") else null,
            )
        }
    }
}

/** The long video last playing on any device, so the others can have it ready. No `id` means it was closed or finished. */
data class NowPlayingMark(val id: String?, val at: Instant) {
    /** Newest wins. Within the same second, the larger id, so every device settles on the same mark. */
    fun supersedes(other: NowPlayingMark): Boolean =
        if (at != other.at) at > other.at else (id ?: "") > (other.id ?: "")

    fun toJson(): JSONObject = JSONObject().put("at", at.toString()).also { json -> id?.let { json.put("id", it) } }

    companion object {
        val NONE = NowPlayingMark(null, Instant.EPOCH)

        fun now(id: String?) = NowPlayingMark(id, Instant.now().truncatedTo(ChronoUnit.SECONDS))

        fun fromJson(json: JSONObject?): NowPlayingMark? {
            val at = json?.optString("at")?.let { runCatching { Instant.parse(it) }.getOrNull() } ?: return null
            return NowPlayingMark(if (json.has("id")) json.getString("id") else null, at)
        }
    }
}

data class PositionMark(val seconds: Double?, val at: Instant) {
    /** Newest wins. Within the same second, a cleared one and then the furthest, so every device settles on the same mark. */
    fun supersedes(other: PositionMark?): Boolean {
        if (other == null) return true
        if (at != other.at) return at > other.at
        return (seconds ?: Double.POSITIVE_INFINITY) > (other.seconds ?: Double.POSITIVE_INFINITY)
    }

    companion object {
        fun now(seconds: Double?) = PositionMark(seconds, Instant.now().truncatedTo(ChronoUnit.SECONDS))

        fun fromJson(json: JSONObject?): Map<String, PositionMark> = buildMap {
            if (json == null) return@buildMap
            for (id in json.keys()) {
                val mark = json.optJSONObject(id) ?: continue
                val at = runCatching { Instant.parse(mark.getString("at")) }.getOrNull() ?: continue
                put(id, PositionMark(if (mark.has("seconds")) mark.getDouble("seconds") else null, at))
            }
        }

        fun toJson(marks: Map<String, PositionMark>): JSONObject = JSONObject().apply {
            for ((id, mark) in marks) {
                val json = JSONObject().put("at", mark.at.truncatedTo(ChronoUnit.SECONDS).toString())
                mark.seconds?.let { json.put("seconds", it) }
                put(id, json)
            }
        }
    }
}

/**
 * Whether a video is saved to Watch Later (or bookmarked), and when that last changed. Merged with the Mac like
 * PlayedMark.
 */
data class WatchLaterMark(val saved: Boolean, val at: Instant) {
    companion object {
        fun now(saved: Boolean) = WatchLaterMark(saved, Instant.now().truncatedTo(ChronoUnit.SECONDS))

        fun fromJson(json: JSONObject?): Map<String, WatchLaterMark> = buildMap {
            if (json == null) return@buildMap
            for (id in json.keys()) {
                val mark = json.optJSONObject(id) ?: continue
                val at = runCatching { Instant.parse(mark.getString("at")) }.getOrNull() ?: continue
                put(id, WatchLaterMark(mark.optBoolean("saved"), at))
            }
        }

        fun toJson(marks: Map<String, WatchLaterMark>): JSONObject = JSONObject().apply {
            for ((id, mark) in marks) {
                put(id, JSONObject().put("saved", mark.saved).put("at", mark.at.truncatedTo(ChronoUnit.SECONDS).toString()))
            }
        }
    }
}

/** Where the paired Mac was last reached, and this phone's token for it. */
/** One event of the Mac's `/download/progress`. */
data class MacDownloadProgress(
    val downloading: Boolean,
    val progress: Double?,
    val done: Int?,
    val total: Int?,
    val current: List<String>,
    val lastDownloadAt: Instant?,
) {
    companion object {
        fun parse(json: JSONObject) = MacDownloadProgress(
            downloading = json.optBoolean("downloading"),
            progress = if (json.has("progress")) json.getDouble("progress") else null,
            done = if (json.has("done")) json.getInt("done") else null,
            total = if (json.has("total")) json.getInt("total") else null,
            current = json.optJSONArray("current")?.let { a -> (0 until a.length()).map(a::getString) }.orEmpty(),
            lastDownloadAt = runCatching { Instant.parse(json.getString("lastDownloadAt")) }.getOrNull(),
        )
    }
}

data class Pairing(val host: String, val port: Int, val token: String, val macName: String) {
    /** The computer's own name: the Mac calls itself "Curated on <name>". */
    val computerName: String get() = macName.removePrefix("Curated on ")

    fun toJson(): JSONObject = JSONObject()
        .put("host", host).put("port", port).put("token", token).put("macName", macName)

    companion object {
        fun fromJson(json: JSONObject) = Pairing(
            json.getString("host"), json.getInt("port"), json.getString("token"), json.optString("macName", "Mac"),
        )
    }
}

/** A queue, and whether it's of short or long videos (each has its own Home, mixes and lists, as on the Mac). */
sealed interface PlaybackMode {
    val form: VideoForm

    data class Creator(val username: String, override val form: VideoForm = VideoForm.SHORT) : PlaybackMode
    /**
     * A null category means all creators. `picked`, from long-pressing Home's Automix, limits it to some of Home's cards
     * instead: category ids, `OTHER_CARD` and `VINE_CARD`.
     */
    data class Automix(
        val category: String?, override val form: VideoForm = VideoForm.SHORT, val picked: Set<String>? = null,
    ) : PlaybackMode
    /** Long videos: every unwatched one, newest first. */
    data class Latest(val category: String?) : PlaybackMode {
        override val form get() = VideoForm.LONG
    }
    /** Short videos only. `picked`, from long-pressing Home's Top 15, limits it to some of Home's cards, as for Automix. */
    data class Top(val category: String?, val picked: Set<String>? = null) : PlaybackMode {
        override val form get() = VideoForm.SHORT
    }
    data class WatchLater(override val form: VideoForm = VideoForm.SHORT) : PlaybackMode
    /** Kept out of Automix and never deleted automatically; plays straight through, watched or not. */
    data class Bookmarks(override val form: VideoForm = VideoForm.SHORT) : PlaybackMode
    /** Every Vine, round-robin across their authors. */
    data object VineAutomix : PlaybackMode {
        override val form get() = VideoForm.SHORT
    }

    companion object {
        const val TOP_COUNT_ALL = 15
        const val TOP_COUNT_CATEGORY = 5
        fun topCount(category: String?) = if (category == null) TOP_COUNT_ALL else TOP_COUNT_CATEGORY
    }
}

val PlaybackMode.isAutomix: Boolean get() = this is PlaybackMode.Automix || this is PlaybackMode.VineAutomix
/** A generated mix that runs on until it's out of unwatched videos. */
val PlaybackMode.isOpenMix: Boolean get() = isAutomix || this is PlaybackMode.Latest
val PlaybackMode.topLimit: Int? get() = (this as? PlaybackMode.Top)?.let { PlaybackMode.topCount(it.category) }

fun JSONArray?.objects(): List<JSONObject> =
    if (this == null) emptyList() else (0 until length()).mapNotNull { optJSONObject(it) }

private fun JSONObject.stringOrNull(key: String): String? = if (has(key) && !isNull(key)) getString(key) else null
