package local.curated.phone

import android.content.Context
import android.net.Uri
import android.os.PowerManager
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.VideoSize
import androidx.media3.exoplayer.ExoPlayer
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** One player for the whole app, like the Mac's Playback. Main thread only. */
class Playback(private val context: Context, private val app: AppState) {
    val player: ExoPlayer = ExoPlayer.Builder(context)
        // Pause for calls and other apps' audio, and when headphones are unplugged.
        .setAudioAttributes(AudioAttributes.Builder().setUsage(C.USAGE_MEDIA).setContentType(C.AUDIO_CONTENT_TYPE_MOVIE).build(), true)
        .setHandleAudioBecomingNoisy(true)
        // Keeps the CPU awake to play on with the screen locked.
        .setWakeMode(C.WAKE_MODE_LOCAL)
        .build()

    var queue by mutableStateOf(emptyList<Video>()); private set
    var index by mutableStateOf<Int?>(null); private set
    var mode by mutableStateOf<PlaybackMode?>(null); private set
    var finished by mutableStateOf(false); private set
    var isPlaying by mutableStateOf(false); private set
    /** True unless paused, so it stays set while buffering and between videos. */
    var playWhenReady by mutableStateOf(false); private set
    /** Set when the queue was cut to a time budget (Automix "Time Limit"). */
    var timeLimitMinutes by mutableStateOf<Int?>(null); private set
    /** Position in the current video, updated a few times a second. */
    var positionSeconds by mutableDoubleStateOf(0.0); private set
    /** The chosen speed; stays the same from video to video. */
    var speed by mutableFloatStateOf(1f); private set
    /** The current video's category always plays at 1x (see `PlaybackRules`), so the chosen speed waits for the next one. */
    var speedLocked by mutableStateOf(false); private set
    /** The speed the current video plays at, apart from a held 2x. */
    val shownSpeed: Float get() = if (speedLocked) 1f else speed
    /** True while the video is held down for a temporary 2x. */
    var isHoldingFast by mutableStateOf(false); private set
    /** Width over height of the current video, for the picture-in-picture window. */
    var videoAspect by mutableFloatStateOf(9f / 16f); private set
    /** The video whose first frame is on screen, so a swipe's still can make way for it. */
    var renderedVideoId by mutableStateOf<String?>(null); private set
    /** A long video fills the window (see enterFullscreen); CuratedRoot shows it over whatever layout is underneath. */
    var fullscreen by mutableStateOf(false)
    /** Whether the phone was upright when full screen started, so leaving it turns it back. */
    var fullscreenFromPortrait = false
    /** Clear mode: the player hides everything over the video until it's tapped (see PlayerScreen). Kept until turned off. */
    var clearMode by mutableStateOf(false)
    /** The player's queue sheet is up. Here so the sideways side panel's Queue button can open it too. */
    var queueShown by mutableStateOf(false)
    /** A long video ended with autoplay off, and there's another to play: the player waits on the Up Next card. */
    var awaitingNext by mutableStateOf(false); private set
    /** Android Auto is connected: only the sound plays, with the phone anywhere, and it doesn't stop to wait for a tap. */
    var inCar by mutableStateOf(false); private set
    /** The app's window is on the phone's screen. */
    var onScreen = false
    private var lastSavedPosition = 0.0

    companion object {
        val SPEEDS = listOf(1f, 1.5f, 2f)
    }

    val current: Video? get() = index?.let { queue.getOrNull(it) }
    val hasPrevious: Boolean get() = (index ?: 0) > 0

    init {
        player.addListener(object : Player.Listener {
            override fun onPlaybackStateChanged(state: Int) {
                if (state == Player.STATE_ENDED) videoEnded()
            }

            override fun onIsPlayingChanged(playing: Boolean) {
                isPlaying = playing
                if (playing) {
                    // However it started: the app, the notification or a headset.
                    current?.takeIf { it.form == VideoForm.LONG }?.let { app.setNowPlaying(it) }
                } else {
                    savePosition()
                }
                app.sendPositionsSoon()
            }

            override fun onPlayWhenReadyChanged(ready: Boolean, reason: Int) {
                playWhenReady = ready
            }

            /** A missing or unreadable file shouldn't stall the queue. */
            override fun onPlayerError(error: PlaybackException) {
                advance(markingPlayed = false)
            }

            override fun onRenderedFirstFrame() {
                renderedVideoId = current?.id
            }

            override fun onVideoSizeChanged(size: VideoSize) {
                if (size.width > 0 && size.height > 0) {
                    videoAspect = size.width * size.pixelWidthHeightRatio / size.height
                }
            }
        })
        app.onLibraryChanged = {
            refreshAfterSync()
            loadSyncedVideo()
        }
        app.onPositionsMerged = ::positionsMerged
        app.onNowPlayingMerged = { loadSyncedVideo() }
        app.onPlaybackRulesChanged = ::applySpeed
        val power = context.getSystemService(PowerManager::class.java)
        MainScope().launch {
            snapshotFlow { app.form }.collect { if (it == VideoForm.LONG) loadSyncedVideo(switching = true) }
        }
        MainScope().launch {
            var lastLockedSend = 0L
            while (true) {
                positionSeconds = player.currentPosition / 1000.0
                if (kotlin.math.abs(positionSeconds - lastSavedPosition) >= 5) savePosition()
                // Playing on with the screen locked, there's no pause to send it on.
                val now = System.currentTimeMillis()
                if (player.isPlaying && !power.isInteractive && now - lastLockedSend >= 60_000) {
                    lastLockedSend = now
                    app.sendPositionsSoon()
                }
                delay(250)
            }
        }
    }

    fun start(queue: List<Video>, at: Int = 0, mode: PlaybackMode, timeLimitMinutes: Int? = null) {
        // Save the old video's place while `index` still points into the old queue.
        savePosition()
        // Opening the video that's already loaded (e.g. back into it from its gallery) carries on where it is.
        val current = current
        if (current != null && !finished && queue.getOrNull(at)?.id == current.id) {
            this.queue = queue
            this.mode = mode
            this.timeLimitMinutes = timeLimitMinutes
            index = at
            applySpeed()
            if (!awaitingNext) player.play()
            return
        }
        index = null
        this.queue = queue
        this.mode = mode
        this.timeLimitMinutes = timeLimitMinutes
        if (at !in queue.indices) {
            stop()
            return
        }
        play(at)
    }

    /**
     * Loads the long video last playing on any device, paused where it was left, while long videos are showing. Never
     * replaces a long video that's playing; a short one that's playing only when `switching` to long videos.
     */
    private fun loadSyncedVideo(switching: Boolean = false) {
        if (!switching && app.form != VideoForm.LONG) return
        val id = app.nowPlayingMark.id ?: return
        if (current?.id == id) return
        val library = app.longLibraries.firstOrNull { library -> library.videos.any { it.id == id } } ?: return
        val at = library.videos.indexOfFirst { it.id == id }
        if (app.played.contains(id)) return
        val current = current
        if (current != null && player.playWhenReady && !finished && (current.form == VideoForm.LONG || !switching)) return
        savePosition()
        index = null
        queue = library.videos
        mode = PlaybackMode.Creator(library.id, VideoForm.LONG)
        timeLimitMinutes = null
        play(at, autoplay = false)
    }

    /** Swaps in a new queue, keeping the current video playing at the top of it. */
    fun continueWith(queue: List<Video>, mode: PlaybackMode) {
        val current = current
        if (current == null || finished) {
            start(queue, mode = mode)
            return
        }
        this.queue = listOf(current) + queue.filter { it.id != current.id }
        this.mode = mode
        timeLimitMinutes = null
        index = 0
    }

    fun play(i: Int, autoplay: Boolean = true) {
        val video = queue.getOrNull(i) ?: return
        savePosition()
        if (autoplay && video.form == VideoForm.LONG) app.setNowPlaying(video)
        app.sendPositionsSoon()
        index = i
        finished = false
        awaitingNext = false
        // A long video picks up where it was left off.
        val saved = if (video.form == VideoForm.LONG) app.resumePosition(video) else null
        val resume = saved?.let { maxOf(0.0, it - app.playbackRules.resumeRewindSeconds) } ?: 0.0
        positionSeconds = resume
        lastSavedPosition = resume
        renderedVideoId = null
        // The title and creator show in the media notification and on the lock screen.
        val metadata = MediaMetadata.Builder()
            .setTitle(if (video.form == VideoForm.LONG) video.displayTitle else video.caption.ifEmpty { "No caption" })
            .setArtist(app.library(video.creator, video.form)?.creator?.displayName ?: "@${video.creator.removePrefix(YOUTUBE_KEY_PREFIX)}")
            .setArtworkUri(CarArtwork.video(context, video.id))
            .build()
        player.setMediaItem(
            MediaItem.Builder().setUri(Uri.fromFile(app.store.videoFile(video))).setMediaMetadata(metadata).build(),
            (resume * 1000).toLong(),
        )
        player.prepare()
        applySpeed()
        player.playWhenReady = autoplay
    }

    /**
     * Remembers how far into the current long video playback is, watched before or not (a rewatch resumes too). One
     * is forgotten once the video is nearly over, so a finished video starts from the top next time.
     */
    fun savePosition() {
        val video = current?.takeIf { it.form == VideoForm.LONG && !finished } ?: return
        val time = player.currentPosition / 1000.0
        // Sitting still isn't news: re-saving an old place with a new date would beat the Mac's newer one.
        if (kotlin.math.abs(time - lastSavedPosition) < 1) return
        lastSavedPosition = time
        when {
            nearlyOver(video) -> app.setResumePosition(video, null)
            time > 2 -> app.setResumePosition(video, time)
        }
    }

    /**
     * Another device moved on in a video that's loaded here: a paused player follows it. One that's playing carries on,
     * and its next save wins.
     */
    private fun positionsMerged(ids: Set<String>) {
        val video = current?.takeIf { it.form == VideoForm.LONG && it.id in ids && !finished } ?: return
        if (player.playWhenReady) return
        val seconds = app.resumePosition(video)
        if (seconds != null) seek(seconds)
        lastSavedPosition = seconds ?: (player.currentPosition / 1000.0)
    }

    /**
     * A video played to the end. A short one with autoplay off is marked watched and plays again; a long one with
     * autoplay off is marked watched and waits; otherwise on to the next.
     */
    private fun videoEnded() {
        val index = index ?: return
        val video = queue.getOrNull(index) ?: return
        if (video.form == VideoForm.SHORT && !app.autoplayShort && !inCar) {
            app.setPlayed(video, true)
            player.seekTo(0)
            player.play()
            return
        }
        if (video.form != VideoForm.LONG || app.autoplayLong || inCar) return advance(markingPlayed = true)
        app.setPlayed(video, true)
        if (nextIndex(after = index) != null) awaitingNext = true else finished = true
    }

    /** From the Up Next card. */
    fun playNext() {
        val next = index?.let(::nextIndex) ?: return
        play(next)
    }

    /** From the Up Next card: the video that just ended, from the start. */
    fun replay() {
        awaitingNext = false
        player.seekTo(0)
        player.play()
    }

    /** Skips forward (or back, for a negative amount) within the current video. */
    fun seekBy(seconds: Double) {
        if (current == null || finished) return
        val length = player.duration.takeIf { it != C.TIME_UNSET }?.div(1000.0) ?: current?.duration ?: Double.MAX_VALUE
        seek((player.currentPosition / 1000.0 + seconds).coerceIn(0.0, maxOf(0.0, length - 0.5)))
    }

    fun seek(seconds: Double) {
        player.seekTo((seconds * 1000).toLong())
        positionSeconds = seconds
    }

    /**
     * After a sync, rebuilds the loaded queue from what's on the phone now: deleted and newly watched videos drop out,
     * new ones come in, and mixes are reshuffled. The current video keeps playing if it's still here; nothing starts
     * playing that was paused (a sync can run in the background), and a finished mix stays finished.
     */
    private fun refreshAfterSync() {
        val mode = mode ?: return
        if (finished) return // The end card stays up.
        val wasPlaying = player.playWhenReady
        val current = current?.takeIf { video -> app.allVideos.any { it.id == video.id } }
        var fresh = Queues.build(mode, app)
        if (mode is PlaybackMode.Creator) {
            // A creator's list keeps its order; just find our place in it again.
            queue = fresh
            val at = current?.let { video -> fresh.indexOfFirst { it.id == video.id } }?.takeIf { it >= 0 }
            if (at != null) index = at else if (fresh.isEmpty()) stop() else play(fresh.indices.firstOrNull { !app.isPlayed(fresh[it]) } ?: 0, wasPlaying)
            return
        }
        fresh = fresh.filter { it.id != current?.id }
        // A time-limited mix keeps its remaining budget.
        timeLimitMinutes?.let { fresh = Queues.limitToDuration(fresh, maxOf(0.0, secondsUntilEnd - currentRemaining)) }
        if (current != null) {
            queue = listOf(current) + fresh
            index = 0
        } else {
            queue = fresh
            if (fresh.isEmpty()) {
                player.stop()
                player.clearMediaItems()
                index = null
                finished = false
            } else {
                play(0, autoplay = wasPlaying)
            }
        }
    }

    /**
     * Advances to the next unplayed video. A creator's list wraps around; mixes only move forward.
     * Skipping a short video counts as watching it. Skipping a long one keeps its place and leaves it unwatched, so it
     * resumes there, unless it was nearly over.
     */
    fun next() {
        val video = current
        if (video?.form == VideoForm.LONG && !finished && !nearlyOver(video)) {
            savePosition()
            advance(markingPlayed = false)
        } else {
            advance(markingPlayed = true)
        }
    }

    /** In a long video's last 20 seconds, where its place is no longer kept. */
    private fun nearlyOver(video: Video): Boolean {
        val length = video.duration ?: player.duration.takeIf { it != C.TIME_UNSET }?.div(1000.0) ?: return false
        return length > 0 && player.currentPosition / 1000.0 > length - 20
    }

    /** Saves the current video to Watch Later and moves on without marking it watched. */
    fun saveForLater() {
        val video = current ?: return
        if (finished) return
        app.setWatchLater(listOf(video), true)
        advance(markingPlayed = false)
    }

    /** Where `next()` goes from `after`: the next unplayed video, wrapping around in a creator's list. */
    private fun nextIndex(after: Int): Int? {
        var candidates = ((after + 1) until queue.size).toList()
        if (mode is PlaybackMode.Creator) candidates = candidates + (0 until after)
        // Bookmarks are for rewatching, so they play straight through, watched or not.
        if (mode is PlaybackMode.Bookmarks) return candidates.firstOrNull()
        return candidates.firstOrNull { !app.isPlayed(queue[it]) }
    }

    /** The video a swipe up brings in. Null at the end of a mix. */
    val upNext: Video? get() = index?.takeIf { !finished }?.let(::nextIndex)?.let { queue[it] }

    /** The video a swipe down brings back. */
    val previousVideo: Video? get() = index?.takeIf { it > 0 }?.let { queue.getOrNull(it - 1) }

    fun toggleBookmark() {
        val video = current ?: return
        app.setBookmarked(video, !app.isBookmarked(video))
    }

    private fun advance(markingPlayed: Boolean) {
        val index = index ?: return
        if (markingPlayed) queue.getOrNull(index)?.let { app.setPlayed(it, true) }
        val nextIndex = nextIndex(after = index)
        if (nextIndex != null) {
            play(nextIndex)
        } else {
            player.pause()
            finished = true
            awaitingNext = false
        }
    }

    fun previous() {
        val index = index ?: return
        if (index > 0) play(index - 1)
    }

    /** Back to the start of the current video. */
    fun restart() {
        if (current == null || finished) return
        player.seekTo(0)
        player.play()
    }

    fun togglePlayPause() {
        if (player.isPlaying) player.pause() else resume()
    }

    fun resume() = player.play()

    fun pause() = player.pause()

    /** 1x → 1.5x → 2x → 1x. */
    fun cycleSpeed() {
        speed = SPEEDS[(SPEEDS.indexOf(speed) + 1) % SPEEDS.size]
        applySpeed()
    }

    fun holdFast(holding: Boolean) {
        if (holding == isHoldingFast) return
        isHoldingFast = holding
        applySpeed()
    }

    private fun applySpeed() {
        speedLocked = current?.let { app.playsAtNormalSpeed(it, mode) } ?: false
        player.setPlaybackSpeed(if (isHoldingFast) 2f else shownSpeed)
    }

    /** The car came or went. Leaving the car stops the sound, unless the phone is in use. */
    fun carConnectionChanged(connected: Boolean) {
        if (inCar && !connected && !onScreen) pause()
        inCar = connected
    }

    fun stop() {
        savePosition()
        current?.takeIf { it.form == VideoForm.LONG }?.let { app.clearNowPlaying(it) }
        app.sendPositionsSoon()
        awaitingNext = false
        player.stop()
        player.clearMediaItems()
        index = null
        queue = emptyList()
        mode = null
        applySpeed()
        timeLimitMinutes = null
        finished = false
    }

    // MARK: Time left

    private fun lengthOf(video: Video): Double = video.duration ?: 0.0

    private val currentRemaining: Double
        get() {
            val video = current ?: return 0.0
            if (finished) return 0.0
            val length = video.duration ?: player.duration.takeIf { it != C.TIME_UNSET }?.div(1000.0) ?: 0.0
            return maxOf(0.0, length - positionSeconds)
        }

    /** Queued videos that haven't been started yet. */
    val unwatched: List<Video> get() = queue.filter { it.id != current?.id && !app.isPlayed(it) }

    /** The rest of the current video plus every unwatched video in the queue. */
    val unwatchedSecondsLeft: Double get() = currentRemaining + unwatched.sumOf(::lengthOf)

    /** How long until the queue runs out on its own: the rest of this video plus the unplayed ones after it. */
    val secondsUntilEnd: Double
        get() {
            val index = index ?: return 0.0
            val upcoming = queue.drop(index + 1).filter { !app.isPlayed(it) }
            return currentRemaining + upcoming.sumOf(::lengthOf)
        }
}
