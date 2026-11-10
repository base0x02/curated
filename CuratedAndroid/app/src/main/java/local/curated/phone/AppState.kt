package local.curated.phone

import android.content.Context
import android.os.Build
import android.provider.Settings
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.core.content.edit
import androidx.work.Constraints
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.withContext
import java.time.Instant
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicLong

/** The library on this phone, watched history, and syncing with the Mac. State lives on the main thread. */
class AppState(private val context: Context) {
    val store = Store(context)

    var manifest by mutableStateOf(store.loadManifest()); private set
    /** Short videos, by creator (playlists aren't here). */
    var libraries by mutableStateOf(emptyList<CreatorLibrary>()); private set
    /** Long videos, by creator and playlist. */
    var longLibraries by mutableStateOf(emptyList<CreatorLibrary>()); private set
    /** Vine authors with Vines on this phone. Short videos, kept apart from `libraries` (no category, no Top list). */
    var vineLibraries by mutableStateOf(emptyList<CreatorLibrary>()); private set
    /** Which Home is showing: short or long videos. Always short at launch, as on the Mac. */
    var form by mutableStateOf(VideoForm.SHORT)
    /** What Sync and automatic sync download: short videos, long ones, or both. */
    var syncForms by mutableStateOf(
        runCatching { SyncForms.valueOf(store.prefs.getString(KEY_SYNC_FORMS, null)!!) }.getOrDefault(SyncForms.Short),
    ); private set
    /** Long videos: start the next one when a video ends. Off by default, as on the Mac. */
    var autoplayLong by mutableStateOf(store.prefs.getBoolean(KEY_AUTOPLAY_LONG, false)); private set
    /** Short videos: go on to the next one when a video ends (on by default), or play it again. */
    var autoplayShort by mutableStateOf(store.prefs.getBoolean(KEY_AUTOPLAY_SHORT, true)); private set
    /** Where each long video was left off, including ones cleared (for syncing with the Mac). */
    private var positionMarks by mutableStateOf(store.loadPositions())
    /** Called with the videos whose position just changed because of the Mac, so a paused player can move there. */
    var onPositionsMerged: ((Set<String>) -> Unit)? = null
    /** The long video last playing on any device. */
    var nowPlayingMark by mutableStateOf(store.loadNowPlaying()); private set
    /** A newer now playing mark just arrived from the Mac. */
    var onNowPlayingMerged: (() -> Unit)? = null
    /** Which categories Automix leaves out or keep to 1x, and the time limit. Shared with the Mac. */
    var playbackRules by mutableStateOf(store.loadPlaybackRules()); private set
    /** The rules changed, here or from the Mac, so the playing video can change speed. */
    var onPlaybackRulesChanged: (() -> Unit)? = null
    @Volatile private var refreshingAvatars = false
    @Volatile private var syncLapStarted = 0L
    /** A position changed here since the Mac last heard. */
    private var positionsChanged = false
    private var positionsSend: kotlinx.coroutines.Job? = null
    private var exchangingPositions = false
    private var marks = store.loadPlayed()
    var played by mutableStateOf(playedIds(marks)); private set
    /** Watch Later history, including removals (for syncing with the Mac). */
    var watchLaterMarks by mutableStateOf(store.loadWatchLater()); private set
    /** Bookmarks, including removals (for syncing with the Mac). */
    var bookmarkMarks by mutableStateOf(store.loadBookmarks()); private set
    var pairing by mutableStateOf(store.loadPairing()); private set

    var isSyncing by mutableStateOf(false); private set
    var syncStep by mutableStateOf(""); private set
    /** 0–1 while downloading videos; null while there's nothing to measure. */
    var syncProgress by mutableStateOf<Float?>(null); private set
    var lastSyncMessage by mutableStateOf(store.prefs.getString(KEY_LAST_MESSAGE, null)); private set
    var lastSyncAt by mutableStateOf(store.prefs.getLong(KEY_LAST_SYNC, 0).takeIf { it > 0 }?.let(Instant::ofEpochMilli)); private set
    var isRequestingDownload by mutableStateOf(false); private set
    /** Why the Mac didn't start a Force Download, or couldn't be asked, until Settings closes. */
    var forceDownloadMessage by mutableStateOf<String?>(null); private set
    /** The Mac's download while Settings is following it; null when nothing's downloading. */
    var macDownload by mutableStateOf<MacDownloadProgress?>(null); private set
    /** A download seen on the Mac finished, and no sync has fetched it yet: Settings shows a checkmark. */
    var macDownloadFinished by mutableStateOf(store.prefs.getBoolean(KEY_MAC_FINISHED, false)); private set
    private var macDownloadWatch: Job? = null
    /**
     * Videos asked for from the Mac (Older Videos) and not fetched yet. The Mac's download is followed until they are,
     * wherever you are in the app, and a sync brings them whichever kinds it's syncing. Saved, since it can finish with
     * this app closed.
     */
    @Volatile private var requestedVideoIDs: Set<String> = store.prefs.getStringSet(KEY_REQUESTED, null).orEmpty().toSet()
    private var followedDownloadAt by mutableStateOf<Instant?>(null)
    /** When the Mac last finished a download: from the last sync, or newer while following its downloads. */
    val lastMacDownloadAt: Instant? get() = listOfNotNull(manifest?.lastDownloadAt, followedDownloadAt).maxOrNull()
    var autoSync by mutableStateOf(store.prefs.getBoolean(KEY_AUTO_SYNC, false)); private set
    var appearance by mutableStateOf(
        runCatching { Appearance.valueOf(store.prefs.getString(KEY_APPEARANCE, null)!!) }.getOrDefault(Appearance.System),
    ); private set
    /** What's behind Home, and the palette each style uses. Kept on the phone only. */
    var backgroundStyle by mutableStateOf(
        runCatching { BackgroundStyle.valueOf(store.prefs.getString(KEY_BACKGROUND, null)!!) }.getOrDefault(BackgroundStyle.Aurora),
    ); private set
    var auroraPalette by mutableStateOf(store.prefs.getString(KEY_AURORA_PALETTE, null) ?: AuroraPalette.Curated.id); private set
    var holidayPalette by mutableStateOf(store.prefs.getString(KEY_HOLIDAY_PALETTE, null) ?: AuroraPalette.holiday.first().id); private set
    /** Home's wordmark becomes the season's holiday one (`Holiday.current`). */
    var holidayWordmarks by mutableStateOf(store.prefs.getBoolean(KEY_HOLIDAY_WORDMARKS, false)); private set

    /** The aurora's palette for the chosen style. */
    val palette: AuroraPalette
        get() = when (backgroundStyle) {
            BackgroundStyle.Aurora -> AuroraPalette.named(auroraPalette, AuroraPalette.aurora)
            BackgroundStyle.Holiday -> AuroraPalette.named(holidayPalette, AuroraPalette.holiday)
        }

    /** Home-screen cards the user collapsed, by category id (or "other"). Kept on the phone only. */
    var collapsedCards by mutableStateOf(store.prefs.getStringSet(KEY_COLLAPSED, null).orEmpty().toSet()); private set

    /** Called on the main thread when a sync removes or adds videos, so the playing queue can be rebuilt. */
    var onLibraryChanged: (() -> Unit)? = null

    private val syncLock = Mutex()
    private val scope = MainScope()

    /** The first-launch pairing screen (OnboardingScreen) covers everything while this is set. */
    var onboarding by mutableStateOf(false)

    init {
        rebuildLibraries()
        onboarding = pairing == null && libraries.isEmpty()
    }

    val timeLimitMinutes: Int get() = playbackRules.timeLimitMinutes ?: manifest?.timeLimitMinutes ?: 10
    val categories: List<Category> get() = manifest?.categories.orEmpty()

    fun category(id: String?): Category? = id?.let { categories.firstOrNull { c -> c.id == it } }
    fun library(username: String, form: VideoForm = VideoForm.SHORT): CreatorLibrary? =
        (if (form == VideoForm.SHORT) libraries + vineLibraries else longLibraries).firstOrNull { it.id == username }

    /** A form's creators (and, for long videos, playlists), or only those in `category`. */
    fun libraries(category: String?, form: VideoForm = VideoForm.SHORT): List<CreatorLibrary> {
        val all = if (form == VideoForm.SHORT) libraries else longLibraries
        return if (category == null) all else all.filter { it.creator.category == category }
    }

    /** What the mixes draw from: playlists are watched on their own, in order, so they stay out. */
    fun mixLibraries(category: String?, form: VideoForm) = libraries(category, form).filter { !it.creator.playlist }

    /**
     * What Automix draws from: `mixLibraries`, plus every Vine as one more creator in the main short Automix and the
     * categories the Mac names (a Funny category's). With no `category` it's the main Automix, which leaves out the
     * cards turned off in Settings.
     */
    fun automixLibraries(category: String?, form: VideoForm): List<CreatorLibrary> {
        val off = if (category == null) playbackRules.cards(form).automixOff else emptySet()
        val mix = mixLibraries(category, form).filter { cardKey(it.creator) !in off }
        val vines = vineLibraries
        if (form != VideoForm.SHORT || vines.isEmpty() || VINE_CARD in off || (category != null && category !in manifest?.vineCategories.orEmpty())) return mix
        return mix + allVines(vines)
    }

    /** Home's card a creator is under, as named in a mix's `picked` and the playback rules. */
    fun cardKey(creator: Creator): String = when {
        creator.isVine -> VINE_CARD
        creator.playlist -> PLAYLIST_CARD
        else -> category(creator.category)?.id ?: OTHER_CARD
    }

    /** Whether `video`, played from `mode`, stays at 1x. A long video in a playlist's queue goes by the playlist. */
    fun playsAtNormalSpeed(video: Video, mode: PlaybackMode?): Boolean {
        var creator = library(video.creator, video.form)?.creator
        if (video.form == VideoForm.LONG && mode is PlaybackMode.Creator) {
            library(mode.username, VideoForm.LONG)?.creator?.takeIf { it.playlist }?.let { creator = it }
        }
        return (creator?.let(::cardKey) ?: OTHER_CARD) in playbackRules.cards(video.form).normalSpeed
    }

    /** Changes the playback rules from here, dated so the Mac takes them. */
    fun updatePlaybackRules(change: (PlaybackRules) -> PlaybackRules) {
        val rules = change(playbackRules)
        if (rules == playbackRules) return
        val dated = rules.copy(at = Instant.now().truncatedTo(java.time.temporal.ChronoUnit.SECONDS))
        playbackRules = dated
        store.savePlaybackRules(dated)
        onPlaybackRulesChanged?.invoke()
        positionsChanged = true
        sendPositionsSoon()
    }

    /** `videos` with the unwatched ones picked by hand first, latest pick first. Once watched they go back to their place. */
    fun handPickedFirst(videos: List<Video>): List<Video> {
        val first = videos.filter { it.pickedAt != null && !isPlayed(it) }
        if (first.isEmpty()) return videos
        val ids = first.map { it.id }.toSet()
        return first.sortedByDescending { it.pickedAt } + videos.filter { it.id !in ids }
    }

    /** A client that's reached the Mac, for asking it things. Null if it can't be reached or this isn't paired. */
    suspend fun macClient(): SyncClient? = pairing?.let { connect(it) }

    /** Whose older videos are being picked from (OlderVideosScreen, over everything). */
    var olderVideos by mutableStateOf<OlderVideosTarget?>(null)
    /** The add-creator form is showing (AddCreatorScreen, over everything). */
    var addingCreator by mutableStateOf(false)

    /** A long creator's videos as they're shown and queued. A playlist keeps its own order. */
    fun longVideos(library: CreatorLibrary): List<Video> =
        if (library.creator.playlist) library.videos else handPickedFirst(library.videos)

    /** `mixLibraries` for a pick of Home's cards (`PlaybackMode.Automix.picked`, `PlaybackMode.Top.picked`). */
    fun mixLibraries(picked: Set<String>, form: VideoForm) =
        mixLibraries(null, form).filter { (category(it.creator.category)?.id ?: OTHER_CARD) in picked }

    /** Automix for a pick of Home's cards: Vines only when their card is picked. */
    fun automixLibraries(picked: Set<String>, form: VideoForm): List<CreatorLibrary> {
        val mix = mixLibraries(picked, form)
        val vines = vineLibraries
        if (form != VideoForm.SHORT || vines.isEmpty() || VINE_CARD !in picked) return mix
        return mix + allVines(vines)
    }

    /** Every Vine as one creator, so they take about one creator's share of a mix. */
    private fun allVines(vines: List<CreatorLibrary>): CreatorLibrary {
        val all = Creator(VINE_KEY_PREFIX + "classics", "Vine", 1, null, hasAvatar = false, vine = true)
        return CreatorLibrary(all, vines.flatMap { it.videos }.shuffled())
    }

    /** For the "Other Creators" card. Playlists have their own card. */
    fun uncategorizedLibraries(form: VideoForm): List<CreatorLibrary> =
        libraries(null, form).filter { category(it.creator.category) == null && !it.creator.playlist }

    val playlistLibraries: List<CreatorLibrary> get() = longLibraries.filter { it.creator.playlist }

    /** Every video on the phone, short and long, once each (a video can be both a creator's and in a playlist). */
    val allVideos: List<Video> get() = (libraries + longLibraries + vineLibraries).flatMap { it.videos }.distinctBy { it.id }

    fun isPlayed(video: Video) = video.id in played
    fun unplayedCount(library: CreatorLibrary) = library.videos.count { it.id !in played }
    /** For the mixes' counts, so playlists aren't included (and Vines are, where Automix plays them). */
    fun unplayedCount(category: String?, form: VideoForm = VideoForm.SHORT) =
        automixLibraries(category, form).sumOf { unplayedCount(it) }

    /** A form's videos on this phone, once each: its creators', and for short videos the Vines. */
    private fun videos(form: VideoForm): List<Video> =
        (libraries(null, form) + if (form == VideoForm.SHORT) vineLibraries else emptyList()).flatMap { it.videos }.distinctBy { it.id }

    // MARK: Resume

    fun resumePosition(video: Video): Double? = positionMarks[video.id]?.seconds

    fun setResumePosition(video: Video, seconds: Double?) {
        if (positionMarks[video.id]?.seconds == seconds) return
        positionMarks = positionMarks + (video.id to PositionMark.now(seconds))
        positionsChanged = true
        store.savePositions(positionMarks)
        if (seconds == null) clearNowPlaying(video)
    }

    /** `video` started or resumed here. */
    fun setNowPlaying(video: Video) = updateNowPlaying(NowPlayingMark.now(video.id))

    /** `video` was closed or finished, so no other device should offer it. */
    fun clearNowPlaying(video: Video) {
        if (nowPlayingMark.id == video.id) updateNowPlaying(NowPlayingMark.now(null))
    }

    private fun updateNowPlaying(mark: NowPlayingMark) {
        nowPlayingMark = mark
        positionsChanged = true
        store.saveNowPlaying(mark)
    }

    /** Takes what the Mac sent back for `/positions`: positions first, since a now playing video resumes from them. */
    private fun merge(reply: PositionsReply) {
        mergePositions(reply.positions)
        val incoming = reply.nowPlaying
        if (incoming != null && incoming.supersedes(nowPlayingMark)) {
            nowPlayingMark = incoming
            store.saveNowPlaying(incoming)
            onNowPlayingMerged?.invoke()
        }
        // The Mac sends back the newest it knows. Older means this changed while the swap was under way.
        val rules = reply.playback
        if (rules != null && rules.at >= playbackRules.at && rules != playbackRules) {
            playbackRules = rules
            store.savePlaybackRules(rules)
            onPlaybackRulesChanged?.invoke()
        }
    }

    /**
     * Keeps the newest position of each video. One saved before the video was last marked watched is cleared, so a
     * watched video starts from the top on every device.
     */
    private fun mergePositions(incoming: Map<String, PositionMark>) {
        val merged = positionMarks.toMutableMap()
        for ((id, mark) in incoming) if (mark.supersedes(merged[id])) merged[id] = mark
        for ((id, mark) in merged.toMap()) {
            val playedMark = marks[id]
            if (mark.seconds != null && playedMark != null && playedMark.played && playedMark.at >= mark.at) {
                merged[id] = PositionMark(null, playedMark.at)
            }
        }
        if (merged == positionMarks) return
        val changed = merged.keys.filter { merged[it]?.seconds != positionMarks[it]?.seconds }.toSet()
        positionMarks = merged
        store.savePositions(merged)
        onPositionsMerged?.invoke(changed)
    }

    /** Tells the Mac about a position changed here, in a moment: pausing and switching videos come in bursts. */
    fun sendPositionsSoon() {
        if (!positionsChanged || pairing == null) return
        positionsSend?.cancel()
        positionsSend = scope.launch {
            kotlinx.coroutines.delay(2000)
            exchangePositions()
        }
    }

    /**
     * Swaps positions with the Mac, so a video picks up here where another device left it. Small and quick, so it runs
     * whenever the app opens or leaves a video, whatever the auto-sync setting. If the Mac can't be reached, the next
     * time will do.
     */
    fun exchangePositions() {
        val saved = pairing ?: return
        if (exchangingPositions) return
        exchangingPositions = true
        scope.launch {
            try {
                val client = connect(saved)
                if (!isSyncing) syncStep = ""
                if (client == null) return@launch
                positionsChanged = false
                val local = positionMarks
                val nowPlaying = nowPlayingMark
                val rules = playbackRules
                val reply = runCatching { withContext(Dispatchers.IO) { client.positions(local, nowPlaying, rules) } }.getOrNull()
                if (reply != null) merge(reply) else positionsChanged = true
            } finally {
                exchangingPositions = false
            }
        }
    }

    /** How much of a long video has been watched, 0–1, while there's somewhere to resume from. */
    fun progress(video: Video): Float? {
        val position = positionMarks[video.id]?.seconds ?: return null
        val length = video.duration?.takeIf { it > 0 } ?: return null
        return (position / length).toFloat().coerceIn(0f, 1f)
    }

    fun updateSyncForms(value: SyncForms) {
        syncForms = value
        store.prefs.edit { putString(KEY_SYNC_FORMS, value.name) }
    }

    fun updateAutoplayShort(enabled: Boolean) {
        autoplayShort = enabled
        store.prefs.edit { putBoolean(KEY_AUTOPLAY_SHORT, enabled) }
    }

    fun updateAutoplayLong(enabled: Boolean) {
        autoplayLong = enabled
        store.prefs.edit { putBoolean(KEY_AUTOPLAY_LONG, enabled) }
    }

    // MARK: Watched history

    fun setPlayed(video: Video, value: Boolean) = setPlayed(listOf(video), value)

    fun setPlayed(videos: List<Video>, value: Boolean) {
        val changed = videos.filter { (it.id in played) != value }
        if (changed.isEmpty()) return
        val mark = PlayedMark.now(value)
        marks = marks + changed.associate { it.id to mark }
        played = playedIds(marks)
        store.savePlayed(marks)
        // A watched video starts from the beginning next time.
        if (value && changed.any { positionMarks[it.id]?.seconds != null }) {
            val cleared = PositionMark.now(null)
            positionMarks = positionMarks + changed.filter { positionMarks[it.id]?.seconds != null }.associate { it.id to cleared }
            positionsChanged = true
            store.savePositions(positionMarks)
        }
        if (value) changed.forEach { clearNowPlaying(it) }
        // Watching a saved video takes it off Watch Later.
        if (value) setWatchLater(changed, false)
    }

    // MARK: Watch Later

    fun isSavedForLater(video: Video) = watchLaterMarks[video.id]?.saved == true

    fun setWatchLater(videos: List<Video>, saved: Boolean) {
        val changed = videos.filter { isSavedForLater(it) != saved }
        if (changed.isEmpty()) return
        val mark = WatchLaterMark.now(saved)
        watchLaterMarks = watchLaterMarks + changed.associate { it.id to mark }
        store.saveWatchLater(watchLaterMarks)
    }

    /** Saved, unwatched videos of `form` on this phone, oldest save first. */
    fun watchLaterVideos(form: VideoForm): List<Video> =
        videos(form)
            .filter { isSavedForLater(it) && !isPlayed(it) }
            .sortedBy { watchLaterMarks[it.id]?.at }

    // MARK: Bookmarks

    fun isBookmarked(video: Video) = bookmarkMarks[video.id]?.saved == true

    val bookmarkedIds: Set<String> get() = bookmarkMarks.filterValues { it.saved }.keys

    fun setBookmarked(video: Video, bookmarked: Boolean) {
        if (isBookmarked(video) == bookmarked) return
        bookmarkMarks = bookmarkMarks + (video.id to WatchLaterMark.now(bookmarked))
        store.saveBookmarks(bookmarkMarks)
    }

    /** Bookmarked videos of `form` on this phone, watched or not, most recently bookmarked first. */
    fun bookmarkedVideos(form: VideoForm): List<Video> =
        videos(form).filter(::isBookmarked).sortedByDescending { bookmarkMarks[it.id]?.at }

    private fun mergeBookmarks(incoming: Map<String, WatchLaterMark>) {
        val merged = bookmarkMarks.toMutableMap()
        for ((id, mark) in incoming) {
            val mine = merged[id]
            if (mine == null || mark.at > mine.at) merged[id] = mark
        }
        bookmarkMarks = merged
        store.saveBookmarks(merged)
    }

    private fun mergeWatchLater(incoming: Map<String, WatchLaterMark>) {
        val merged = watchLaterMarks.toMutableMap()
        for ((id, mark) in incoming) {
            val mine = merged[id]
            if (mine == null || mark.at > mine.at) merged[id] = mark
        }
        watchLaterMarks = merged
        store.saveWatchLater(merged)
    }

    /** Keeps the newer state of each video. */
    private fun mergePlayed(incoming: Map<String, PlayedMark>) {
        val merged = marks.toMutableMap()
        for ((id, mark) in incoming) {
            val mine = merged[id]
            if (mine == null || mark.at > mine.at) merged[id] = mark
        }
        marks = merged
        played = playedIds(merged)
        store.savePlayed(merged)
    }

    private fun playedIds(marks: Map<String, PlayedMark>) = marks.filterValues { it.played }.keys

    /**
     * Short libraries: every creator that isn't a playlist, except YouTube creators the Mac only sends long videos
     * for. Long libraries: creators with long videos, and playlists. The Mac sends each video once, so a playlist is
     * built from its `order`: every long video on the phone in it, whichever creator it came under.
     */
    private fun rebuildLibraries() {
        val m = manifest ?: run { libraries = emptyList(); longLibraries = emptyList(); vineLibraries = emptyList(); return }
        val downloaded = m.videos.filter { store.isDownloaded(it) }
        val short = downloaded.filter { it.form == VideoForm.SHORT }.groupBy { it.creator }
        val long = downloaded.filter { it.form == VideoForm.LONG }.groupBy { it.creator }
        val sentLong = m.videos.filter { it.form == VideoForm.LONG }.map { it.creator }.toSet()
        val sentShort = m.videos.filter { it.form == VideoForm.SHORT }.map { it.creator }.toSet()
        libraries = m.creators
            .filter { !it.playlist && !it.isVine && (it.username in sentShort || it.username !in sentLong) }
            .map { CreatorLibrary(it, short[it.username].orEmpty().sortedByDescending { v -> v.date }) }
        longLibraries = m.creators
            .filter { it.playlist || it.username in sentLong }
            .map { creator ->
                val ordered = if (creator.playlist) {
                    val position = creator.order.withIndex().associate { (i, id) -> id to i }
                    downloaded.filter { it.form == VideoForm.LONG && it.id in position }.distinctBy { it.id }
                        .sortedBy { position[it.id] }
                } else {
                    long[creator.username].orEmpty().sortedByDescending { it.date }
                }
                CreatorLibrary(creator, ordered, VideoForm.LONG)
            }
        // Only authors with a Vine downloaded here: the rest would be empty avatars.
        vineLibraries = m.creators.filter { it.isVine }
            .map { CreatorLibrary(it, short[it.username].orEmpty().sortedByDescending { v -> v.date }) }
            .filter { it.videos.isNotEmpty() }
    }

    // MARK: Pairing

    val deviceName: String
        get() = Settings.Global.getString(context.contentResolver, Settings.Global.DEVICE_NAME)?.takeIf { it.isNotBlank() }
            ?: Build.MODEL

    /** Returns an error message, or null once paired. */
    suspend fun pair(host: String, port: Int, code: String): String? {
        val result = withContext(Dispatchers.IO) {
            runCatching { SyncClient(host, port).pair(code.filter(Char::isDigit), deviceName) }
        }
        val json = result.getOrElse { return it.friendlyMessage() }
        val newPairing = Pairing(host, port, json.getString("token"), json.optString("macName", "Mac"))
        store.savePairing(newPairing)
        pairing = newPairing
        return null
    }

    /** Forgets the Mac. Downloaded videos stay. */
    /**
     * Forgets the Mac and everything that came from it: videos, avatars, the manifest, and the watched, Watch Later
     * and bookmark history (the Mac keeps its own, so pairing again brings them back). Appearance and the other
     * settings for this phone stay.
     */
    fun unpair() {
        store.savePairing(null)
        pairing = null
        // The phone is cleared, so it starts over at the pairing screen.
        onboarding = true
        store.removeAllVideos()
        manifest = null
        marks = emptyMap()
        played = emptySet()
        watchLaterMarks = emptyMap()
        bookmarkMarks = emptyMap()
        positionMarks = emptyMap()
        nowPlayingMark = NowPlayingMark.NONE
        playbackRules = PlaybackRules()
        onPlaybackRulesChanged?.invoke()
        positionsChanged = false
        store.savePlayed(emptyMap())
        store.saveWatchLater(emptyMap())
        store.saveBookmarks(emptyMap())
        collapsedCards = emptySet()
        lastSyncMessage = null
        lastSyncAt = null
        stopWatchingMacDownload()
        markMacDownloadFinished(false)
        setRequestedVideos(emptySet())
        followedDownloadAt = null
        store.prefs.edit {
            remove(KEY_MAC_BASELINE)
            remove(KEY_COLLAPSED)
            remove(KEY_LAST_MESSAGE)
            remove(KEY_LAST_SYNC)
        }
        rebuildLibraries()
        onLibraryChanged?.invoke()
    }

    // MARK: Syncing

    /** Starts a sync that keeps going if the screen that asked for it goes away. */
    fun syncInBackground(forms: SyncForms? = null) {
        scope.launch { sync(forms) }
    }

    /**
     * Pulls new videos, drops ones the Mac deleted, and swaps watched history. Returns a summary. Any sync but the one
     * a finished Mac download starts (`afterMacDownload`) removes that download's checkmark.
     */
    suspend fun sync(forms: SyncForms? = null, afterMacDownload: Boolean = false): String {
        if (!syncLock.tryLock()) return "Already syncing"
        try {
            withContext(Dispatchers.Main) {
                isSyncing = true
                syncProgress = null
            }
            val message = try {
                runSync(forms ?: withContext(Dispatchers.Main) { syncForms }, afterMacDownload)
            } catch (e: Exception) {
                e.friendlyMessage()
            }
            withContext(Dispatchers.Main) {
                lastSyncMessage = message
                store.prefs.edit { putString(KEY_LAST_MESSAGE, message) }
            }
            return message
        } finally {
            withContext(Dispatchers.Main) {
                isSyncing = false
                syncStep = ""
                syncProgress = null
            }
            syncLock.unlock()
        }
    }

    /** Asks the Mac to download everything now. The new videos and the time it finished arrive with a later sync. */
    fun forceDownload() {
        val saved = pairing ?: return
        if (isRequestingDownload) return
        isRequestingDownload = true
        markMacDownloadFinished(false)
        forceDownloadMessage = null
        scope.launch {
            val message = try {
                val client = connect(saved) ?: throw SyncException(
                    "Couldn't reach ${saved.macName}. Make sure Curated is open on your Mac with phone sync turned on, " +
                        "and that you're on the same Wi-Fi (or plugged in with USB sync set up).",
                )
                withContext(Dispatchers.IO) { client.forceDownload() }.also {
                    // Again from the start, in case the last look at the Mac is just ending.
                    macDownloadWatch?.cancel()
                    macDownloadWatch = null
                    watchMacDownload()
                }
            } catch (e: SyncException) {
                if (e.status == 404) "Update Curated on your Mac to use Force Download." else e.friendlyMessage()
            } catch (e: Exception) {
                e.friendlyMessage()
            }
            withContext(Dispatchers.Main) {
                forceDownloadMessage = message
                isRequestingDownload = false
                if (!isSyncing) syncStep = ""
            }
        }
    }

    /**
     * Follows the Mac's download on a connection the Mac closes when it's over; with nothing downloading, that's at once.
     * If the connection breaks mid-download it tries again a few times, then waits for the next call.
     */
    fun watchMacDownload() {
        val saved = pairing ?: return
        if (macDownloadWatch != null) return
        macDownloadWatch = scope.launch {
            var failures = 0
            while (isActive) {
                try {
                    val client = connect(saved) ?: throw java.io.IOException("Mac not found")
                    if (!isSyncing) syncStep = ""
                    withContext(Dispatchers.IO) {
                        client.followDownload { event -> withContext(Dispatchers.Main) { apply(event) } }
                    }
                    break
                } catch (e: CancellationException) {
                    throw e
                } catch (e: SyncException) {
                    break  // An older Mac, or unpaired.
                } catch (e: Exception) {
                    failures++
                    if (macDownload == null || failures >= 3) break
                    delay(3000)
                }
            }
            macDownload = null
            macDownloadWatch = null
        }
    }

    private fun setRequestedVideos(ids: Set<String>) {
        requestedVideoIDs = ids
        store.prefs.edit { putStringSet(KEY_REQUESTED, ids) }
    }

    /** The Mac started downloading these: fetches them when it's done. */
    fun followRequestedVideos(ids: Collection<String>) {
        setRequestedVideos(requestedVideoIDs + ids)
        // Again from the start, in case the last look at the Mac is just ending.
        macDownloadWatch?.cancel()
        macDownloadWatch = null
        watchMacDownload()
    }

    /** Back on screen: videos asked for earlier may be ready, or still coming. */
    fun resumeFollowingRequestedVideos() {
        if (requestedVideoIDs.isNotEmpty()) watchMacDownload()
    }

    /**
     * Closes the connection, for when the app leaves the screen or, unless videos asked for are on their way
     * (`keepingRequested`), when Settings closes.
     */
    fun stopWatchingMacDownload(keepingRequested: Boolean = false) {
        forceDownloadMessage = null
        if (keepingRequested && requestedVideoIDs.isNotEmpty()) return
        macDownloadWatch?.cancel()
        macDownloadWatch = null
        macDownload = null
    }

    private fun markMacDownloadFinished(finished: Boolean) {
        macDownloadFinished = finished
        store.prefs.edit { putBoolean(KEY_MAC_FINISHED, finished) }
    }

    /**
     * The saved baseline is the Mac's last download time when one was seen running (0 if none): a newer time afterwards
     * means it finished, and the same one that it was stopped. Saved, since it can finish with this app closed.
     */
    private fun apply(event: MacDownloadProgress) {
        event.lastDownloadAt?.let { followedDownloadAt = it }
        val at = event.lastDownloadAt?.toEpochMilli() ?: 0
        if (event.downloading) {
            if (!store.prefs.contains(KEY_MAC_BASELINE)) store.prefs.edit { putLong(KEY_MAC_BASELINE, at) }
            macDownload = event
            if (macDownloadFinished) markMacDownloadFinished(false)
            forceDownloadMessage = null
        } else {
            macDownload = null
            // The Mac had started on videos asked for when it said so, so not downloading now means it's over.
            var fetch = requestedVideoIDs.isNotEmpty()
            if (store.prefs.contains(KEY_MAC_BASELINE)) {
                val finished = store.prefs.getLong(KEY_MAC_BASELINE, 0) != at
                store.prefs.edit { remove(KEY_MAC_BASELINE) }
                if (finished) {
                    markMacDownloadFinished(true)
                    fetch = true
                }
            }
            if (fetch) syncAfterMacDownload()
        }
    }

    /** Fetches what the Mac just downloaded, after any sync under way, which may have listed the videos too early. */
    private fun syncAfterMacDownload() {
        scope.launch {
            while (isSyncing) delay(1000)
            sync(afterMacDownload = true)
        }
    }

    private suspend fun step(text: String, progress: Float? = null) = withContext(Dispatchers.Main) {
        syncStep = text
        syncProgress = progress
    }

    /**
     * Fetches the Mac's whole list (short and long; it's small), but only downloads `forms`. Nothing is removed for
     * being a kind that wasn't picked: only videos the Mac no longer has leave the phone.
     */
    private suspend fun runSync(forms: SyncForms, afterMacDownload: Boolean): String {
        val saved = withContext(Dispatchers.Main) { pairing } ?: return "Pair with your Mac first"
        step("Looking for your Mac…")
        val syncStarted = System.currentTimeMillis()
        syncLapStarted = syncStarted
        val client = connect(saved, lookUp = true) ?: throw SyncException(
            "Couldn't reach ${saved.macName}. Make sure Curated is open on your Mac with phone sync turned on, " +
                "and that you're on the same Wi-Fi (or plugged in with USB sync set up).",
        )

        syncLap("find Mac (${client.host})")
        step("Checking for new videos…")
        // Vines come with the short videos: listed every time, downloaded when short videos are.
        val manifestText = withContext(Dispatchers.IO) { client.manifest(SyncForms.All, vine = true) }
        val newManifest = Manifest.parse(manifestText)

        step("Syncing watched videos…")
        val (localMarks, localLater, localBookmarks) = withContext(Dispatchers.Main) {
            Triple(marks, watchLaterMarks, bookmarkMarks)
        }
        val (merged, mergedLater, mergedBookmarks) = withContext(Dispatchers.IO) {
            client.played(localMarks, localLater, localBookmarks)
        }
        withContext(Dispatchers.Main) {
            mergePlayed(merged)
            mergeWatchLater(mergedLater)
            mergeBookmarks(mergedBookmarks)
        }
        // After the watched marks, which can clear positions. An older Mac doesn't have this.
        val (localPositions, localNowPlaying, localRules) = withContext(Dispatchers.Main) {
            positionsChanged = false
            Triple(positionMarks, nowPlayingMark, playbackRules)
        }
        runCatching { withContext(Dispatchers.IO) { client.positions(localPositions, localNowPlaying, localRules) } }.getOrNull()?.let {
            withContext(Dispatchers.Main) { merge(it) }
        }

        val removed = withContext(Dispatchers.IO) {
            store.saveManifest(manifestText)
            store.removeVideosExcept(newManifest.videos)
        }
        withContext(Dispatchers.Main) {
            manifest = newManifest
            rebuildLibraries()
            // Deleted videos (and ones the Mac marked watched) leave the queue now, not after the downloads.
            onLibraryChanged?.invoke()
        }

        val requested = requestedVideoIDs
        withContext(Dispatchers.IO) {
            // Only new ones hold the sync up; the rest get a fresh copy about once a day, behind it.
            val staleAvatars = mutableListOf<String>()
            for (creator in newManifest.creators.filter { it.hasAvatar }) {
                val dest = store.avatarFile(creator.username)
                if (!dest.exists()) {
                    runCatching { client.download("/avatar/${creator.username}", java.io.File("${dest.path}.part"), dest) {} }
                } else if (System.currentTimeMillis() - dest.lastModified() > 24 * 60 * 60 * 1000L) {
                    staleAvatars.add(creator.username)
                }
            }
            refreshAvatars(staleAvatars, client)
            syncLap("avatars")
            // Long videos' thumbnails, for their galleries and lists. Small, and kept once fetched.
            for (video in newManifest.videos.filter { (forms.includesLong || it.id in requested) && it.hasPoster && !store.posterFile(it).exists() }) {
                val dest = store.posterFile(video)
                runCatching { client.download("/poster/${video.id}", java.io.File("${dest.path}.part"), dest) {} }
            }
        }

        // Only the kinds asked for this time, and videos asked for from the Mac; a video in a playlist and a creator's is sent once.
        val missing = newManifest.videos.filter { (forms.includes(it.form) || it.id in requested) && !store.isDownloaded(it) }
            .distinctBy { it.id }.sortedByDescending { it.date }
        val totalBytes = missing.sumOf { maxOf(1L, it.size - store.partialFile(it).length()) }.coerceAtLeast(1)
        val doneBytes = AtomicLong(0)
        val addedCount = AtomicInteger(0)
        val failedCount = AtomicInteger(0)
        val nextVideo = AtomicInteger(0)
        // The first 401 fails the others too: the Mac has forgotten this phone.
        coroutineScope {
            repeat(PARALLEL_DOWNLOADS) {
                launch(Dispatchers.IO) {
                    while (true) {
                        ensureActive()
                        val i = nextVideo.getAndIncrement()
                        val video = missing.getOrNull(i) ?: break
                        step("Downloading ${i + 1} of ${missing.size}…", doneBytes.get().toFloat() / totalBytes)
                        val ok = runCatching {
                            var lastReport = 0L
                            client.download("/video/${video.id}", store.partialFile(video), store.videoFile(video)) { n ->
                                val done = doneBytes.addAndGet(n)
                                if (kotlin.math.abs(done - lastReport) > 512 * 1024) {
                                    lastReport = done
                                    // Snapshot state can be written from any thread.
                                    syncProgress = (done.toFloat() / totalBytes).coerceIn(0f, 1f)
                                }
                            }
                        }
                        if (ok.isSuccess) {
                            addedCount.incrementAndGet()
                            withContext(Dispatchers.Main) { rebuildLibraries() }
                        } else {
                            failedCount.incrementAndGet()
                            (ok.exceptionOrNull() as? SyncException)?.takeIf { it.status == 401 }?.let { throw it }
                        }
                    }
                }
            }
        }
        val added = addedCount.get()
        val failed = failedCount.get()

        syncLap("the rest (${added} added)")
        android.util.Log.i("Curated", "Sync timing: total ${System.currentTimeMillis() - syncStarted} ms")
        withContext(Dispatchers.Main) {
            if (added > 0) onLibraryChanged?.invoke()
            lastSyncAt = Instant.now()
            store.prefs.edit { putLong(KEY_LAST_SYNC, System.currentTimeMillis()) }
            if (!afterMacDownload) markMacDownloadFinished(false)
            // What the Mac finished is all here. One it couldn't download isn't waited for, since it isn't coming.
            if (afterMacDownload && failed == 0) setRequestedVideos(requestedVideoIDs - requested)
        }
        val kind = if (requested.isNotEmpty()) "" else when (forms) { SyncForms.Short -> "short "; SyncForms.Long -> "long "; SyncForms.All -> "" }
        return buildList {
            add(if (added == 0) "Up to date" else "$added new ${kind}video${if (added == 1) "" else "s"}")
            if (removed > 0) add("$removed removed")
            if (failed > 0) add("$failed couldn't download")
        }.joinToString(" · ")
    }

    private fun refreshAvatars(usernames: List<String>, client: SyncClient) {
        if (usernames.isEmpty() || refreshingAvatars) return
        refreshingAvatars = true
        scope.launch(Dispatchers.IO) {
            try {
                for (username in usernames) {
                    if (pairing == null) break
                    val dest = store.avatarFile(username)
                    runCatching { client.download("/avatar/$username", java.io.File("${dest.path}.part"), dest) {} }
                }
            } finally {
                refreshingAvatars = false
            }
        }
    }

    /** Where a sync's time goes, in logcat under "Curated". */
    private fun syncLap(step: String) {
        val now = System.currentTimeMillis()
        android.util.Log.i("Curated", "Sync timing: $step ${now - syncLapStarted} ms")
        syncLapStarted = now
    }

    /**
     * Tries USB (adb reverse). Then with `lookUp` (full syncs), finds the Mac by Bonjour and uses its best address,
     * wired first. Otherwise, or if that finds nothing (some networks block Bonjour), tries where the Mac was last
     * seen, then looks for any Mac.
     */
    private suspend fun connect(saved: Pairing, lookUp: Boolean = false): SyncClient? = withContext(Dispatchers.IO) {
        fun reachable(host: String, port: Int) = runCatching { SyncClient(host, port).info(1500) }.isSuccess
        val usb = "127.0.0.1" to SyncClient.DEFAULT_PORT
        var target = usb.takeIf { (host, port) -> reachable(host, port) }
        if (target == null && lookUp) {
            // The same port too, so a test copy of the Mac app with the same name is never mistaken for it.
            val mac = Discovery.find(context, 1500, saved.macName).firstOrNull { it.port == saved.port }
            if (mac != null) {
                val addresses = runCatching { SyncClient(mac.host, mac.port).info().optString("addresses") }.getOrDefault("")
                    .split(',').filter { it.isNotEmpty() }
                target = (addresses + mac.host).firstOrNull { reachable(it, mac.port) }?.let { it to mac.port }
            }
        }
        if (target == null) target = (saved.host to saved.port).takeIf { (host, port) -> reachable(host, port) }
        if (target == null) {
            step("Looking for your Mac on this network…")
            val found = Discovery.find(context).sortedByDescending { it.name == saved.macName }
            target = found.map { it.host to it.port }.firstOrNull { (host, port) -> reachable(host, port) }
        }
        val (host, port) = target ?: return@withContext null
        if (host != "127.0.0.1" && (host != saved.host || port != saved.port)) {
            val moved = saved.copy(host = host, port = port)
            store.savePairing(moved)
            withContext(Dispatchers.Main) { pairing = moved }
        }
        SyncClient(host, port, saved.token)
    }

    fun setCollapsed(card: String, collapsed: Boolean) {
        collapsedCards = if (collapsed) collapsedCards + card else collapsedCards - card
        store.prefs.edit { putStringSet(KEY_COLLAPSED, collapsedCards) }
    }

    fun updateAppearance(value: Appearance) {
        appearance = value
        store.prefs.edit { putString(KEY_APPEARANCE, value.name) }
    }

    fun updateBackgroundStyle(value: BackgroundStyle) {
        backgroundStyle = value
        store.prefs.edit { putString(KEY_BACKGROUND, value.name) }
    }

    /** Picks a palette for the current style (Aurora and Holiday each keep their own). */
    fun updatePalette(id: String) {
        when (backgroundStyle) {
            BackgroundStyle.Aurora -> { auroraPalette = id; store.prefs.edit { putString(KEY_AURORA_PALETTE, id) } }
            BackgroundStyle.Holiday -> { holidayPalette = id; store.prefs.edit { putString(KEY_HOLIDAY_PALETTE, id) } }
        }
    }

    fun updateHolidayWordmarks(enabled: Boolean) {
        holidayWordmarks = enabled
        store.prefs.edit { putBoolean(KEY_HOLIDAY_WORDMARKS, enabled) }
    }

    fun updateAutoSync(enabled: Boolean) {
        autoSync = enabled
        store.prefs.edit { putBoolean(KEY_AUTO_SYNC, enabled) }
        val work = WorkManager.getInstance(context)
        if (enabled) {
            val request = PeriodicWorkRequestBuilder<SyncWorker>(1, TimeUnit.HOURS)
                .setConstraints(
                    Constraints.Builder()
                        .setRequiredNetworkType(NetworkType.UNMETERED)
                        .setRequiresCharging(true)
                        .build(),
                )
                .build()
            work.enqueueUniquePeriodicWork(SyncWorker.NAME, ExistingPeriodicWorkPolicy.UPDATE, request)
        } else {
            work.cancelUniqueWork(SyncWorker.NAME)
        }
    }

    private fun Throwable.friendlyMessage(): String = when {
        this is SyncException && status == 401 -> "Your Mac doesn't recognize this phone anymore. Unpair and pair again."
        this is SyncException -> message ?: "Sync failed"
        this is java.net.ConnectException || this is java.net.SocketTimeoutException ->
            "Couldn't connect. Check that phone sync is on in Curated on your Mac."
        else -> message ?: "Sync failed"
    }

    private companion object {
        /**
         * How many videos download at once. Each new connection starts slowly, so small videos gain from several: on
         * real Wi-Fi, 12 MB videos went at 204 Mbps one at a time, 274 three at a time and 315 six at a time.
         */
        const val PARALLEL_DOWNLOADS = 6
        const val KEY_LAST_MESSAGE = "lastSyncMessage"
        const val KEY_LAST_SYNC = "lastSyncAt"
        const val KEY_MAC_FINISHED = "macDownloadFinished"
        const val KEY_MAC_BASELINE = "macDownloadBaseline"
        const val KEY_REQUESTED = "requestedVideoIDs"
        const val KEY_AUTO_SYNC = "autoSync"
        const val KEY_COLLAPSED = "collapsedCards"
        const val KEY_APPEARANCE = "appearance"
        const val KEY_BACKGROUND = "background"
        const val KEY_AURORA_PALETTE = "auroraPalette"
        const val KEY_HOLIDAY_PALETTE = "holidayPalette"
        const val KEY_HOLIDAY_WORDMARKS = "holidayWordmarks"
        const val KEY_SYNC_FORMS = "syncForms"
        const val KEY_AUTOPLAY_LONG = "autoplayLong"
        const val KEY_AUTOPLAY_SHORT = "autoplayShort"
    }
}

/** Light, dark, or whatever the phone is set to. The player stays dark either way. */
enum class Appearance(val label: String) { System("System"), Light("Light"), Dark("Dark") }
