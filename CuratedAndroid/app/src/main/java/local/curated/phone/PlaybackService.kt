package local.curated.phone

import android.app.PendingIntent
import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.KeyEvent
import androidx.compose.runtime.snapshotFlow
import androidx.media3.common.C
import androidx.media3.common.ForwardingPlayer
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.Player
import androidx.media3.session.CommandButton
import androidx.media3.session.LibraryResult
import androidx.media3.session.MediaLibraryService
import androidx.media3.session.MediaLibraryService.LibraryParams
import androidx.media3.session.MediaLibraryService.MediaLibrarySession
import androidx.media3.session.MediaSession
import androidx.media3.session.SessionCommand
import androidx.media3.session.SessionError
import androidx.media3.session.SessionResult
import com.google.common.collect.ImmutableList
import com.google.common.util.concurrent.Futures
import com.google.common.util.concurrent.ListenableFuture
import kotlinx.coroutines.FlowPreview
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.debounce
import kotlinx.coroutines.launch

/**
 * Keeps playing with the screen locked (a foreground service with a media notification), takes headphone buttons (one
 * click plays or pauses, two skip to the next video, three go back to the previous one), and is what Android Auto
 * browses and plays from (`CarLibrary`).
 */
class PlaybackService : MediaLibraryService() {
    private var session: MediaLibrarySession? = null
    private val scope = MainScope()
    /** The folders Android Auto has opened, to tell when they change. */
    private val openedFolders = mutableSetOf<String>()

    @OptIn(FlowPreview::class)
    override fun onCreate() {
        super.onCreate()
        val playback = curated.playback
        val app = curated.state
        val library = CarLibrary(this, app, playback)
        val openApp = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val session = MediaLibrarySession.Builder(this, QueuePlayer(playback, library), SessionCallback(playback, library, openedFolders))
            .setSessionActivity(openApp)
            .build()
        this.session = session
        // The car's lists follow syncs, watched marks and what's playing.
        scope.launch {
            snapshotFlow {
                listOf(app.libraries, app.longLibraries, app.vineLibraries, app.played, app.watchLaterMarks, app.bookmarkMarks, app.pairing, playback.current?.id, playback.queue, playback.finished)
            }.debounce(300).collect {
                for (folder in openedFolders) session.notifyChildrenChanged(folder, Int.MAX_VALUE, null)
            }
        }
        // Buttons beside the transport controls, in the car only, so the phone's notification stays as it was.
        scope.launch {
            snapshotFlow {
                if (!playback.inCar || playback.current == null) emptyList()
                else carButtons(playback.shownSpeed, playback.speedLocked, playback.current?.let(app::isBookmarked) == true)
            }.collect { session.setMediaButtonPreferences(ImmutableList.copyOf(it)) }
        }
        // There's nothing to tap at the end of a queue in the car, so the end card's words go where the video's were.
        scope.launch {
            snapshotFlow { playback.inCar && playback.finished }.collect { ended ->
                if (!ended || playback.player.mediaItemCount == 0) return@collect
                val current = playback.player.getMediaItemAt(0)
                val minutes = playback.timeLimitMinutes
                val headline = when {
                    minutes != null -> "Your $minutes minutes are up"
                    playback.endsInSunshine -> "You've reached the end"
                    else -> "You're all caught up"
                }
                playback.player.replaceMediaItem(
                    0,
                    current.buildUpon().setMediaMetadata(
                        MediaMetadata.Builder().setTitle(headline).setArtist("Time to enjoy some sunshine")
                            .setArtworkUri(CarArtwork.tile(this@PlaybackService, Tile.Sunshine)).build(),
                    ).build(),
                )
            }
        }
    }

    override fun onGetSession(controllerInfo: MediaSession.ControllerInfo): MediaLibrarySession? = session

    /** Swiping the app away stops it, as leaving it does. Not in the car, where it's not the phone that's in use. */
    override fun onTaskRemoved(rootIntent: Intent?) {
        if (!curated.playback.inCar) pauseAllPlayersAndStopSelf()
    }

    override fun onDestroy() {
        scope.cancel()
        // The player belongs to Playback and outlives the session.
        session?.release()
        session = null
        super.onDestroy()
    }
}

private const val COMMAND_SPEED = "local.curated.phone.SPEED"
private const val COMMAND_BACK = "local.curated.phone.BACK"
private const val COMMAND_BOOKMARK = "local.curated.phone.BOOKMARK"
private const val COMMAND_LATER = "local.curated.phone.LATER"
private const val BACK_SECONDS = 15.0

private fun carButtons(speed: Float, speedLocked: Boolean, bookmarked: Boolean): List<CommandButton> = listOf(
    carButton(COMMAND_SPEED, "Speed", when (speed) { 1.5f -> R.drawable.ic_car_speed_15; 2f -> R.drawable.ic_car_speed_2; else -> R.drawable.ic_car_speed_1 }, !speedLocked),
    carButton(COMMAND_BACK, "Back 15 seconds", R.drawable.ic_car_back_15),
    carButton(COMMAND_BOOKMARK, if (bookmarked) "Remove bookmark" else "Bookmark", if (bookmarked) R.drawable.ic_car_bookmark else R.drawable.ic_car_bookmark_outline),
    carButton(COMMAND_LATER, "Watch Later", R.drawable.ic_car_clock),
)

private fun carButton(command: String, name: String, icon: Int, enabled: Boolean = true): CommandButton =
    CommandButton.Builder(CommandButton.ICON_UNDEFINED)
        .setCustomIconResId(icon)
        .setDisplayName(name)
        .setSessionCommand(SessionCommand(command, Bundle.EMPTY))
        .setEnabled(enabled)
        .build()

/**
 * The player holds one video at a time while Playback owns the queue, so next and previous (headphone, notification,
 * lock screen and car buttons) go through Playback, and so does the car choosing something to play.
 */
private class QueuePlayer(private val playback: Playback, private val library: CarLibrary) : ForwardingPlayer(playback.player) {
    // No timeline: this player only ever holds one video, so Android Auto's Queue button would list just that. The car's
    // Up Next, in Mixes, shows Playback's real queue.
    override fun getAvailableCommands(): Player.Commands =
        super.getAvailableCommands().buildUpon().addAll(*QUEUE_COMMANDS).remove(Player.COMMAND_GET_TIMELINE).build()

    override fun isCommandAvailable(command: Int): Boolean =
        command != Player.COMMAND_GET_TIMELINE && (command in QUEUE_COMMANDS || super.isCommandAvailable(command))

    override fun seekToNext() = playback.next()
    override fun seekToNextMediaItem() = playback.next()
    override fun seekToPrevious() = playback.previous()
    override fun seekToPreviousMediaItem() = playback.previous()

    override fun setMediaItem(mediaItem: MediaItem) = playFirst(listOf(mediaItem))
    override fun setMediaItem(mediaItem: MediaItem, startPositionMs: Long) = playFirst(listOf(mediaItem))
    override fun setMediaItem(mediaItem: MediaItem, resetPosition: Boolean) = playFirst(listOf(mediaItem))
    override fun setMediaItems(mediaItems: MutableList<MediaItem>) = playFirst(mediaItems)
    override fun setMediaItems(mediaItems: MutableList<MediaItem>, resetPosition: Boolean) = playFirst(mediaItems)
    override fun setMediaItems(mediaItems: MutableList<MediaItem>, startIndex: Int, startPositionMs: Long) = playFirst(mediaItems)

    private fun playFirst(items: List<MediaItem>) {
        val item = items.firstOrNull() ?: return
        // "Play ... on Curated" comes as a search rather than a choice.
        val spoken = item.requestMetadata.searchQuery
        if (item.mediaId.isEmpty() && spoken != null) library.playSearch(spoken) else library.play(item.mediaId)
    }

    private companion object {
        val QUEUE_COMMANDS = intArrayOf(
            Player.COMMAND_SEEK_TO_NEXT, Player.COMMAND_SEEK_TO_NEXT_MEDIA_ITEM,
            Player.COMMAND_SEEK_TO_PREVIOUS, Player.COMMAND_SEEK_TO_PREVIOUS_MEDIA_ITEM,
        )
    }
}

/** Android Auto's browsing and buttons, on top of the headset's. Called on the main thread. */
private class SessionCallback(
    private val playback: Playback,
    private val library: CarLibrary,
    private val openedFolders: MutableSet<String>,
) : MediaLibrarySession.Callback {
    private val headset = HeadsetClicks(playback)

    override fun onMediaButtonEvent(session: MediaSession, controllerInfo: MediaSession.ControllerInfo, intent: Intent): Boolean =
        headset.onMediaButtonEvent(session, controllerInfo, intent)

    override fun onConnect(session: MediaSession, controller: MediaSession.ControllerInfo): MediaSession.ConnectionResult {
        val commands = MediaSession.ConnectionResult.DEFAULT_SESSION_AND_LIBRARY_COMMANDS.buildUpon()
        for (command in listOf(COMMAND_SPEED, COMMAND_BACK, COMMAND_BOOKMARK, COMMAND_LATER)) commands.add(SessionCommand(command, Bundle.EMPTY))
        return MediaSession.ConnectionResult.AcceptedResultBuilder(session).setAvailableSessionCommands(commands.build()).build()
    }

    override fun onCustomCommand(session: MediaSession, controller: MediaSession.ControllerInfo, customCommand: SessionCommand, args: Bundle): ListenableFuture<SessionResult> {
        when (customCommand.customAction) {
            COMMAND_SPEED -> playback.cycleSpeed()
            COMMAND_BACK -> playback.seekBy(-BACK_SECONDS)
            COMMAND_BOOKMARK -> playback.toggleBookmark()
            COMMAND_LATER -> playback.saveForLater()
            else -> return Futures.immediateFuture(SessionResult(SessionError.ERROR_NOT_SUPPORTED))
        }
        return Futures.immediateFuture(SessionResult(SessionResult.RESULT_SUCCESS))
    }

    override fun onGetLibraryRoot(session: MediaLibrarySession, browser: MediaSession.ControllerInfo, params: LibraryParams?): ListenableFuture<LibraryResult<MediaItem>> {
        // The system asks for "recent" media to offer resuming after a restart; a mix isn't something to resume blindly.
        if (params?.isRecent == true) return Futures.immediateFuture(LibraryResult.ofError(SessionError.ERROR_NOT_SUPPORTED))
        return Futures.immediateFuture(LibraryResult.ofItem(library.root, LibraryParams.Builder().setExtras(library.rootExtras).build()))
    }

    /** Taken as they come. By default Media3 looks the folder up first, and without a subscription changes go unheard. */
    override fun onSubscribe(session: MediaLibrarySession, browser: MediaSession.ControllerInfo, parentId: String, params: LibraryParams?): ListenableFuture<LibraryResult<Void>> {
        openedFolders += parentId
        return Futures.immediateFuture(LibraryResult.ofVoid(params))
    }

    override fun onGetChildren(session: MediaLibrarySession, browser: MediaSession.ControllerInfo, parentId: String, page: Int, pageSize: Int, params: LibraryParams?): ListenableFuture<LibraryResult<ImmutableList<MediaItem>>> {
        val items = library.children(parentId) ?: return Futures.immediateFuture(LibraryResult.ofError(SessionError.ERROR_BAD_VALUE))
        openedFolders += parentId
        val from = page.toLong() * pageSize
        val shown = if (from >= items.size) emptyList() else items.subList(from.toInt(), minOf(from + pageSize, items.size.toLong()).toInt())
        return Futures.immediateFuture(LibraryResult.ofItemList(ImmutableList.copyOf(shown), params))
    }

    override fun onSearch(session: MediaLibrarySession, browser: MediaSession.ControllerInfo, query: String, params: LibraryParams?): ListenableFuture<LibraryResult<Void>> {
        session.notifySearchResultChanged(browser, query, library.search(query).size, params)
        return Futures.immediateFuture(LibraryResult.ofVoid(params))
    }

    override fun onGetSearchResult(session: MediaLibrarySession, browser: MediaSession.ControllerInfo, query: String, page: Int, pageSize: Int, params: LibraryParams?): ListenableFuture<LibraryResult<ImmutableList<MediaItem>>> {
        val items = library.search(query)
        val from = page.toLong() * pageSize
        val shown = if (from >= items.size) emptyList() else items.subList(from.toInt(), minOf(from + pageSize, items.size.toLong()).toInt())
        return Futures.immediateFuture(LibraryResult.ofItemList(ImmutableList.copyOf(shown), params))
    }

    /** Keeps just the ids; `QueuePlayer` hands them to Playback when the session sets them. */
    override fun onSetMediaItems(mediaSession: MediaSession, controller: MediaSession.ControllerInfo, mediaItems: MutableList<MediaItem>, startIndex: Int, startPositionMs: Long): ListenableFuture<MediaSession.MediaItemsWithStartPosition> =
        Futures.immediateFuture(MediaSession.MediaItemsWithStartPosition(mediaItems, 0, C.TIME_UNSET))

    override fun onAddMediaItems(mediaSession: MediaSession, controller: MediaSession.ControllerInfo, mediaItems: MutableList<MediaItem>): ListenableFuture<MutableList<MediaItem>> =
        Futures.immediateFuture(mediaItems)
}

/** Counts presses of a headset's single button and acts once they stop coming. */
private class HeadsetClicks(private val playback: Playback) : MediaSession.Callback {
    private val handler = Handler(Looper.getMainLooper())
    private var clicks = 0
    private val act = Runnable {
        when (clicks) {
            1 -> playback.togglePlayPause()
            2 -> playback.next()
            else -> if (playback.hasPrevious) playback.previous() else playback.restart()
        }
        clicks = 0
    }

    override fun onMediaButtonEvent(session: MediaSession, controllerInfo: MediaSession.ControllerInfo, intent: Intent): Boolean {
        @Suppress("DEPRECATION")
        val event = intent.getParcelableExtra<KeyEvent>(Intent.EXTRA_KEY_EVENT) ?: return false
        if (event.keyCode != KeyEvent.KEYCODE_HEADSETHOOK && event.keyCode != KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE) return false
        if (event.action == KeyEvent.ACTION_DOWN && event.repeatCount == 0) {
            clicks += 1
            handler.removeCallbacks(act)
            if (clicks >= 3) act.run() else handler.postDelayed(act, CLICK_WINDOW_MS)
        }
        return true
    }

    private companion object {
        /** How long to wait for another click before acting. */
        const val CLICK_WINDOW_MS = 400L
    }
}
