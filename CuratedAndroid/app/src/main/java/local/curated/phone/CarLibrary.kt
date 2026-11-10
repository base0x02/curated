package local.curated.phone

import android.content.Context
import android.os.Bundle
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata

/**
 * What Android Auto shows: tabs for Mixes, Categories and Creators. It draws the screens itself from these items, so
 * all that's ours is the content, its pictures, and whether it's a grid or a list. Main thread only.
 */
class CarLibrary(private val context: Context, private val app: AppState, private val playback: Playback) {
    val root: MediaItem = folder(ROOT, "Curated", null, null, null)

    val rootExtras = Bundle().apply {
        putInt(STYLE_BROWSABLE, STYLE_GRID)
        putInt(STYLE_PLAYABLE, STYLE_GRID)
    }

    /** Null for an id that isn't a folder. */
    fun children(id: String): List<MediaItem>? = when {
        id == ROOT -> listOf(
            folder(MIXES, "Mixes", null, CarArtwork.icon(context, R.drawable.ic_car_shuffle), null, playable = STYLE_GRID),
            folder(CATEGORIES, "Categories", null, CarArtwork.icon(context, R.drawable.ic_car_grid), null, browsable = STYLE_GRID),
            folder(CREATORS, "Creators", null, CarArtwork.icon(context, R.drawable.ic_car_people), null, browsable = STYLE_GRID),
        )
        id == MIXES -> mixes()
        id == CATEGORIES -> categories()
        id == CREATORS -> creators()
        id == QUEUE -> queue()
        id.startsWith(CATEGORY) -> category(id.removePrefix(CATEGORY))
        id.startsWith(CREATOR) -> parseCreator(id.removePrefix(CREATOR))?.let { (form, username) -> creatorVideos(form, username) }
        else -> null
    }.let { items -> if (items?.isEmpty() == true && id != QUEUE) listOf(nothingYet()) else items }

    /** Plays what was chosen. Choosing what's already playing just carries on, instead of reshuffling a mix. */
    fun play(id: String) {
        when {
            id.startsWith(MODE) -> parseMode(id.removePrefix(MODE))?.let { mode ->
                if (playback.mode == mode && playback.current != null && !playback.finished) playback.resume() else start(mode, null)
            }
            id.startsWith(VIDEO) -> {
                val parts = id.removePrefix(VIDEO).split(SEPARATOR, limit = 3)
                val form = runCatching { VideoForm.valueOf(parts[0]) }.getOrNull() ?: return
                if (parts.size == 3) start(PlaybackMode.Creator(parts[1], form), parts[2])
            }
            id.startsWith(QUEUE_ITEM) -> {
                val at = playback.queue.indexOfFirst { it.id == id.removePrefix(QUEUE_ITEM) }
                if (at >= 0) playback.play(at)
            }
        }
    }

    /** Creators, then videos, whose name or title has the words in it. */
    fun search(query: String): List<MediaItem> {
        val words = query.lowercase().split(' ').filter { it.isNotBlank() }
        if (words.isEmpty()) return emptyList()
        fun matches(text: String) = text.lowercase().let { text -> words.all { it in text } }
        val creators = creatorRows((app.longLibraries + app.libraries).filter { matches(it.creator.displayName) }, "Creators")
        val videos = (app.longLibraries + app.libraries).flatMap { library -> library.videos.map { library to it } }
            .distinctBy { (_, video) -> video.id }
            .filter { (_, video) -> matches(videoTitle(video)) }
            .take(MAX_ROWS)
            .map { (library, video) -> videoItem(video, VIDEO + library.form.name + SEPARATOR + library.id + SEPARATOR + video.id) }
        return creators + videos
    }

    /** "Play ... on Curated": the first thing found, or Automix when nothing's named or found, as a radio does. */
    fun playSearch(query: String) {
        val found = search(query).firstOrNull()
        when {
            found == null -> start(PlaybackMode.Automix(null, if (app.automixCount(null, VideoForm.SHORT) > 0) VideoForm.SHORT else VideoForm.LONG), null)
            found.mediaMetadata.isPlayable == true -> play(found.mediaId)
            else -> parseCreator(found.mediaId.removePrefix(CREATOR))?.let { (form, username) -> start(PlaybackMode.Creator(username, form), null) }
        }
    }

    private fun videoTitle(video: Video) = if (video.form == VideoForm.LONG) video.displayTitle else video.caption.ifEmpty { "Video" }

    private fun start(mode: PlaybackMode, videoId: String?) {
        val queue = Queues.build(mode, app)
        if (queue.isEmpty()) return
        playback.start(queue, queue.indexOfFirst { it.id == videoId }.coerceAtLeast(0), mode)
        app.form = mode.form
    }

    // MARK: Tabs

    private fun mixes(): List<MediaItem> = buildList {
        val upNext = playback.unwatched.size
        if (playback.current != null && !playback.finished && upNext > 0) {
            add(folder(QUEUE, "Up Next", count(upNext), CarArtwork.tile(context, Tile.Queue), "Now Playing", playable = STYLE_LIST))
        }
        val long = "Long Videos"
        addMix("Latest", Tile.Latest, app.mixLibraries(null, VideoForm.LONG).sumOf { app.unplayedCount(it) }, PlaybackMode.Latest(null), long)
        addMix("Automix", Tile.LongAutomix, app.automixCount(null, VideoForm.LONG), PlaybackMode.Automix(null, VideoForm.LONG), long)
        addMix("Watch Later", Tile.WatchLater, app.watchLaterVideos(VideoForm.LONG).size, PlaybackMode.WatchLater(VideoForm.LONG), long)
        addMix("Bookmarks", Tile.Bookmarks, app.bookmarkedVideos(VideoForm.LONG).size, PlaybackMode.Bookmarks(VideoForm.LONG), long)
        val short = "Short Videos"
        addMix("Automix", Tile.Automix, app.automixCount(null, VideoForm.SHORT), PlaybackMode.Automix(null), short)
        addMix("Top ${PlaybackMode.TOP_COUNT_ALL}", Tile.Top, topCount(null), PlaybackMode.Top(null), short)
        addMix("Vine", Tile.Vine, app.vineLibraries.sumOf { app.unplayedCount(it) }, PlaybackMode.VineAutomix, short)
        addMix("Watch Later", Tile.WatchLater, app.watchLaterVideos(VideoForm.SHORT).size, PlaybackMode.WatchLater(), short)
        addMix("Bookmarks", Tile.Bookmarks, app.bookmarkedVideos(VideoForm.SHORT).size, PlaybackMode.Bookmarks(), short)
    }

    private fun AppState.automixCount(category: String?, form: VideoForm) =
        automixLibraries(category, form).sumOf { library -> library.videos.count { !isPlayed(it) && !isBookmarked(it) } }

    private fun topCount(category: String?) =
        minOf(PlaybackMode.topCount(category), app.mixLibraries(category, VideoForm.SHORT).sumOf { app.unplayedCount(it) })

    private fun MutableList<MediaItem>.addMix(title: String, tile: Tile, count: Int, mode: PlaybackMode, group: String) {
        if (count > 0) add(playable(MODE + modeId(mode), title, count(count), CarArtwork.tile(context, tile), group))
    }

    private fun categories(): List<MediaItem> = app.categories.mapIndexedNotNull { position, category ->
        val videos = app.automixCount(category.id, VideoForm.SHORT) + app.mixLibraries(category.id, VideoForm.LONG).sumOf { app.unplayedCount(it) }
        if (videos == 0) null
        else folder(CATEGORY + category.id, category.name, count(videos), CarArtwork.category(context, category.name, category.symbol, position), null, browsable = STYLE_GRID, playable = STYLE_GRID)
    }

    private fun category(id: String): List<MediaItem> = buildList {
        val long = "Long Videos"
        addMix("Latest", Tile.Latest, app.mixLibraries(id, VideoForm.LONG).sumOf { app.unplayedCount(it) }, PlaybackMode.Latest(id), long)
        addMix("Automix", Tile.LongAutomix, app.automixCount(id, VideoForm.LONG), PlaybackMode.Automix(id, VideoForm.LONG), long)
        val short = "Short Videos"
        addMix("Automix", Tile.Automix, app.automixCount(id, VideoForm.SHORT), PlaybackMode.Automix(id), short)
        addMix("Top ${PlaybackMode.TOP_COUNT_CATEGORY}", Tile.Top, topCount(id), PlaybackMode.Top(id), short)
        addAll(creatorRows(app.libraries(id, VideoForm.LONG) + app.libraries(id, VideoForm.SHORT), "Creators"))
    }

    private fun creators(): List<MediaItem> =
        creatorRows(app.longLibraries.filter { !it.creator.playlist }, "Long Videos") +
            creatorRows(app.playlistLibraries, "Playlists") +
            creatorRows(app.libraries, "Short Videos")

    /** Only creators with a video on this phone. */
    private fun creatorRows(libraries: List<CreatorLibrary>, group: String): List<MediaItem> =
        libraries.filter { it.videos.isNotEmpty() }.map { library ->
            val unplayed = app.unplayedCount(library)
            folder(
                CREATOR + library.form.name + SEPARATOR + library.id, library.creator.displayName,
                if (unplayed > 0) "$unplayed unwatched" else count(library.videos.size),
                CarArtwork.avatar(context, library.id).takeIf { library.creator.hasAvatar } ?: CarArtwork.tile(context, Tile.Empty),
                group, playable = if (library.form == VideoForm.LONG) STYLE_GRID else STYLE_LIST,
            )
        }

    private fun creatorVideos(form: VideoForm, username: String): List<MediaItem> {
        val library = app.library(username, form) ?: return emptyList()
        val videos = if (form == VideoForm.LONG) app.longVideos(library) else library.videos
        // On a creator's own page, the time left rather than their name again.
        return videos.take(MAX_ROWS).map { videoItem(it, VIDEO + form.name + SEPARATOR + username + SEPARATOR + it.id, showCreator = false) }
    }

    private fun queue(): List<MediaItem> =
        playback.queue.drop((playback.index ?: return emptyList()) + 1)
            .filter { playback.mode is PlaybackMode.Bookmarks || !app.isPlayed(it) }
            .take(MAX_ROWS)
            .map { videoItem(it, QUEUE_ITEM + it.id) }

    private fun videoItem(video: Video, id: String, showCreator: Boolean = true): MediaItem {
        val title = videoTitle(video)
        val creator = app.library(video.creator, video.form)?.creator?.displayName?.takeIf { showCreator }
        val length = video.duration?.let(::formatClock)
        return playable(id, title, listOfNotNull(creator, length).joinToString(" · "), CarArtwork.video(context, video.id), null, Bundle().apply {
            val progress = app.progress(video)
            when {
                app.isPlayed(video) -> putInt(PLAYBACK_STATUS, STATUS_PLAYED)
                progress != null -> {
                    putInt(PLAYBACK_STATUS, STATUS_PARTIAL)
                    putDouble(COMPLETION, progress.toDouble())
                }
                else -> putInt(PLAYBACK_STATUS, STATUS_UNPLAYED)
            }
        })
    }

    private fun nothingYet() = folder(
        EMPTY, "No videos yet",
        if (app.pairing == null) "Pair with your Mac on your phone" else "Sync with your Mac on your phone",
        CarArtwork.tile(context, Tile.Empty), null,
    )

    private fun count(videos: Int) = if (videos == 1) "1 video" else "$videos videos"

    // MARK: Items

    private fun folder(id: String, title: String, subtitle: String?, art: android.net.Uri?, group: String?, browsable: Int? = null, playable: Int? = null): MediaItem =
        item(id, title, subtitle, art, isPlayable = false, Bundle().apply {
            group?.let { putString(GROUP_TITLE, it) }
            browsable?.let { putInt(STYLE_BROWSABLE, it) }
            playable?.let { putInt(STYLE_PLAYABLE, it) }
        })

    private fun playable(id: String, title: String, subtitle: String?, art: android.net.Uri?, group: String?, extras: Bundle = Bundle()): MediaItem =
        item(id, title, subtitle, art, isPlayable = true, extras.apply { group?.let { putString(GROUP_TITLE, it) } })

    private fun item(id: String, title: String, subtitle: String?, art: android.net.Uri?, isPlayable: Boolean, extras: Bundle): MediaItem =
        MediaItem.Builder().setMediaId(id).setMediaMetadata(
            MediaMetadata.Builder()
                .setTitle(title)
                .setSubtitle(subtitle)
                .setArtworkUri(art)
                .setIsBrowsable(!isPlayable)
                .setIsPlayable(isPlayable)
                .setMediaType(if (isPlayable) MediaMetadata.MEDIA_TYPE_VIDEO else MediaMetadata.MEDIA_TYPE_FOLDER_MIXED)
                .setExtras(extras)
                .build(),
        ).build()

    // MARK: Ids

    private fun parseCreator(text: String): Pair<VideoForm, String>? {
        val parts = text.split(SEPARATOR, limit = 2)
        val form = runCatching { VideoForm.valueOf(parts[0]) }.getOrNull() ?: return null
        return parts.getOrNull(1)?.let { form to it }
    }

    private fun modeId(mode: PlaybackMode): String {
        val category = when (mode) {
            is PlaybackMode.Automix -> mode.category
            is PlaybackMode.Latest -> mode.category
            is PlaybackMode.Top -> mode.category
            else -> null
        }.orEmpty()
        val kind = when (mode) {
            is PlaybackMode.Automix -> "automix"
            is PlaybackMode.Latest -> "latest"
            is PlaybackMode.Top -> "top"
            is PlaybackMode.WatchLater -> "later"
            is PlaybackMode.Bookmarks -> "bookmarks"
            is PlaybackMode.VineAutomix -> "vine"
            is PlaybackMode.Creator -> "creator"
        }
        return listOf(kind, mode.form.name, category).joinToString(SEPARATOR)
    }

    private fun parseMode(text: String): PlaybackMode? {
        val parts = text.split(SEPARATOR, limit = 3)
        if (parts.size != 3) return null
        val form = runCatching { VideoForm.valueOf(parts[1]) }.getOrNull() ?: return null
        val category = parts[2].ifEmpty { null }
        return when (parts[0]) {
            "automix" -> PlaybackMode.Automix(category, form)
            "latest" -> PlaybackMode.Latest(category)
            "top" -> PlaybackMode.Top(category)
            "later" -> PlaybackMode.WatchLater(form)
            "bookmarks" -> PlaybackMode.Bookmarks(form)
            "vine" -> PlaybackMode.VineAutomix
            else -> null
        }
    }

    companion object {
        const val ROOT = "root"
        const val MIXES = "mixes"
        const val CATEGORIES = "categories"
        const val CREATORS = "creators"
        const val QUEUE = "queue"
        private const val EMPTY = "empty"
        private const val CATEGORY = "category/"
        private const val CREATOR = "creator/"
        private const val MODE = "mode/"
        private const val VIDEO = "video/"
        private const val QUEUE_ITEM = "queued/"
        /** Not in creator keys, categories or video ids. */
        private const val SEPARATOR = "\u001F"
        private const val MAX_ROWS = 100

        // Android Auto's content style and progress extras.
        private const val STYLE_BROWSABLE = "android.media.browse.CONTENT_STYLE_BROWSABLE_HINT"
        private const val STYLE_PLAYABLE = "android.media.browse.CONTENT_STYLE_PLAYABLE_HINT"
        private const val GROUP_TITLE = "android.media.browse.CONTENT_STYLE_GROUP_TITLE_HINT"
        private const val STYLE_LIST = 1
        private const val STYLE_GRID = 2
        private const val PLAYBACK_STATUS = "android.media.extra.PLAYBACK_STATUS"
        private const val COMPLETION = "androidx.media.MediaItem.Extras.COMPLETION_PERCENTAGE"
        private const val STATUS_UNPLAYED = 0
        private const val STATUS_PARTIAL = 1
        private const val STATUS_PLAYED = 2
    }
}
