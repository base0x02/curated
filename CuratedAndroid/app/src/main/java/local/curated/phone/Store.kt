package local.curated.phone

import android.content.Context
import org.json.JSONObject
import java.io.File

/** Everything the phone keeps, in the app's private storage. */
class Store(context: Context) {
    private val root = context.filesDir
    private val library = File(root, "library")
    val videosDir = File(library, "videos")
    private val avatarsDir = File(library, "avatars")
    /** Long videos' thumbnails from the Mac, "<video id>.jpg". */
    private val postersDir = File(library, "posters")
    private val manifestFile = File(library, "manifest.json")
    private val playedFile = File(root, "played.json")
    private val pairingFile = File(root, "pairing.json")
    private val watchLaterFile = File(root, "watchlater.json")
    private val bookmarksFile = File(root, "bookmarks.json")
    /** Where each long video was left off, in seconds. Kept on the phone only. */
    /** Before positions synced: `{videoID: seconds}`. Only read, to carry them over into `positionMarksFile`. */
    private val positionsFile = File(root, "positions.json")
    private val positionMarksFile = File(root, "positionmarks.json")
    private val nowPlayingFile = File(root, "nowplaying.json")
    private val playbackRulesFile = File(root, "playbackrules.json")
    val prefs = context.getSharedPreferences("curated", Context.MODE_PRIVATE)

    init {
        videosDir.mkdirs()
        avatarsDir.mkdirs()
        postersDir.mkdirs()
    }

    fun loadManifest(): Manifest? =
        runCatching { Manifest.parse(manifestFile.readText()) }.getOrNull()

    fun saveManifest(text: String) = writeAtomically(manifestFile, text)

    fun videoFile(video: Video) = File(videosDir, "${video.id}.${video.fileExtension}")
    fun partialFile(video: Video) = File(videosDir, "${video.id}.${video.fileExtension}.part")
    fun avatarFile(username: String) = File(avatarsDir, "$username.jpg")
    fun posterFile(video: Video) = File(postersDir, "${video.id}.jpg")
    /** By name, for ArtworkProvider, which is only given a video's id. */
    fun posterFile(id: String) = File(postersDir, "$id.jpg")

    /** Only complete files count; downloads land as .part and are renamed when done. */
    fun isDownloaded(video: Video): Boolean = videoFile(video).let { it.exists() && (video.size <= 0 || it.length() == video.size) }

    /** Deletes files for videos the Mac no longer has (or that are no longer synced), and their posters. */
    fun removeVideosExcept(keep: Collection<Video>): Int {
        val names = keep.flatMap { listOf(videoFile(it).name, partialFile(it).name) }.toSet()
        val posters = keep.map { posterFile(it).name }.toSet()
        postersDir.listFiles().orEmpty().filter { it.name !in posters }.forEach { it.delete() }
        return videosDir.listFiles().orEmpty().count { it.name !in names && it.delete() && !it.name.endsWith(".part") }
    }

    fun removeAllVideos() {
        videosDir.listFiles().orEmpty().forEach { it.delete() }
        avatarsDir.listFiles().orEmpty().forEach { it.delete() }
        postersDir.listFiles().orEmpty().forEach { it.delete() }
        manifestFile.delete()
        positionsFile.delete()
        positionMarksFile.delete()
        nowPlayingFile.delete()
        playbackRulesFile.delete()
    }

    fun bytesUsed(): Long = library.walkTopDown().filter { it.isFile }.sumOf { it.length() }

    @Synchronized
    fun loadPlayed(): Map<String, PlayedMark> =
        runCatching { PlayedMark.fromJson(JSONObject(playedFile.readText())) }.getOrDefault(emptyMap())

    @Synchronized
    fun savePlayed(marks: Map<String, PlayedMark>) = writeAtomically(playedFile, PlayedMark.toJson(marks).toString())

    @Synchronized
    fun loadWatchLater(): Map<String, WatchLaterMark> =
        runCatching { WatchLaterMark.fromJson(JSONObject(watchLaterFile.readText())) }.getOrDefault(emptyMap())

    @Synchronized
    fun saveWatchLater(marks: Map<String, WatchLaterMark>) = writeAtomically(watchLaterFile, WatchLaterMark.toJson(marks).toString())

    @Synchronized
    fun loadBookmarks(): Map<String, WatchLaterMark> =
        runCatching { WatchLaterMark.fromJson(JSONObject(bookmarksFile.readText())) }.getOrDefault(emptyMap())

    @Synchronized
    fun saveBookmarks(marks: Map<String, WatchLaterMark>) = writeAtomically(bookmarksFile, WatchLaterMark.toJson(marks).toString())

    @Synchronized
    fun loadPositions(): Map<String, PositionMark> = runCatching {
        PositionMark.fromJson(org.json.JSONObject(positionMarksFile.readText()))
    }.getOrElse {
        // These had no dates before they synced. Date them long ago so any newer change wins.
        runCatching {
            val json = org.json.JSONObject(positionsFile.readText())
            json.keys().asSequence().associateWith { PositionMark(json.getDouble(it), java.time.Instant.EPOCH) }
        }.getOrDefault(emptyMap())
    }

    @Synchronized
    fun savePositions(marks: Map<String, PositionMark>) =
        writeAtomically(positionMarksFile, PositionMark.toJson(marks).toString())

    fun loadNowPlaying(): NowPlayingMark =
        runCatching { NowPlayingMark.fromJson(JSONObject(nowPlayingFile.readText())) }.getOrNull() ?: NowPlayingMark.NONE

    @Synchronized
    fun saveNowPlaying(mark: NowPlayingMark) = writeAtomically(nowPlayingFile, mark.toJson().toString())

    fun loadPlaybackRules(): PlaybackRules =
        runCatching { PlaybackRules.fromJson(JSONObject(playbackRulesFile.readText())) }.getOrNull() ?: PlaybackRules()

    @Synchronized
    fun savePlaybackRules(rules: PlaybackRules) = writeAtomically(playbackRulesFile, rules.toJson().toString())

    fun loadPairing(): Pairing? = runCatching { Pairing.fromJson(JSONObject(pairingFile.readText())) }.getOrNull()

    fun savePairing(pairing: Pairing?) {
        if (pairing == null) pairingFile.delete() else writeAtomically(pairingFile, pairing.toJson().toString())
    }

    private fun writeAtomically(file: File, text: String) {
        file.parentFile?.mkdirs()
        val tmp = File(file.parentFile, "${file.name}.tmp")
        tmp.writeText(text)
        tmp.renameTo(file)
    }
}
