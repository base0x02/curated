package local.curated.phone

import android.content.Context
import android.content.Intent
import androidx.activity.compose.BackHandler
import androidx.annotation.OptIn
import android.view.LayoutInflater
import androidx.compose.animation.animateContentSize
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.displayCutout
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.union
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.material.icons.filled.Layers
import androidx.compose.material.icons.filled.LayersClear
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.material.icons.filled.Bookmark
import androidx.compose.material.icons.filled.BookmarkBorder
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.util.VelocityTracker
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import kotlin.math.abs
import kotlin.math.sign
import kotlinx.coroutines.launch
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.outlined.MoveToInbox
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.painter.Painter
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.drag
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.detectVerticalDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.List
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.FastForward
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.RadioButtonUnchecked
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.IosShare
import androidx.compose.material.icons.filled.SkipNext
import androidx.compose.material.icons.filled.Timer
import androidx.compose.material.icons.filled.MoveToInbox
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.Visibility
import androidx.compose.material3.AssistChip
import androidx.compose.material3.AssistChipDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.FileProvider
import androidx.media3.common.util.UnstableApi
import androidx.media3.ui.PlayerView
import androidx.compose.material.icons.automirrored.filled.PlaylistPlay
import androidx.compose.material.icons.filled.Replay
import androidx.compose.material3.Button
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Switch
import android.app.Activity
import android.content.ContextWrapper
import android.content.pm.ActivityInfo
import android.content.res.Configuration
import androidx.compose.material.icons.filled.Forward10
import androidx.compose.material.icons.filled.Fullscreen
import androidx.compose.material.icons.filled.FullscreenExit
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.Replay10
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.platform.LocalConfiguration
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat

/** How the player sits in the window. */
sealed interface PlayerLayout {
    /** The whole window, with Back. */
    data object Full : PlayerLayout
    /** The right-hand pane on a large screen, such as an unfolded Fold; the left pane handles Back. */
    data object Pane : PlayerLayout
    /**
     * The right-hand pane on a phone held sideways (a Fold's cover screen): the video's details, picture in picture,
     * the queue and, for short videos, the main controls move into the left pane (PlayerSideControls), and the rest
     * stand down the right edge.
     */
    data object Side : PlayerLayout
    /** Half-folded on a table: the video above the hinge, the controls below it. Positions are from the window's top. */
    data class Tabletop(val hingeTop: Dp, val hingeBottom: Dp) : PlayerLayout
}

@kotlin.OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PlayerScreen(mode: PlaybackMode, onBack: () -> Unit, layout: PlayerLayout = PlayerLayout.Full) {
    val context = LocalContext.current
    val state = context.curated.state
    val playback = context.curated.playback
    var showQueue by playback::queueShown
    DisposableEffect(Unit) { onDispose { playback.queueShown = false } }
    val side = layout == PlayerLayout.Side
    // Back (arrow or system gesture) pauses; the video stays in the Now Playing bar.
    val leave = {
        // Not when the car has since started another queue.
        if (playback.mode == mode) playback.pause()
        onBack()
    }
    // Beside other screens, the left pane handles Back.
    val ownsBack = layout != PlayerLayout.Pane && !side
    BackHandler(enabled = ownsBack, onBack = leave)

    val build: (() -> List<Video>)? = if (mode is PlaybackMode.Creator) null else { { Queues.build(mode, state) } }
    LaunchedEffect(mode) {
        // Rebuild if another queue is loaded, or this one was empty (e.g. new videos since).
        if ((playback.mode != mode || playback.queue.isEmpty()) && build != null) playback.start(build(), mode = mode)
    }
    val isLoaded = playback.mode == mode
    val isTimeLimited = isLoaded && playback.timeLimitMinutes != null
    val nothingUnplayed = state.libraries(null, mode.form).all { state.unplayedCount(it) == 0 }

    // The end of a time-limited or Top mix, or of a creator, fills the screen with the sunshine panel, so the video's
    // panel steps aside.
    val sunshine = isLoaded && playback.finished && playback.endsInSunshine
    val video = playback.current?.takeIf { isLoaded && !sunshine }

    // Clear mode: nothing over the video until it's tapped; then everything comes up for 3 seconds after the last touch.
    val clear = playback.clearMode && layout !is PlayerLayout.Tabletop
    var revealed by remember { mutableStateOf(false) }
    var touches by remember { mutableIntStateOf(0) }
    LaunchedEffect(clear, revealed, touches) {
        if (clear && revealed) {
            kotlinx.coroutines.delay(3000)
            revealed = false
        }
    }
    val controlsShown = !clear || revealed
    ClearModeEffects(clear && layout == PlayerLayout.Full)
    // Sideways, a short video's buttons stand in a column down the right edge instead of a row along the bottom; beside
    // the side panel, a long video's do too.
    val buttonsAside = side || layout == PlayerLayout.Full &&
        LocalConfiguration.current.orientation == Configuration.ORIENTATION_LANDSCAPE && video?.form == VideoForm.SHORT
    // Upright (and in a pane, either way up), a short video's buttons stand in a column on the right as on the Mac:
    // the queue and autoplay at the top, then share, speed, and Watch Later, bookmark and played together midway down.
    val buttonColumn = mode.form == VideoForm.SHORT && !buttonsAside && layout !is PlayerLayout.Tabletop
    // Automix can be cut to a time budget: long-press the title or the queue button, or use the queue sheet's button.
    val toggleTimeLimit: (() -> Unit)? =
        if (mode.isAutomix && mode.form == VideoForm.SHORT && build != null && (!nothingUnplayed || isTimeLimited)) { {
            if (isTimeLimited) {
                playback.continueWith(build(), mode)
            } else {
                val minutes = state.timeLimitMinutes
                playback.start(Queues.limitToDuration(build(), minutes * 60.0), mode = mode, timeLimitMinutes = minutes)
            }
        } } else null

    val topBar = @Composable { overVideo: Boolean, modifier: Modifier ->
        PlayerTopBar(
            mode, build, isLoaded, nothingUnplayed, showsBack = ownsBack, onBack = leave,
            showQueue = { showQueue = true }, toggleTimeLimit = toggleTimeLimit, overVideo = overVideo, modifier = modifier,
            showsQueue = !side, buttonColumn = buttonColumn,
            onClearMode = if (layout is PlayerLayout.Tabletop) null else { {
                playback.clearMode = !playback.clearMode
                revealed = false
            } },
        )
    }
    if (layout is PlayerLayout.Tabletop) {
        Column(Modifier.fillMaxSize().background(Color.Black)) {
            VideoArea(mode, isLoaded, Modifier.fillMaxWidth().height(layout.hingeTop))
            Spacer(Modifier.height(layout.hingeBottom - layout.hingeTop))
            Column(Modifier.fillMaxWidth().weight(1f)) {
                topBar(false, if (isTimeLimited) Modifier.background(Accent) else Modifier)
                Spacer(Modifier.weight(1f))
                video?.let { NowPlayingPanel(it, mode, overVideo = false) }
            }
        }
    } else {
        // A time-limited mix puts a blue strip above the video, not over it, with the countdown in place of the usual
        // summary. In clear mode it goes over the video with the rest, so the video can fill the screen. With the
        // buttons in a column, the bar stays over the video (so they keep their places) and just the title turns blue.
        val strip = isTimeLimited && !clear && !buttonColumn
        Column(
            Modifier.fillMaxSize().background(Color.Black).pointerInput(clear) {
                if (!clear) return@pointerInput
                // Any touch while the controls are up keeps them up for another 3 seconds.
                awaitPointerEventScope {
                    while (true) {
                        val event = awaitPointerEvent(PointerEventPass.Initial)
                        if (revealed && event.changes.any { it.pressed }) touches++
                    }
                }
            },
        ) {
            if (strip) topBar(false, Modifier.background(Accent).statusBarsPadding())
            Box(Modifier.fillMaxWidth().weight(1f)) {
                // Beside the side panel, a short video keeps to the left and leaves the room on the right to its buttons.
                val videoSize = if (side && video?.form == VideoForm.SHORT) {
                    Modifier.fillMaxHeight().aspectRatio(playback.videoAspect, matchHeightConstraintsFirst = true)
                } else {
                    Modifier.fillMaxSize()
                }
                VideoArea(mode, isLoaded, videoSize, onTap = if (controlsShown) null else { { revealed = true } })
                androidx.compose.animation.AnimatedVisibility(controlsShown, Modifier.fillMaxSize(), enter = fadeIn(), exit = fadeOut()) {
                    Box(Modifier.fillMaxSize()) {
                        Column(Modifier.fillMaxSize()) {
                            if (!strip) topBar(true, if (isTimeLimited && !buttonColumn) Modifier.background(Accent) else Modifier)
                            video?.let {
                                Box(Modifier.fillMaxWidth().weight(1f)) {
                                    if (!side) {
                                        NowPlayingPanel(
                                            it, mode, Modifier.align(Alignment.BottomCenter), buttonsAside = buttonsAside,
                                            buttonColumn = buttonColumn,
                                            onFullscreen = { enterFullscreen(context) },
                                        )
                                    } else if (it.form == VideoForm.LONG) {
                                        // The details are in the side panel, so a long video keeps just its controls,
                                        // with a thin progress bar along the bottom.
                                        Column(
                                            Modifier.align(Alignment.BottomCenter).fillMaxWidth()
                                                .background(Brush.verticalGradient(listOf(Color.Transparent, Color.Black.copy(alpha = 0.7f))))
                                                .navigationBarsPadding()
                                                .padding(start = 16.dp, end = 72.dp, top = 24.dp, bottom = 4.dp),
                                        ) {
                                            LongTransport(onFullscreen = { enterFullscreen(context) })
                                            it.duration?.takeIf { length -> length > 0 }?.let { length -> ScrubBar(length) }
                                        }
                                    }
                                    if (buttonsAside) {
                                        // Beside the side panel, a short video's played button is there instead.
                                        VideoButtons(
                                            it, vertical = true,
                                            Modifier.align(Alignment.CenterEnd).fillMaxHeight()
                                                .background(Brush.horizontalGradient(listOf(Color.Transparent, Color.Black.copy(alpha = 0.45f))))
                                                .windowInsetsPadding(
                                                    WindowInsets.displayCutout.union(WindowInsets.navigationBars).only(WindowInsetsSides.End),
                                                )
                                                .padding(start = 16.dp, end = 4.dp),
                                            showsPlayed = !side || it.form == VideoForm.LONG,
                                        )
                                    }
                                }
                            }
                        }
                        // Midway down the right edge, as on the Mac, below the queue and autoplay at the top.
                        if (buttonColumn && video != null) {
                            VideoButtonColumn(video, Modifier.align(Alignment.CenterEnd).padding(end = 16.dp))
                        }
                    }
                }
            }
        }
    }

    if (showQueue) {
        // Slides up from the bottom. For long videos it's Up Next: wide rows, and the autoplay switch.
        ModalBottomSheet(onDismissRequest = { showQueue = false }) {
            if (mode.form == VideoForm.LONG) {
                Row(
                    Modifier.fillMaxWidth().padding(start = 20.dp, end = 16.dp, bottom = 8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Column(Modifier.weight(1f)) {
                        Text("Up Next", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                        Text(
                            "${playback.unwatched.size} unwatched · ${formatLength(playback.unwatchedSecondsLeft)} left",
                            style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f),
                        )
                    }
                    Text("Autoplay", style = MaterialTheme.typography.bodyMedium, modifier = Modifier.padding(end = 8.dp))
                    Switch(checked = state.autoplayLong, onCheckedChange = state::updateAutoplayLong)
                }
            }
            if (toggleTimeLimit != null) {
                Row(
                    Modifier.fillMaxWidth().clickable {
                        toggleTimeLimit()
                        showQueue = false
                    }.padding(horizontal = 20.dp, vertical = 12.dp),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    Icon(Icons.Filled.Timer, null, tint = if (isTimeLimited) Accent else MaterialTheme.colorScheme.onSurface)
                    Text("Time Limit", style = MaterialTheme.typography.bodyLarge, color = if (isTimeLimited) Accent else Color.Unspecified)
                }
            }
            val listState = rememberLazyListState(initialFirstVisibleItemIndex = maxOf(0, (playback.index ?: 0) - 2))
            LazyColumn(state = listState) {
                itemsIndexed(playback.queue, key = { _, v -> v.id }) { index, video ->
                    val pick = Modifier.fillMaxWidth().clickable {
                        playback.play(index)
                        showQueue = false
                    }
                    if (video.form == VideoForm.LONG) {
                        LongVideoRow(video, isCurrent = playback.current?.id == video.id, showCreator = mode !is PlaybackMode.Creator, modifier = pick)
                    } else {
                        VideoRow(
                            video, isCurrent = playback.current?.id == video.id, isPlayed = state.isPlayed(video),
                            creator = if (mode is PlaybackMode.Creator) null else state.library(video.creator)?.creator,
                            isSaved = state.isSavedForLater(video), modifier = pick,
                        )
                    }
                }
            }
        }
    }
}

/**
 * The video with its gestures and what's drawn over the middle of it (paused, 2x, the end card). Short videos: swiping
 * drags the video with the finger while the next (or previous) one slides in behind it, with rubber-band resistance
 * where there's nothing to slide in. Long videos don't swipe; they pinch to zoom (see VideoZoom).
 */
@Composable
private fun VideoArea(mode: PlaybackMode, isLoaded: Boolean, modifier: Modifier, onTap: (() -> Unit)? = null) {
    val context = LocalContext.current
    val store = context.curated.state.store
    val playback = context.curated.playback
    val scope = rememberCoroutineScope()
    val offset = remember { Animatable(0f) }
    var height by remember { mutableFloatStateOf(1f) }
    val direction by remember { derivedStateOf { sign(offset.value) } }
    // The video that just slid in keeps its still on top until the player draws its first frame.
    var coverId by remember { mutableStateOf<String?>(null) }
    val isLong = playback.current?.form == VideoForm.LONG
    val haptics = LocalHapticFeedback.current
    val zoom = remember { VideoZoom { haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove) } }
    zoom.aspect = playback.videoAspect
    LaunchedEffect(playback.current?.id) { zoom.reset() }
    // A double tap's "10s" sign: which side (1 ahead, -1 back), shown briefly.
    var skipFlash by remember { mutableIntStateOf(0) }
    var skipFlashCount by remember { mutableIntStateOf(0) }
    LaunchedEffect(skipFlashCount) {
        kotlinx.coroutines.delay(650)
        skipFlash = 0
    }
    val upNext = playback.upNext
    val previous = playback.previousVideo
    LaunchedEffect(upNext?.id) { upNext?.let { loadStill(store.videoFile(it)) } }

    fun follow(raw: Float): Float {
        val hasNeighbor = if (raw < 0) playback.upNext != null else playback.previousVideo != null
        return if (hasNeighbor) raw.coerceIn(-height, height) else raw / 4
    }

    /** Past a quarter of the height, or flicked, the neighbor finishes sliding in and plays; otherwise it springs back. */
    fun endSwipe(raw: Float, velocity: Float) {
        val goingUp = raw < 0
        val committed = abs(raw) > height * 0.25f || (abs(velocity) > 1500f && (velocity < 0) == goingUp)
        val incoming = if (goingUp) playback.upNext else playback.previousVideo
        scope.launch {
            if (!committed || incoming == null) {
                // Swiping up past the last video still finishes the mix.
                if (committed && goingUp) playback.next()
                offset.animateTo(0f, spring(stiffness = Spring.StiffnessMediumLow))
                return@launch
            }
            offset.animateTo(if (goingUp) -height else height, tween(220))
            if (goingUp) playback.next() else playback.previous()
            coverId = playback.current?.id
            offset.snapTo(0f)
        }
    }

    Box(
        modifier.background(Color.Black).clipToBounds().onSizeChanged {
            height = it.height.toFloat()
            zoom.container = Size(it.width.toFloat(), it.height.toFloat())
        }
    ) {
        if (direction < 0 && upNext != null) {
            VideoStill(store.videoFile(upNext), Modifier.fillMaxSize().graphicsLayer { translationY = height + offset.value })
        } else if (direction > 0 && previous != null) {
            VideoStill(store.videoFile(previous), Modifier.fillMaxSize().graphicsLayer { translationY = -height + offset.value })
        }
        Box(
            Modifier.fillMaxSize().graphicsLayer {
                val zoomed = if (isLong) zoom.scale else 1f
                scaleX = zoomed
                scaleY = zoomed
                translationX = if (isLong) zoom.pan.x else 0f
                translationY = offset.value + if (isLong) zoom.pan.y else 0f
            }
        ) {
            VideoSurface()
            val current = playback.current
            if (current != null && coverId == current.id && playback.renderedVideoId != current.id && playback.positionSeconds < 0.3) {
                VideoStill(store.videoFile(current), Modifier.fillMaxSize())
            }
        }

        // Tap to pause, hold for 2x. Short videos: swipe up for the next video and down for the previous one. Long
        // videos: pinch to zoom.
        Box(
            Modifier.fillMaxSize()
                .videoZoom(zoom, scope, enabled = isLong)
                .pointerInput(isLong, onTap) {
                    detectTapGestures(
                        onTap = { (onTap ?: playback::togglePlayPause)() },
                        // Long videos: double-tap the right half to skip ahead 10 seconds, the left half to go back.
                        // (Only for them: listening for a double tap holds up every single tap.)
                        onDoubleTap = if (isLong) { at ->
                            val ahead = at.x > size.width / 2
                            playback.seekBy(if (ahead) 10.0 else -10.0)
                            skipFlash = if (ahead) 1 else -1
                            skipFlashCount++
                        } else null,
                        onLongPress = { playback.holdFast(true) },
                        onPress = {
                            tryAwaitRelease()
                            playback.holdFast(false)
                        },
                    )
                }
                .pointerInput(isLoaded, isLong) {
                    val tracker = VelocityTracker()
                    var raw = 0f
                    var swiping = false
                    detectVerticalDragGestures(
                        onDragStart = {
                            raw = 0f
                            tracker.resetTracking()
                            swiping = isLoaded && !isLong && !playback.isHoldingFast && playback.current != null
                        },
                        onVerticalDrag = { change, dy ->
                            if (swiping) {
                                change.consume()
                                tracker.addPosition(change.uptimeMillis, change.position)
                                raw += dy
                                val target = follow(raw)
                                scope.launch { offset.snapTo(target) }
                            }
                        },
                        onDragEnd = { if (swiping) endSwipe(raw, tracker.calculateVelocity().y) },
                        onDragCancel = { scope.launch { offset.animateTo(0f) } },
                    )
                },
        )

        if (!isLoaded || playback.queue.isEmpty()) {
            Text(
                when (mode) {
                    is PlaybackMode.Top -> "No unplayed videos right now. Check back after the next sync."
                    is PlaybackMode.Latest -> "No unwatched long videos. Check back after the next sync."
                    is PlaybackMode.WatchLater -> "Nothing saved. Use the Watch Later button in the player to set a video aside for later."
                    is PlaybackMode.Bookmarks -> "No bookmarks. Use the bookmark button in the player to keep a video; bookmarked videos stay out of Automix and aren't deleted automatically."
                    else -> "No unplayed videos. Automix alternates between creators' unplayed videos. Check back after the next sync."
                },
                color = Color.White.copy(alpha = 0.7f), textAlign = TextAlign.Center,
                modifier = Modifier.align(Alignment.Center).padding(32.dp),
            )
        } else if (!playback.isPlaying && !playback.finished && !playback.awaitingNext && playback.current != null && direction == 0f) {
            Icon(
                Icons.Filled.PlayArrow, "Paused", tint = Color.White.copy(alpha = 0.8f),
                modifier = Modifier.align(Alignment.Center).size(72.dp),
            )
        }

        if (skipFlash != 0) {
            Row(
                Modifier.align(if (skipFlash > 0) Alignment.CenterEnd else Alignment.CenterStart)
                    .padding(horizontal = 40.dp)
                    .background(Color.Black.copy(alpha = 0.55f), RoundedCornerShape(24.dp))
                    .padding(horizontal = 16.dp, vertical = 10.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                Icon(if (skipFlash > 0) Icons.Filled.Forward10 else Icons.Filled.Replay10, null, tint = Color.White)
                Text("10s", color = Color.White, fontWeight = FontWeight.SemiBold)
            }
        }

        if (playback.finished && isLoaded) {
            val minutes = playback.timeLimitMinutes
            if (playback.endsInSunshine) {
                SunshinePanel(if (minutes != null) "Your $minutes minutes are up" else "You've reached the end")
            } else {
                FinishedCard(Modifier.align(Alignment.Center))
            }
        }
        if (playback.awaitingNext && isLoaded) playback.upNext?.let { UpNextCard(it, Modifier.align(Alignment.Center)) }

        if (playback.isHoldingFast) {
            Row(
                Modifier.align(Alignment.Center)
                    .background(Color.Black.copy(alpha = 0.6f), RoundedCornerShape(20.dp))
                    .padding(horizontal = 16.dp, vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                Text("2x", color = Color.White, fontWeight = FontWeight.SemiBold)
                Icon(Icons.Filled.FastForward, null, tint = Color.White, modifier = Modifier.size(20.dp))
            }
        }
    }
}

/**
 * Title, what's left, and the mix controls: the queue, autoplay and clear mode. Long-pressing the title or the queue
 * button starts or ends Automix's Time Limit. Over the video it fades down from the top; below a hinge it sits plainly.
 */
@Composable
private fun PlayerTopBar(
    mode: PlaybackMode, build: (() -> List<Video>)?, isLoaded: Boolean, nothingUnplayed: Boolean, showsBack: Boolean,
    onBack: () -> Unit, showQueue: () -> Unit, toggleTimeLimit: (() -> Unit)?, overVideo: Boolean, modifier: Modifier,
    onClearMode: (() -> Unit)?, showsQueue: Boolean = true, buttonColumn: Boolean = false,
) {
    val state = LocalContext.current.curated.state
    val playback = LocalContext.current.curated.playback
    val isTimeLimited = isLoaded && playback.timeLimitMinutes != null
    val haptics = LocalHapticFeedback.current
    Column(
        if (overVideo) {
            modifier.fillMaxWidth()
                .background(Brush.verticalGradient(listOf(Color.Black.copy(alpha = 0.7f), Color.Transparent)))
                // Clear mode hides the status bar, but the camera's still there.
                .windowInsetsPadding(WindowInsets.statusBars.union(WindowInsets.displayCutout.only(WindowInsetsSides.Top)))
                .padding(bottom = 16.dp)
        } else {
            // The blue time-limit strip keeps the header's height; below a hinge the bar gets a little room.
            modifier.fillMaxWidth().padding(vertical = if (isTimeLimited) 0.dp else 8.dp)
        },
    ) {
        // Over the video, with the buttons in a column, they're circles down the right; otherwise plain icons in the row.
        val circles = buttonColumn && overVideo
        // Clear mode: shows what a tap does, clearing the screen or keeping the controls up.
        val clearMode = @Composable {
            if (onClearMode != null) {
                BarButton(
                    if (playback.clearMode) Icons.Filled.Layers else Icons.Filled.LayersClear,
                    if (playback.clearMode) "Clear mode is on. Tap to keep the controls up" else "Clear mode: hide the controls until you tap the video",
                    circle = circles, onClick = onClearMode,
                )
            }
        }
        val queue = @Composable {
            BarButton(
                Icons.AutoMirrored.Filled.List, "Queue", circle = circles, enabled = isLoaded && playback.queue.isNotEmpty(),
                onLongClick = toggleTimeLimit?.let { toggle -> { haptics.performHapticFeedback(HapticFeedbackType.LongPress); toggle() } },
                onClick = showQueue,
            )
        }
        val autoplay = @Composable {
            // Short videos: on to the next one when a video ends, or play it on a loop. The glyph alone shows which.
            val on = state.autoplayShort
            BarButton(
                painterResource(if (on) R.drawable.autoplay_on else R.drawable.autoplay_off),
                if (on) "Autoplay is on. Tap to play each video on a loop" else "Autoplay is off. Tap to go on to the next video when one ends",
                circle = circles,
            ) { state.updateAutoplayShort(!on) }
        }
        Row(verticalAlignment = if (circles) Alignment.Top else Alignment.CenterVertically) {
            if (showsBack) {
                IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back", tint = Color.White) }
            } else {
                Spacer(Modifier.width(16.dp))
            }
            val longPress = if (toggleTimeLimit == null) Modifier else Modifier.pointerInput(toggleTimeLimit) {
                detectTapGestures(onLongPress = {
                    haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                    toggleTimeLimit()
                })
            }
            if (circles) {
                // As on the iPhone: the title turns to a blue pill while a time-limited mix counts down, with the
                // countdown beside what's left. The padding stays so the text doesn't jump.
                Box(Modifier.weight(1f)) {
                    Column(
                        Modifier.padding(top = 2.dp).clip(RoundedCornerShape(14.dp))
                            .background(if (isTimeLimited) Accent else Color.Transparent)
                            .then(longPress).padding(horizontal = 10.dp, vertical = 4.dp),
                    ) {
                        Text(title(mode), style = MaterialTheme.typography.titleMedium, color = Color.White, maxLines = 1)
                        Row {
                            if (mode.isOpenMix && isLoaded) QueueSummary(showTimeLeft = !isTimeLimited)
                            if (isTimeLimited) {
                                Text(
                                    " · ${formatClock(playback.secondsUntilEnd)}",
                                    style = MaterialTheme.typography.labelMedium, color = Color.White, fontWeight = FontWeight.SemiBold,
                                )
                            }
                        }
                    }
                }
            } else {
                Column(Modifier.weight(1f).then(longPress)) {
                    Text(title(mode), style = MaterialTheme.typography.titleMedium, color = Color.White, maxLines = 1)
                    if (mode.isOpenMix && isLoaded) QueueSummary(showTimeLeft = !isTimeLimited)
                }
            }
            // A time-limited mix counts down between the title and the buttons, in place of the time left.
            if (isTimeLimited && !circles) {
                Box(Modifier.weight(1f), contentAlignment = Alignment.Center) {
                    Text(formatClock(playback.secondsUntilEnd), color = Color.White, fontWeight = FontWeight.SemiBold)
                }
            }
            if (circles) {
                // The Mac's order: the queue and autoplay; then clear mode. (Time Limit starts from Home, and picture
                // in picture starts by itself on leaving the app.)
                Column(Modifier.padding(end = 16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    if (showsQueue) queue()
                    autoplay()
                    clearMode()
                }
            } else {
                // Long videos: autoplay the next one or not; blue while it's on.
                if (mode.form == VideoForm.LONG) {
                    IconButton(onClick = { state.updateAutoplayLong(!state.autoplayLong) }) {
                        Icon(
                            Icons.AutoMirrored.Filled.PlaylistPlay,
                            if (state.autoplayLong) "Autoplay is on. Tap to stop after each video" else "Autoplay is off. Tap to play the next video automatically",
                            tint = if (state.autoplayLong) Accent else Color.White,
                        )
                    }
                }
                clearMode()
                if (showsQueue) queue()
            }
        }
        // Watch Later and bookmarks keep a way to rebuild. The mixes have none: Home's buttons build a fresh queue.
        if (build != null && (mode is PlaybackMode.WatchLater || mode is PlaybackMode.Bookmarks)) {
            Row(
                Modifier.fillMaxWidth().padding(horizontal = 12.dp),
                horizontalArrangement = Arrangement.End,
            ) {
                AssistChip(
                    onClick = { playback.start(build(), mode = mode) },
                    label = { Text("Refresh") },
                    leadingIcon = { Icon(Icons.Filled.Refresh, null, Modifier.size(AssistChipDefaults.IconSize)) },
                    enabled = !nothingUnplayed || mode is PlaybackMode.Bookmarks,
                    colors = AssistChipDefaults.assistChipColors(
                        containerColor = ChipBackground, labelColor = Color.White, leadingIconContentColor = Color.White,
                    ),
                    border = null,
                )
            }
        }
    }
}

/** All that's shown in the picture-in-picture window. */
@Composable
fun PipVideo() {
    Box(Modifier.fillMaxSize().background(Color.Black)) { VideoSurface() }
}

/** Keeps the mix controls readable over bright video. */
private val ChipBackground = Color.Black.copy(alpha = 0.55f)

@OptIn(UnstableApi::class)
@Composable
private fun VideoSurface() {
    val playback = LocalContext.current.curated.playback
    AndroidView(
        factory = { context ->
            (LayoutInflater.from(context).inflate(R.layout.player_view, null) as PlayerView).apply {
                player = playback.player
            }
        },
        onRelease = { it.player = null },
        modifier = Modifier.fillMaxSize(),
    )
}

@Composable
private fun title(mode: PlaybackMode): String {
    val state = LocalContext.current.curated.state
    return when (mode) {
        is PlaybackMode.Automix -> listOfNotNull(state.category(mode.category)?.name, "Automix").joinToString(" ")
        is PlaybackMode.Latest -> listOfNotNull(state.category(mode.category)?.name, "Latest").joinToString(" ")
        is PlaybackMode.Top -> listOfNotNull(state.category(mode.category)?.name, "Top ${PlaybackMode.topCount(mode.category)}").joinToString(" ")
        is PlaybackMode.WatchLater -> "Watch Later"
        is PlaybackMode.Bookmarks -> "Bookmarks"
        is PlaybackMode.VineAutomix -> "Vine Automix"
        is PlaybackMode.Creator -> state.library(mode.username, mode.form)?.creator?.displayName ?: "@${mode.username.removePrefix(YOUTUBE_KEY_PREFIX)}"
    }
}

/** "12 unwatched · 23:41 left", or just "12 unwatched" while a time-limited mix counts down. Its own composable so the ticking clock only redraws this. */
@Composable
private fun QueueSummary(showTimeLeft: Boolean) {
    val playback = LocalContext.current.curated.playback
    Text(
        "${playback.unwatched.size} unwatched" + if (showTimeLeft) " · ${formatClock(playback.unwatchedSecondsLeft)} left" else "",
        style = MaterialTheme.typography.labelMedium, color = Color.White.copy(alpha = 0.7f),
    )
}

@Composable
private fun NowPlayingPanel(
    video: Video, mode: PlaybackMode, modifier: Modifier = Modifier, overVideo: Boolean = true, buttonsAside: Boolean = false,
    buttonColumn: Boolean = false, onFullscreen: (() -> Unit)? = null,
) {
    var expanded by remember(video.id) { mutableStateOf(false) }
    val isLong = video.form == VideoForm.LONG

    Column(
        modifier.fillMaxWidth()
            .then(if (overVideo) Modifier.background(Brush.verticalGradient(listOf(Color.Transparent, Color.Black.copy(alpha = 0.85f)))) else Modifier)
            .navigationBarsPadding()
            // Leaves room for the buttons standing down the right edge.
            .padding(start = 16.dp, end = if (buttonsAside) 72.dp else 16.dp, top = if (overVideo) 32.dp else 8.dp, bottom = 8.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        NowPlayingDetails(video, mode, expanded) { expanded = !expanded }
        val length = video.duration ?: 0.0
        if (length > 0 && isLong) {
            // Long videos get a seek bar to drag, with the time either side.
            SeekRow(length)
        } else if (length > 0) {
            ScrubBar(length)
        }
        // Long videos: a row of playback controls (back 10 seconds, play or pause, ahead 10, and full screen) above
        // the row of the video's own buttons.
        if (isLong) LongTransport(onFullscreen)
        if (!buttonsAside && !buttonColumn) VideoButtons(video, vertical = false)
    }
}

/** The creator, when and where in the queue, and the caption (a long video's title and description). */
@Composable
private fun NowPlayingDetails(video: Video, mode: PlaybackMode, expanded: Boolean, toggleExpanded: () -> Unit) {
    val state = LocalContext.current.curated.state
    val library = state.library(video.creator, video.form)
    val isLong = video.form == VideoForm.LONG
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Avatar(library, video.creator, 36.dp)
        Column(Modifier.weight(1f)) {
            Text(library?.creator?.displayName ?: "@${video.creator.removePrefix(YOUTUBE_KEY_PREFIX)}", color = Color.White, fontWeight = FontWeight.SemiBold)
            Text(positionLabel(video, mode), style = MaterialTheme.typography.labelSmall, color = Color.White.copy(alpha = 0.7f))
        }
        video.viewCount?.let { views ->
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Icon(Icons.Outlined.Visibility, "Views", tint = Color.White.copy(alpha = 0.85f), modifier = Modifier.size(20.dp))
                Text(compactNumber(views), style = MaterialTheme.typography.labelSmall, color = Color.White.copy(alpha = 0.85f), fontWeight = FontWeight.SemiBold)
            }
        }
    }
    // Long videos: the title, then the description (tap for more).
    if (isLong && video.title.isNotEmpty()) {
        Text(video.title, color = Color.White, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, maxLines = 2, overflow = TextOverflow.Ellipsis)
    }
    val text = if (isLong) video.details else video.caption
    if (text.isNotEmpty()) {
        Text(
            text, color = Color.White, style = MaterialTheme.typography.bodyMedium,
            maxLines = if (expanded) 12 else 2, overflow = TextOverflow.Ellipsis,
            modifier = Modifier.clickable(onClick = toggleExpanded),
        )
    }
}

/**
 * A short video's buttons in a column on the right, in the Mac's order: share, speed, then Watch Later, bookmark and
 * played together in a pill.
 */
@Composable
private fun VideoButtonColumn(video: Video, modifier: Modifier = Modifier) {
    val context = LocalContext.current
    val state = context.curated.state
    val playback = context.curated.playback
    Column(modifier, verticalArrangement = Arrangement.spacedBy(12.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        BarButton(Icons.Filled.IosShare, "Share", circle = true) { share(context, video) }
        Box(
            Modifier.size(CircleSize).clip(CircleShape).background(CircleFill).border(1.dp, CircleEdge, CircleShape)
                .clickable(enabled = !playback.speedLocked, onClickLabel = "Change the playback speed") { playback.cycleSpeed() },
            contentAlignment = Alignment.Center,
        ) {
            Text(
                speedLabel(playback.shownSpeed), color = Color.White.copy(alpha = if (playback.speedLocked) 0.55f else 1f),
                fontWeight = FontWeight.SemiBold, style = MaterialTheme.typography.labelLarge,
            )
        }
        Column(
            Modifier.clip(RoundedCornerShape(50)).background(CircleFill).border(1.dp, CircleEdge, RoundedCornerShape(50))
                .padding(vertical = 4.dp),
        ) {
            val saved = state.isSavedForLater(video)
            PillButton(
                if (saved) Icons.Filled.MoveToInbox else Icons.Outlined.MoveToInbox,
                if (saved) "In Watch Later. Tap to take it off the list" else "Watch Later",
                enabled = !playback.finished || saved,
            ) { if (saved) state.setWatchLater(listOf(video), false) else playback.saveForLater() }
            val bookmarked = state.isBookmarked(video)
            PillButton(
                if (bookmarked) Icons.Filled.Bookmark else Icons.Filled.BookmarkBorder,
                if (bookmarked) "Bookmarked. Tap to remove the bookmark" else "Bookmark: keep out of Automix and never delete automatically",
            ) { playback.toggleBookmark() }
            val isPlayed = state.isPlayed(video)
            PillButton(
                if (isPlayed) Icons.Filled.CheckCircle else Icons.Filled.RadioButtonUnchecked,
                if (isPlayed) "Played. Tap to mark unplayed" else "Mark as played",
            ) { state.setPlayed(video, !isPlayed) }
        }
    }
}

private val CircleSize = 52.dp
/** The Mac's glass, roughly: a dark translucent fill with a faint light edge, so it shows over bright and dark video. */
private val CircleFill = Color.Black.copy(alpha = 0.35f)
private val CircleEdge = Color.White.copy(alpha = 0.18f)

/** A button in the player's bars: a plain icon, or a circle like the Mac's (blue while `on`). */
@Composable
private fun BarButton(
    icon: Any, description: String, circle: Boolean, on: Boolean = false, enabled: Boolean = true,
    onLongClick: (() -> Unit)? = null, onClick: () -> Unit,
) {
    val tint = Color.White.copy(alpha = if (enabled) 1f else 0.45f)
    val glyph = @Composable {
        when (icon) {
            is ImageVector -> Icon(icon, description, tint = tint, modifier = Modifier.size(26.dp))
            is Painter -> Icon(icon, description, tint = tint, modifier = Modifier.size(26.dp))
        }
    }
    if (!circle && onLongClick == null) {
        IconButton(onClick = onClick, enabled = enabled) { glyph() }
        return
    }
    Box(
        (if (circle) Modifier.size(CircleSize).clip(CircleShape).background(if (on) Accent else CircleFill).border(1.dp, CircleEdge, CircleShape)
        else Modifier.size(48.dp).clip(CircleShape))
            .combinedClickable(enabled = enabled, onLongClick = onLongClick, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) { glyph() }
}

@Composable
private fun PillButton(icon: ImageVector, description: String, enabled: Boolean = true, onClick: () -> Unit) {
    Box(
        Modifier.size(width = CircleSize, height = 50.dp).clickable(enabled = enabled, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Icon(icon, description, tint = Color.White.copy(alpha = if (enabled) 1f else 0.45f), modifier = Modifier.size(26.dp))
    }
}

/** A long video's playback controls: back 10 seconds, play or pause, ahead 10, and full screen. */
@Composable
private fun LongTransport(onFullscreen: (() -> Unit)?) {
    val playback = LocalContext.current.curated.playback
    Row(verticalAlignment = Alignment.CenterVertically) {
        // Balances the full screen button, so the three in the middle are centered.
        Spacer(Modifier.size(48.dp))
        Spacer(Modifier.weight(1f))
        IconButton(onClick = { playback.seekBy(-10.0) }) {
            Icon(Icons.Filled.Replay10, "Back 10 seconds", tint = Color.White, modifier = Modifier.size(30.dp))
        }
        Spacer(Modifier.width(20.dp))
        IconButton(onClick = { playback.togglePlayPause() }, enabled = !playback.finished, modifier = Modifier.size(56.dp)) {
            Icon(
                if (playback.isPlaying) Icons.Filled.Pause else Icons.Filled.PlayArrow,
                if (playback.isPlaying) "Pause" else "Play", tint = Color.White, modifier = Modifier.size(42.dp),
            )
        }
        Spacer(Modifier.width(20.dp))
        IconButton(onClick = { playback.seekBy(10.0) }) {
            Icon(Icons.Filled.Forward10, "Ahead 10 seconds", tint = Color.White, modifier = Modifier.size(30.dp))
        }
        Spacer(Modifier.weight(1f))
        if (onFullscreen != null) {
            IconButton(onClick = onFullscreen) { Icon(Icons.Filled.Fullscreen, "Full screen", tint = Color.White) }
        } else {
            Spacer(Modifier.size(48.dp))
        }
    }
}

/** Whether PlayerSideControls has anything to show: a video, and no sunshine panel in its place. */
val Playback.showsSideControls: Boolean get() = current != null && !(finished && endsInSunshine)

/**
 * The bottom of the left pane on a phone held sideways (see PlayerLayout.Side), in place of the details drawn over
 * the video: picture in picture and the queue; for short videos the progress bar, played, play or pause and next;
 * then the creator, date and caption (a long video's title and description). Dragging its handle down (or tapping it)
 * shrinks it to one row, the creator with play or pause and next, to free the screen above; dragging up opens it again.
 */
@Composable
fun PlayerSideControls(modifier: Modifier = Modifier) {
    val context = LocalContext.current
    val state = context.curated.state
    val playback = context.curated.playback
    val mode = playback.mode ?: return
    val video = playback.current?.takeIf { playback.showsSideControls } ?: return
    var expanded by remember(video.id) { mutableStateOf(false) }
    val library = state.library(video.creator, video.form)
    val isLong = video.form == VideoForm.LONG
    val ink = MaterialTheme.colorScheme.onSurface
    val faint = ink.copy(alpha = 0.65f)
    var collapsed by rememberSaveable { mutableStateOf(false) }
    val creatorName = library?.creator?.displayName ?: "@${video.creator.removePrefix(YOUTUBE_KEY_PREFIX)}"
    val playPause = @Composable { buttonSize: Dp, iconSize: Dp ->
        IconButton(onClick = { playback.togglePlayPause() }, enabled = !playback.finished, modifier = Modifier.size(buttonSize)) {
            Icon(
                if (playback.isPlaying) Icons.Filled.Pause else Icons.Filled.PlayArrow,
                if (playback.isPlaying) "Pause" else "Play", tint = ink, modifier = Modifier.size(iconSize),
            )
        }
    }
    val skip = @Composable {
        IconButton(onClick = { playback.next() }, enabled = !playback.finished) {
            Icon(Icons.Filled.SkipNext, "Next video", tint = ink, modifier = Modifier.size(30.dp))
        }
    }

    Column(
        modifier.fillMaxWidth()
            .background(MaterialTheme.colorScheme.surfaceContainer)
            .pointerInput(Unit) {
                // A drag anywhere on the tray (not on the progress bar, which takes its own) opens or shrinks it.
                var dragged = 0f
                detectVerticalDragGestures(
                    onDragStart = { dragged = 0f },
                    onVerticalDrag = { change, dy ->
                        change.consume()
                        dragged += dy
                    },
                    onDragEnd = {
                        if (dragged > 24.dp.toPx()) collapsed = true else if (dragged < -24.dp.toPx()) collapsed = false
                    },
                )
            }
            .animateContentSize()
            .navigationBarsPadding()
            .padding(start = 16.dp, end = 8.dp, bottom = if (collapsed) 4.dp else 10.dp),
        verticalArrangement = Arrangement.spacedBy(2.dp),
    ) {
        // The handle.
        Box(
            Modifier.fillMaxWidth().height(14.dp).clickable(onClickLabel = if (collapsed) "Show the controls" else "Shrink the controls") {
                collapsed = !collapsed
            },
            contentAlignment = Alignment.Center,
        ) {
            Box(Modifier.size(width = 36.dp, height = 4.dp).background(ink.copy(alpha = 0.3f), RoundedCornerShape(50)))
        }
        if (collapsed) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Avatar(library, video.creator, 28.dp)
                Text(
                    if (isLong && video.title.isNotEmpty()) video.title else creatorName, color = ink, fontWeight = FontWeight.SemiBold,
                    maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f),
                )
                playPause(48.dp, 32.dp)
                if (!isLong) skip()
            }
            return@Column
        }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
            IconButton(onClick = { playback.queueShown = true }, enabled = playback.queue.isNotEmpty()) {
                Icon(Icons.AutoMirrored.Filled.List, "Queue", tint = ink)
            }
        }
        if (!isLong) {
            video.duration?.takeIf { it > 0 }?.let { length -> Box(Modifier.padding(end = 8.dp)) { ScrubBar(length, ink) } }
            Row(
                Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(28.dp, Alignment.CenterHorizontally),
            ) {
                val isPlayed = state.isPlayed(video)
                IconButton(onClick = { state.setPlayed(video, !isPlayed) }) {
                    Icon(
                        if (isPlayed) Icons.Filled.CheckCircle else Icons.Filled.RadioButtonUnchecked,
                        if (isPlayed) "Played. Tap to mark unplayed" else "Mark as played", tint = ink,
                    )
                }
                playPause(52.dp, 38.dp)
                skip()
            }
        }
        Row(
            Modifier.padding(top = 4.dp, end = 8.dp),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Avatar(library, video.creator, 36.dp)
            Column(Modifier.weight(1f)) {
                Text(creatorName, color = ink, fontWeight = FontWeight.SemiBold, maxLines = 1)
                Text(positionLabel(video, mode), style = MaterialTheme.typography.labelSmall, color = faint, maxLines = 1)
            }
            video.viewCount?.let { views ->
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Icon(Icons.Outlined.Visibility, "Views", tint = faint, modifier = Modifier.size(20.dp))
                    Text(compactNumber(views), style = MaterialTheme.typography.labelSmall, color = faint, fontWeight = FontWeight.SemiBold)
                }
            }
        }
        if (isLong && video.title.isNotEmpty()) {
            Text(
                video.title, color = ink, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold,
                maxLines = 2, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(top = 4.dp, end = 8.dp),
            )
        }
        val text = if (isLong) video.details else video.caption
        if (text.isNotEmpty()) {
            Text(
                text, color = ink, style = MaterialTheme.typography.bodyMedium,
                maxLines = if (expanded) 8 else 2, overflow = TextOverflow.Ellipsis,
                modifier = Modifier.padding(top = 2.dp, end = 8.dp).clickable { expanded = !expanded },
            )
        }
    }
}

/**
 * The video's own buttons: played, autoplay (short videos), speed, Watch Later, bookmark and share. A row along the
 * bottom, or a column down the right edge when a short video plays sideways.
 */
@Composable
private fun VideoButtons(video: Video, vertical: Boolean, modifier: Modifier = Modifier, showsPlayed: Boolean = true) {
    val context = LocalContext.current
    val state = context.curated.state
    val playback = context.curated.playback
    val isLong = video.form == VideoForm.LONG
    val played = @Composable {
        val isPlayed = state.isPlayed(video)
        IconButton(onClick = { state.setPlayed(video, !isPlayed) }) {
            Icon(
                if (isPlayed) Icons.Filled.CheckCircle else Icons.Filled.RadioButtonUnchecked,
                if (isPlayed) "Played. Tap to mark unplayed" else "Mark as played", tint = Color.White,
            )
        }
    }
    val others = @Composable {
        // Short videos: on to the next one when a video ends, or play it on a loop. The glyph alone shows which.
        if (!isLong) {
            val on = state.autoplayShort
            IconButton(onClick = { state.updateAutoplayShort(!on) }) {
                Icon(
                    painterResource(if (on) R.drawable.autoplay_on else R.drawable.autoplay_off),
                    if (on) "Autoplay is on. Tap to play each video on a loop" else "Autoplay is off. Tap to go on to the next video when one ends",
                    tint = Color.White,
                )
            }
        }
        TextButton(onClick = { playback.cycleSpeed() }, enabled = !playback.speedLocked) {
            Text(speedLabel(playback.shownSpeed), color = Color.White.copy(alpha = if (playback.speedLocked) 0.55f else 1f), fontWeight = FontWeight.SemiBold)
        }
        IconButton(onClick = { playback.saveForLater() }, enabled = !playback.finished) {
            Icon(Icons.Filled.MoveToInbox, "Watch Later", tint = Color.White)
        }
        val bookmarked = state.isBookmarked(video)
        IconButton(onClick = { playback.toggleBookmark() }) {
            Icon(
                if (bookmarked) Icons.Filled.Bookmark else Icons.Filled.BookmarkBorder,
                if (bookmarked) "Bookmarked. Tap to remove the bookmark" else "Bookmark: keep out of Automix and never delete automatically",
                tint = Color.White,
            )
        }
        IconButton(onClick = { share(context, video) }) {
            Icon(Icons.Filled.IosShare, "Share", tint = Color.White)
        }
    }
    if (vertical) {
        Column(modifier, verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
            if (showsPlayed) played()
            others()
        }
    } else {
        Row(modifier, verticalAlignment = Alignment.CenterVertically) {
            played()
            // Tap, swipe and hold on the video play, pause, skip and go back.
            Spacer(Modifier.weight(1f))
            others()
        }
    }
}

@Composable
private fun positionLabel(video: Video, mode: PlaybackMode): String {
    val playback = LocalContext.current.curated.playback
    val index = playback.index ?: 0
    val parts = mutableListOf(relativeDate(video.date.toEpochMilli()))
    when {
        playback.timeLimitMinutes != null -> parts += "${playback.timeLimitMinutes}-min mix · ${index + 1} of ${playback.queue.size}"
        mode is PlaybackMode.VineAutomix -> parts += "Vine Automix"
        mode.isAutomix -> parts += "Automix"
        mode is PlaybackMode.Latest -> parts += "Latest · ${index + 1} of ${playback.queue.size}"
        mode.topLimit != null || mode is PlaybackMode.WatchLater || mode is PlaybackMode.Bookmarks -> parts += "${index + 1} of ${playback.queue.size}"
    }
    return parts.joinToString(" · ")
}

/** Full screen for a long video: the whole window, turned sideways. Leaving it turns the phone back. */
fun enterFullscreen(context: Context) {
    val app = context.curated
    if (app.playback.current?.form != VideoForm.LONG) return
    val activity = context.findActivity()
    app.playback.fullscreenFromPortrait =
        context.resources.configuration.orientation == Configuration.ORIENTATION_PORTRAIT
    app.playback.fullscreen = true
    activity?.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
}

fun exitFullscreen(context: Context) {
    val playback = context.curated.playback
    if (!playback.fullscreen) return
    playback.fullscreen = false
    // Back upright if that's how it started; the sensor takes over again a moment later (FullscreenEffects).
    context.findActivity()?.requestedOrientation =
        if (playback.fullscreenFromPortrait) ActivityInfo.SCREEN_ORIENTATION_USER_PORTRAIT else ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
}

/** Hides the status and navigation bars while full screen, and gives the sensor the orientation back afterwards. */
@Composable
fun FullscreenEffects(fullscreen: Boolean) {
    val context = LocalContext.current
    val activity = context.findActivity()
    DisposableEffect(fullscreen) {
        val window = activity?.window
        val bars = window?.let { WindowCompat.getInsetsController(it, it.decorView) }
        if (fullscreen) {
            bars?.systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            bars?.hide(WindowInsetsCompat.Type.systemBars())
        } else {
            bars?.show(WindowInsetsCompat.Type.systemBars())
        }
        onDispose { bars?.show(WindowInsetsCompat.Type.systemBars()) }
    }
    LaunchedEffect(fullscreen) {
        if (!fullscreen && activity?.requestedOrientation == ActivityInfo.SCREEN_ORIENTATION_USER_PORTRAIT) {
            kotlinx.coroutines.delay(2500)
            activity.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
        }
    }
}

/** Hides the status and navigation bars while clear mode is on in the full-window player; a swipe in from the edge shows them for a moment. */
@Composable
private fun ClearModeEffects(on: Boolean) {
    val activity = LocalContext.current.findActivity()
    DisposableEffect(on) {
        val window = activity?.window
        val bars = window?.let { WindowCompat.getInsetsController(it, it.decorView) }
        if (on) {
            bars?.systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            bars?.hide(WindowInsetsCompat.Type.systemBars())
        }
        onDispose { if (on) bars?.show(WindowInsetsCompat.Type.systemBars()) }
    }
}

/**
 * A long video full screen: just the video while it plays. A tap brings everything up for 3 seconds (exit, the title
 * and creator, back and ahead 10 seconds, play or pause, the description and the seek bar); it all stays up while
 * paused. Double-tap the sides to skip.
 */
@Composable
fun FullscreenPlayer() {
    val context = LocalContext.current
    val state = context.curated.state
    val playback = context.curated.playback
    val video = playback.current ?: return
    val mode = playback.mode ?: return
    var shown by remember { mutableStateOf(true) }
    var pokes by remember { mutableIntStateOf(0) }
    LaunchedEffect(shown, pokes, playback.isPlaying) {
        if (shown && playback.isPlaying) {
            kotlinx.coroutines.delay(3000)
            shown = false
        }
    }
    fun poke() {
        shown = true
        pokes++
    }
    val visible = shown || !playback.isPlaying
    BackHandler { exitFullscreen(context) }
    Box(Modifier.fillMaxSize().background(Color.Black)) {
        VideoArea(mode, isLoaded = true, Modifier.fillMaxSize(), onTap = { if (visible) shown = false else poke() })
        if (visible) {
            val library = state.library(video.creator, video.form)
            Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.4f))) {
                Row(
                    Modifier.align(Alignment.TopStart).fillMaxWidth().padding(8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    IconButton(onClick = { exitFullscreen(context) }) {
                        Icon(Icons.Filled.FullscreenExit, "Exit full screen", tint = Color.White)
                    }
                    Column(Modifier.weight(1f)) {
                        Text(video.displayTitle, color = Color.White, style = MaterialTheme.typography.titleMedium,
                             maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Text(library?.creator?.displayName ?: "", color = Color.White.copy(alpha = 0.7f),
                             style = MaterialTheme.typography.labelMedium, maxLines = 1)
                    }
                }
                Row(
                    Modifier.align(Alignment.Center),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(40.dp),
                ) {
                    IconButton(onClick = { playback.seekBy(-10.0); poke() }, Modifier.size(56.dp)) {
                        Icon(Icons.Filled.Replay10, "Back 10 seconds", tint = Color.White, modifier = Modifier.size(40.dp))
                    }
                    IconButton(onClick = { playback.togglePlayPause(); poke() }, Modifier.size(72.dp)) {
                        Icon(
                            if (playback.isPlaying) Icons.Filled.Pause else Icons.Filled.PlayArrow,
                            if (playback.isPlaying) "Pause" else "Play", tint = Color.White, modifier = Modifier.size(56.dp),
                        )
                    }
                    IconButton(onClick = { playback.seekBy(10.0); poke() }, Modifier.size(56.dp)) {
                        Icon(Icons.Filled.Forward10, "Ahead 10 seconds", tint = Color.White, modifier = Modifier.size(40.dp))
                    }
                }
                Column(
                    Modifier.align(Alignment.BottomCenter).fillMaxWidth().padding(horizontal = 24.dp, vertical = 12.dp),
                    verticalArrangement = Arrangement.spacedBy(4.dp),
                ) {
                    if (video.details.isNotEmpty()) {
                        Text(video.details, color = Color.White.copy(alpha = 0.85f), style = MaterialTheme.typography.bodySmall,
                             maxLines = 2, overflow = TextOverflow.Ellipsis)
                    }
                    video.duration?.takeIf { it > 0 }?.let { length -> SeekRow(length) { poke() } }
                }
            }
        }
        if (playback.awaitingNext) playback.upNext?.let { UpNextCard(it, Modifier.align(Alignment.Center)) }
    }
}

/** The long-video seek bar with the time either side. `onChange` runs while it's dragged. */
@Composable
private fun SeekRow(length: Double, onChange: () -> Unit = {}) {
    val playback = LocalContext.current.curated.playback
    var scrubbing by remember(playback.current?.id) { mutableStateOf<Float?>(null) }
    val shown = scrubbing?.toDouble() ?: playback.positionSeconds
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(formatClock(shown), style = MaterialTheme.typography.labelSmall, color = Color.White.copy(alpha = 0.8f))
        Slider(
            value = shown.toFloat().coerceIn(0f, length.toFloat()),
            onValueChange = { scrubbing = it; onChange() },
            onValueChangeFinished = {
                scrubbing?.let { playback.seek(it.toDouble()) }
                scrubbing = null
            },
            valueRange = 0f..length.toFloat(),
            colors = SliderDefaults.colors(thumbColor = Color.White, activeTrackColor = Color.White, inactiveTrackColor = Color.White.copy(alpha = 0.25f)),
            modifier = Modifier.weight(1f),
        )
        Text("-" + formatClock(length - shown), style = MaterialTheme.typography.labelSmall, color = Color.White.copy(alpha = 0.8f))
    }
}

/**
 * The short-video progress bar, which scrubs like TikTok's: touch it and slide along, and the video pauses and follows
 * the finger, the bar thickens and the time shows above it. Playback picks up again on release if it was playing.
 */
@Composable
private fun ScrubBar(length: Double, color: Color = Color.White) {
    val playback = LocalContext.current.curated.playback
    var scrubbing by remember(playback.current?.id) { mutableStateOf<Double?>(null) }
    val shown = scrubbing ?: playback.positionSeconds
    val fraction = (shown / length).toFloat().coerceIn(0f, 1f)
    val thickness by animateDpAsState(if (scrubbing != null) 6.dp else 3.dp, label = "scrub bar")
    Box(
        Modifier.fillMaxWidth()
            // Taller than the bar, so it's easy to catch with a finger.
            .height(20.dp)
            .pointerInput(length) {
                fun timeAt(x: Float) = (x / size.width).coerceIn(0f, 1f) * length
                awaitEachGesture {
                    val down = awaitFirstDown()
                    down.consume()
                    val wasPlaying = playback.isPlaying
                    playback.pause()
                    fun scrubTo(x: Float) {
                        val time = timeAt(x)
                        scrubbing = time
                        playback.seek(time)
                    }
                    scrubTo(down.position.x)
                    drag(down.id) { change ->
                        change.consume()
                        scrubTo(change.position.x)
                    }
                    scrubbing = null
                    if (wasPlaying) playback.resume()
                }
            },
        contentAlignment = Alignment.CenterStart,
    ) {
        Box(Modifier.fillMaxWidth().height(thickness).background(color.copy(alpha = 0.25f), RoundedCornerShape(50)))
        Box(Modifier.fillMaxWidth(fraction).height(thickness).background(color, RoundedCornerShape(50)))
        if (scrubbing != null) {
            Text(
                "${formatClock(shown)} / ${formatClock(length)}",
                style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, color = Color.White,
                modifier = Modifier.align(Alignment.Center).offset(y = (-36).dp)
                    .background(Color.Black.copy(alpha = 0.6f), RoundedCornerShape(8.dp))
                    .padding(horizontal = 10.dp, vertical = 4.dp),
            )
        }
    }
}

/** The Activity behind a Compose context, for the window and orientation. */
private fun Context.findActivity(): Activity? = when (this) {
    is Activity -> this
    is ContextWrapper -> baseContext.findActivity()
    else -> null
}

/** When a long video ends with autoplay off: what's next, to play or skip, or the one that just ended again. */
@Composable
private fun UpNextCard(next: Video, modifier: Modifier = Modifier) {
    val playback = LocalContext.current.curated.playback
    Column(
        modifier.padding(24.dp)
            .background(Color(0xFF1C1C1E).copy(alpha = 0.92f), RoundedCornerShape(16.dp))
            .padding(20.dp)
            .width(280.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Text("Up Next", style = MaterialTheme.typography.labelLarge, color = Color.White.copy(alpha = 0.6f))
        LongThumbnail(next, Modifier.fillMaxWidth(), corner = 10.dp)
        Text(next.displayTitle, style = MaterialTheme.typography.titleMedium, color = Color.White, textAlign = TextAlign.Center, maxLines = 2, overflow = TextOverflow.Ellipsis)
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            TextButton(onClick = { playback.replay() }) {
                Icon(Icons.Filled.Replay, null, tint = Color.White, modifier = Modifier.size(18.dp))
                Spacer(Modifier.width(6.dp))
                Text("Replay", color = Color.White)
            }
            Button(onClick = { playback.playNext() }) {
                Icon(Icons.Filled.PlayArrow, null, modifier = Modifier.size(18.dp))
                Spacer(Modifier.width(6.dp))
                Text("Play Next")
            }
        }
    }
}

/** The end of a queue that doesn't get `SunshinePanel` (Automix, Watch Later, Bookmarks…). */
@Composable
private fun FinishedCard(modifier: Modifier = Modifier) {
    Column(
        modifier.padding(32.dp)
            .background(Color(0xFF1C1C1E).copy(alpha = 0.92f), RoundedCornerShape(16.dp))
            .padding(28.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Icon(Icons.Outlined.CheckCircle, null, tint = Color.White, modifier = Modifier.size(48.dp))
        Text("You're all caught up", style = MaterialTheme.typography.titleLarge, color = Color.White, textAlign = TextAlign.Center)
        Text("No unplayed videos left here.", color = Color.White.copy(alpha = 0.7f), textAlign = TextAlign.Center)
    }
}

/** "1x", "1.5x", "2x". */
private fun speedLabel(speed: Float): String =
    (if (speed % 1f == 0f) speed.toInt().toString() else speed.toString()) + "x"

private fun share(context: Context, video: Video) {
    val file = context.curated.state.store.videoFile(video)
    val uri = FileProvider.getUriForFile(context, "${context.packageName}.files", file)
    val intent = Intent(Intent.ACTION_SEND)
        .setType(if (video.fileExtension == "mov") "video/quicktime" else "video/mp4")
        .putExtra(Intent.EXTRA_STREAM, uri)
        .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    context.startActivity(Intent.createChooser(intent, null))
}
