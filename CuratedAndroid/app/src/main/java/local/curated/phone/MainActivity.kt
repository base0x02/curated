package local.curated.phone

import android.app.PendingIntent
import android.app.PictureInPictureParams
import android.app.RemoteAction
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.graphics.drawable.Icon
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.util.Rational
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.animation.Crossfade
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.consumeWindowInsets
import androidx.compose.foundation.layout.displayCutout
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Text
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.key
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.repeatOnLifecycle
import androidx.window.layout.FoldingFeature
import androidx.window.layout.WindowInfoTracker
import androidx.compose.material3.MaterialTheme
import androidx.core.view.WindowCompat
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.material3.lightColorScheme
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.snapshots.SnapshotStateList
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.graphics.Color
import androidx.core.content.ContextCompat
import androidx.lifecycle.lifecycleScope
import androidx.media3.session.MediaController
import androidx.media3.session.SessionToken
import com.google.common.util.concurrent.ListenableFuture
import kotlinx.coroutines.launch

class MainActivity : ComponentActivity() {
    private var inPip by mutableStateOf(false)
    /** The hinge of a foldable such as the Galaxy Z Fold, when this window spans it. */
    private var fold by mutableStateOf<FoldingFeature?>(null)
    /** Lives here, not in a composable, so it survives swapping to the picture-in-picture layout. */
    private val stack = mutableStateListOf<Screen>(Screen.Home)
    private val playback get() = curated.playback
    private lateinit var sessionConnection: ListenableFuture<MediaController>

    /** Play/pause and skip buttons in the picture-in-picture window. */
    private val pipReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            when (intent.getStringExtra(EXTRA_CONTROL)) {
                CONTROL_TOGGLE -> playback.togglePlayPause()
                CONTROL_NEXT -> playback.next()
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        // Starts PlaybackService, which takes headphone buttons and keeps playing with the screen locked.
        sessionConnection = MediaController.Builder(this, SessionToken(this, ComponentName(this, PlaybackService::class.java))).buildAsync()
        ContextCompat.registerReceiver(this, pipReceiver, IntentFilter(ACTION_PIP_CONTROL), ContextCompat.RECEIVER_NOT_EXPORTED)
        // A fresh launch goes straight to Automix (Home stays underneath for Back) when there's something to watch.
        val state = curated.state
        // Opened while the car is playing something: that, rather than Automix loading over it.
        val inCarMode = playback.mode.takeIf { playback.inCar && playback.current != null && !playback.finished }
        if (savedInstanceState == null && stack.size == 1 && inCarMode != null) {
            stack.add(Screen.Player(inCarMode))
        } else if (savedInstanceState == null && stack.size == 1 && state.unplayedCount(null) > 0) {
            stack.add(Screen.Player(PlaybackMode.Automix(null)))
        }
        setContent {
            val dark = when (state.appearance) {
                Appearance.System -> isSystemInDarkTheme()
                Appearance.Light -> false
                Appearance.Dark -> true
            }
            // Light status and navigation bar icons over dark screens: the theme's, or the full-screen player's.
            val darkBars = dark || inPip || stack.lastOrNull() is Screen.Player
            LaunchedEffect(darkBars) {
                WindowCompat.getInsetsController(window, window.decorView).apply {
                    isAppearanceLightStatusBars = !darkBars
                    isAppearanceLightNavigationBars = !darkBars
                }
            }
            MaterialTheme(colorScheme = if (dark) DarkColors else LightColors) {
                CompositionLocalProvider(LocalDarkTheme provides dark) {
                    Crossfade(targetState = state.onboarding, animationSpec = tween(600), label = "onboarding") { onboarding ->
                        when {
                            inPip -> PipVideo()
                            onboarding -> OnboardingScreen {
                                state.onboarding = false
                                // Like a launch: straight into Automix when there's something to watch.
                                stack.removeRange(1, stack.size)
                                if (state.unplayedCount(null) > 0) stack.add(Screen.Player(PlaybackMode.Automix(null)))
                            }
                            else -> CuratedRoot(stack, fold)
                        }
                    }
                }
            }
        }
        lifecycleScope.launch {
            repeatOnLifecycle(Lifecycle.State.STARTED) {
                WindowInfoTracker.getOrCreate(this@MainActivity).windowLayoutInfo(this@MainActivity).collect { info ->
                    fold = info.displayFeatures.filterIsInstance<FoldingFeature>().firstOrNull()
                }
            }
        }
        // Keep the window's shape, buttons and auto-enter in step with what's playing.
        lifecycleScope.launch {
            snapshotFlow { Triple(playback.isPlaying, playback.current?.id, playback.videoAspect) }
                .collect { if (supportsPip) setPictureInPictureParams(pipParams()) }
        }
        // Stop the screen sleeping while a video plays, on any screen (full player, mini player or PiP).
        lifecycleScope.launch {
            snapshotFlow { playback.playWhenReady && playback.current != null && !playback.finished }
                .collect { awake ->
                    if (awake) window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    else window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                }
        }
    }

    override fun onDestroy() {
        MediaController.releaseFuture(sessionConnection)
        unregisterReceiver(pipReceiver)
        super.onDestroy()
    }

    /** Leaving the app with a video playing shrinks it into picture-in-picture (older Androids). */
    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S && playback.isPlaying) enterPip()
    }

    override fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean, newConfig: Configuration) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        inPip = isInPictureInPictureMode
    }

    /** A video may have moved on on another device. */
    override fun onStart() {
        super.onStart()
        playback.onScreen = true
        curated.state.exchangePositions()
        curated.state.resumeFollowingRequestedVideos()
    }

    /** Also runs when the picture-in-picture window is closed. Locking the screen keeps the video playing, as does being in the car. */
    override fun onStop() {
        super.onStop()
        playback.onScreen = false
        if (getSystemService(PowerManager::class.java).isInteractive && !playback.inCar) playback.pause()
        // So another device can pick up from here, even if this one is never opened again.
        playback.savePosition()
        curated.state.sendPositionsSoon()
        curated.state.stopWatchingMacDownload()
    }

    fun enterPip() {
        if (supportsPip && playback.current != null) enterPictureInPictureMode(pipParams())
    }

    private val supportsPip: Boolean
        get() = packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)

    private fun pipParams(): PictureInPictureParams {
        // Android only allows ratios between 1:2.39 and 2.39:1.
        val aspect = playback.videoAspect.coerceIn(1 / 2.39f + 0.01f, 2.39f - 0.01f)
        val builder = PictureInPictureParams.Builder()
            .setAspectRatio(Rational((aspect * 1000).toInt(), 1000))
            .setActions(
                listOf(
                    pipAction(
                        if (playback.isPlaying) R.drawable.pip_pause else R.drawable.pip_play,
                        if (playback.isPlaying) "Pause" else "Play", CONTROL_TOGGLE, 1,
                    ),
                    pipAction(R.drawable.pip_next, "Skip", CONTROL_NEXT, 2),
                ),
            )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setAutoEnterEnabled(playback.isPlaying && playback.current != null)
            builder.setSeamlessResizeEnabled(false)
        }
        return builder.build()
    }

    private fun pipAction(icon: Int, title: String, control: String, requestCode: Int): RemoteAction {
        val intent = Intent(ACTION_PIP_CONTROL).setPackage(packageName).putExtra(EXTRA_CONTROL, control)
        val pending = PendingIntent.getBroadcast(this, requestCode, intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        return RemoteAction(Icon.createWithResource(this, icon), title, title, pending)
    }

    private companion object {
        const val ACTION_PIP_CONTROL = "local.curated.phone.PIP_CONTROL"
        const val EXTRA_CONTROL = "control"
        const val CONTROL_TOGGLE = "toggle"
        const val CONTROL_NEXT = "next"
    }
}

/** Matches the Mac app's system-blue accent. */
val Accent = Color(0xFF0A84FF)

/** The red and cyan of the Curated logo (its dark-mode artwork), for the Automix and Top 15 tiles. Light mode uses the red for both. */
val LogoRed = Color(0xFFE33151)
val LogoCyan = Color(0xFF6CE7E2)

/** Platform colors, as on the Mac: TikTok's logo cyan and magenta, and YouTube red. */
val TikTokCyan = Color(0xFF25F4EE)
val TikTokMagenta = Color(0xFFFE2C55)
val YouTubeRed = Color(0xFFFF453A)
/** The green of the classic Vine logo. */
val VineGreen = Color(0xFF00B488)

private val DarkColors = darkColorScheme(
    primary = Accent,
    onPrimary = Color.White,
    secondaryContainer = Accent.copy(alpha = 0.3f),
    onSecondaryContainer = Color.White,
)

/** iOS-style grouped light gray behind white surfaces. */
private val LightColors = lightColorScheme(
    primary = Accent,
    onPrimary = Color.White,
    secondaryContainer = Accent.copy(alpha = 0.18f),
    onSecondaryContainer = Color.Black,
    background = Color(0xFFF2F2F7),
    surface = Color(0xFFF2F2F7),
    surfaceContainer = Color.White,
)

/** Whether the app is drawn dark, for artwork that has light and dark versions (the logo). */
val LocalDarkTheme = staticCompositionLocalOf { true }

sealed interface Screen {
    data object Home : Screen
    data class Player(val mode: PlaybackMode) : Screen
    data class Creator(val username: String, val form: VideoForm = VideoForm.SHORT) : Screen
    data object Settings : Screen
}

/** True in the side-by-side layout, where the player has its own pane and the Now Playing bar isn't needed. */
val LocalTwoPane = staticCompositionLocalOf { false }

/** The narrowest left pane that still fits four creators a row on Home, with a little to spare for rounding. */
private val MIN_FOUR_COLUMN_PANE = 364.dp

/**
 * Phones and a Fold's cover screen get one screen at a time. A wide window (a Fold's inner screen, a tablet) puts the
 * screens on the left and the player on the right, split at the hinge when there's one down the middle. Half-folded on
 * a table, the player takes the window with the video above the hinge and its controls below.
 */
@Composable
fun CuratedRoot(stack: SnapshotStateList<Screen>, fold: FoldingFeature?) {
    val context = LocalContext.current
    val playback = context.curated.playback
    // A long video full screen covers whichever layout is underneath (one pane, two panes or tabletop).
    val fullscreen = playback.fullscreen && playback.current?.form == VideoForm.LONG
    FullscreenEffects(fullscreen)
    // Leave it if what's playing stops being a long video (stopped, or a short one started).
    LaunchedEffect(fullscreen) { if (!fullscreen && playback.fullscreen) exitFullscreen(context) }
    if (fullscreen) {
        FullscreenPlayer()
        return
    }
    BoxWithConstraints(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background)) {
        val density = LocalDensity.current
        val wide = maxWidth >= 600.dp
        val windowWidth = maxWidth

        fun open(screen: Screen) {
            // The player pane shows one queue, so there's only ever one player on the stack.
            if (wide && screen is Screen.Player) stack.removeAll { it is Screen.Player }
            stack.add(screen)
        }
        /** In two panes Back steps back through the left pane; the player stays. */
        val backTarget: Int? =
            if (wide) stack.indices.lastOrNull { it > 0 && stack[it] !is Screen.Player }
            else stack.lastIndex.takeIf { it > 0 }
        fun back() {
            backTarget?.let { stack.removeAt(it) }
        }
        BackHandler(enabled = backTarget != null) { back() }

        val appState = context.curated.state
        appState.olderVideos?.let { target ->
            OlderVideosScreen(target) { appState.olderVideos = null }
            return@BoxWithConstraints
        }
        if (appState.addingCreator) {
            AddCreatorScreen { appState.addingCreator = false }
            return@BoxWithConstraints
        }
        // Settings has the whole window, whatever's playing, and lays itself out for its shape.
        if (stack.last() == Screen.Settings) {
            SettingsScreen(onBack = ::back)
            return@BoxWithConstraints
        }

        val stackedPlayer = (stack.lastOrNull { it is Screen.Player } as Screen.Player?)?.mode
        val tabletop = fold?.takeIf {
            it.state == FoldingFeature.State.HALF_OPENED && it.orientation == FoldingFeature.Orientation.HORIZONTAL
        }
        if (tabletop != null && stackedPlayer != null) {
            val top = with(density) { tabletop.bounds.top.toDp() }
            val bottom = with(density) { tabletop.bounds.bottom.toDp() }
            PlayerScreen(
                stackedPlayer, onBack = { stack.removeAll { it is Screen.Player } },
                layout = PlayerLayout.Tabletop(top, bottom),
            )
            return@BoxWithConstraints
        }

        if (!wide) {
            when (val screen = stack.last()) {
                Screen.Home -> HomeScreen(open = ::open)
                is Screen.Player -> PlayerScreen(mode = screen.mode, onBack = ::back)
                is Screen.Creator -> CreatorScreen(username = screen.username, form = screen.form, open = ::open, onBack = ::back)
                Screen.Settings -> {}
            }
            return@BoxWithConstraints
        }

        // Split at a hinge down the middle, if it's well inside the window; otherwise give the screens a phone's width.
        val hinge = fold?.takeIf { it.orientation == FoldingFeature.Orientation.VERTICAL }?.let {
            with(density) { it.bounds.left.toDp() to it.bounds.right.toDp() }
        }?.takeIf { (left, _) -> left > windowWidth * 0.3f && left < windowWidth * 0.7f }
        // A phone held sideways (a Fold's cover screen), not a tablet or a Fold's inner screen: the video's details
        // and main controls move into the left pane, under the screens, and Home's top bar takes the mix buttons.
        val sideways = maxHeight < 600.dp
        // The open player, or else whatever's loaded (paused after Back on a phone, say).
        val mode = stackedPlayer ?: playback.mode
        val paneWidth = hinge?.first ?: (windowWidth * 0.42f).coerceIn(320.dp, 440.dp)
        val leftWidth = when {
            mode?.form != VideoForm.SHORT -> paneWidth
            // Short videos are narrow, so sideways the left pane takes more of the room.
            sideways -> paneWidth * 1.35f
            // An unfolded Fold held upright: the left pane gives up to 15% to the video, but keeps four creators a
            // row on Home (4 × 80dp, plus the cards' 12dp margins and 8dp padding either side).
            hinge != null && maxHeight > windowWidth -> maxOf(MIN_FOUR_COLUMN_PANE, paneWidth * 0.85f).coerceAtMost(paneWidth)
            else -> paneWidth
        }
        val sideControls = sideways && playback.showsSideControls
        Row(Modifier.fillMaxSize()) {
            // The screens run right up to the edge: sideways, nothing they put there clashes with a punch-hole camera.
            Column(Modifier.width(leftWidth).fillMaxHeight().consumeWindowInsets(WindowInsets.displayCutout)) {
                CompositionLocalProvider(LocalTwoPane provides true) {
                    // The side controls sit over the navigation bar, so the screen above them needn't.
                    Box(Modifier.weight(1f).then(if (sideControls) Modifier.consumeWindowInsets(WindowInsets.navigationBars) else Modifier)) {
                        when (val screen = stack.lastOrNull { it !is Screen.Player } ?: Screen.Home) {
                            Screen.Home -> HomeScreen(open = ::open, mixButtonsInBar = sideways)
                            is Screen.Creator -> CreatorScreen(username = screen.username, form = screen.form, open = ::open, onBack = ::back)
                            Screen.Settings, is Screen.Player -> {}
                        }
                    }
                    if (sideControls) PlayerSideControls()
                }
            }
            if (hinge != null && hinge.second > hinge.first) {
                Spacer(Modifier.width(hinge.second - hinge.first))
            } else {
                Box(Modifier.width(1.dp).fillMaxHeight().background(MaterialTheme.colorScheme.onSurface.copy(alpha = 0.12f)))
            }
            Box(Modifier.weight(1f).fillMaxHeight().background(Color.Black)) {
                if (mode != null) {
                    key(mode) {
                        PlayerScreen(mode, onBack = {}, layout = if (sideways) PlayerLayout.Side else PlayerLayout.Pane)
                    }
                } else {
                    Text(
                        "Pick a mix or a creator to start watching.",
                        color = Color.White.copy(alpha = 0.6f), textAlign = TextAlign.Center,
                        modifier = Modifier.align(Alignment.Center).padding(32.dp),
                    )
                }
            }
        }
    }
}
