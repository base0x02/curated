package local.curated.phone

import androidx.annotation.OptIn
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.media3.common.util.UnstableApi
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.PlayerView

/** Shown at the bottom of the lists while a video is loaded. Tap to go back to it, ✕ to stop. */
@Composable
fun NowPlayingBar(open: (Screen) -> Unit) {
    // Two panes have the player beside the list instead.
    if (LocalTwoPane.current) return
    val app = LocalContext.current.curated
    val playback = app.playback
    val video = playback.current ?: return
    val mode = playback.mode ?: return
    if (playback.finished) return
    val library = app.state.library(video.creator, video.form)
    val isLong = video.form == VideoForm.LONG

    Column(Modifier.fillMaxWidth().background(MaterialTheme.colorScheme.surfaceContainer).navigationBarsPadding()) {
        HorizontalDivider(color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.08f))
        Row(
            Modifier.fillMaxWidth().clickable { open(Screen.Player(mode)) }.padding(horizontal = 12.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            LivePreview(video, Modifier.size(if (isLong) 64.dp else 36.dp, if (isLong) 36.dp else 64.dp).clip(RoundedCornerShape(6.dp)))
            Column(Modifier.weight(1f)) {
                Text(
                    "Now Playing · ${library?.creator?.displayName ?: "@${video.creator.removePrefix(YOUTUBE_KEY_PREFIX)}"}",
                    style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.SemiBold, maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                Text(
                    if (isLong) video.displayTitle else video.caption.ifEmpty { "No caption" },
                    style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f),
                    maxLines = 1, overflow = TextOverflow.Ellipsis,
                )
            }
            IconButton(onClick = { playback.togglePlayPause() }) {
                Icon(if (playback.isPlaying) Icons.Filled.Pause else Icons.Filled.PlayArrow, if (playback.isPlaying) "Pause" else "Play")
            }
            IconButton(onClick = { playback.stop() }) {
                Icon(Icons.Filled.Close, "Stop")
            }
        }
    }
}

/** The player itself, small. A thumbnail sits underneath until a frame is drawn. */
@OptIn(UnstableApi::class)
@Composable
private fun LivePreview(video: Video, modifier: Modifier) {
    val app = LocalContext.current.curated
    Box(modifier.background(Color.Black)) {
        Thumbnail(app.state.store.videoFile(video), Modifier.fillMaxSize())
        AndroidView(
            factory = { context ->
                PlayerView(context).apply {
                    useController = false
                    resizeMode = AspectRatioFrameLayout.RESIZE_MODE_ZOOM
                    setShutterBackgroundColor(android.graphics.Color.TRANSPARENT)
                    player = app.playback.player
                }
            },
            onRelease = { it.player = null },
            modifier = Modifier.fillMaxSize(),
        )
    }
}
