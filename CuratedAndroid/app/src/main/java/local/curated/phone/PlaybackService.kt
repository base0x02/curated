package local.curated.phone

import android.app.PendingIntent
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.view.KeyEvent
import androidx.media3.common.ForwardingPlayer
import androidx.media3.common.Player
import androidx.media3.session.MediaSession
import androidx.media3.session.MediaSessionService

/**
 * Keeps playing with the screen locked (a foreground service with a media notification) and takes headphone buttons:
 * one click plays or pauses, two skip to the next video, three go back to the previous one.
 */
class PlaybackService : MediaSessionService() {
    private var session: MediaSession? = null

    override fun onCreate() {
        super.onCreate()
        val playback = curated.playback
        val openApp = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        session = MediaSession.Builder(this, QueuePlayer(playback))
            .setCallback(HeadsetClicks(playback))
            .setSessionActivity(openApp)
            .build()
    }

    override fun onGetSession(controllerInfo: MediaSession.ControllerInfo): MediaSession? = session

    /** Swiping the app away stops it, as leaving it does. */
    override fun onTaskRemoved(rootIntent: Intent?) {
        pauseAllPlayersAndStopSelf()
    }

    override fun onDestroy() {
        // The player belongs to Playback and outlives the session.
        session?.release()
        session = null
        super.onDestroy()
    }
}

/**
 * The player holds one video at a time while Playback owns the queue, so next and previous (headphone, notification
 * and lock screen buttons) go through Playback.
 */
private class QueuePlayer(private val playback: Playback) : ForwardingPlayer(playback.player) {
    override fun getAvailableCommands(): Player.Commands =
        super.getAvailableCommands().buildUpon().addAll(*QUEUE_COMMANDS).build()

    override fun isCommandAvailable(command: Int): Boolean = command in QUEUE_COMMANDS || super.isCommandAvailable(command)

    override fun seekToNext() = playback.next()
    override fun seekToNextMediaItem() = playback.next()
    override fun seekToPrevious() = playback.previous()
    override fun seekToPreviousMediaItem() = playback.previous()

    private companion object {
        val QUEUE_COMMANDS = intArrayOf(
            Player.COMMAND_SEEK_TO_NEXT, Player.COMMAND_SEEK_TO_NEXT_MEDIA_ITEM,
            Player.COMMAND_SEEK_TO_PREVIOUS, Player.COMMAND_SEEK_TO_PREVIOUS_MEDIA_ITEM,
        )
    }
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
