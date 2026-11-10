package local.curated.phone

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CreatorScreen(username: String, form: VideoForm = VideoForm.SHORT, open: (Screen) -> Unit, onBack: () -> Unit) {
    val app = LocalContext.current.curated
    val state = app.state
    val playback = app.playback
    val library = state.library(username, form)
    var menu by remember { mutableStateOf(false) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(library?.creator?.displayName ?: "@${username.removePrefix(YOUTUBE_KEY_PREFIX)}", maxLines = 1) },
                navigationIcon = {
                    IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back") }
                },
                actions = {
                    // Older Videos is there for a creator with nothing downloaded yet, too.
                    if (library != null && (library.videos.isNotEmpty() || form == VideoForm.LONG)) {
                        Box {
                            IconButton(onClick = { menu = true }) { Icon(Icons.Filled.MoreVert, "More") }
                            DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                                OlderVideosItem(library) { menu = false }
                                if (library.videos.isNotEmpty()) MarkAllItems(library) { menu = false }
                            }
                        }
                    }
                },
            )
        },
        bottomBar = { NowPlayingBar(open) },
    ) { padding ->
        if (library == null || library.videos.isEmpty()) {
            Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
                Text(
                    "No videos for ${library?.creator?.displayName ?: "@${username.removePrefix(YOUTUBE_KEY_PREFIX)}"} on this phone yet.",
                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f), textAlign = TextAlign.Center, modifier = Modifier.padding(32.dp),
                )
            }
            return@Scaffold
        }
        val mode = PlaybackMode.Creator(username, form)
        val videos = if (form == VideoForm.LONG) state.longVideos(library) else library.videos
        fun play(index: Int) {
            playback.start(videos, at = index, mode = mode)
            open(Screen.Player(mode))
        }
        if (form == VideoForm.LONG) {
            // A gallery: the creator (or playlist) on top, then a thumbnail card per video, more across on wide screens.
            LazyVerticalGrid(
                GridCells.Adaptive(minSize = 280.dp), Modifier.padding(padding),
                contentPadding = PaddingValues(16.dp),
                horizontalArrangement = Arrangement.spacedBy(16.dp), verticalArrangement = Arrangement.spacedBy(22.dp),
            ) {
                item(span = { GridItemSpan(maxLineSpan) }) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                        if (library.creator.playlist) PlaylistThumbnail(library, 56.dp) else Avatar(library, username, 56.dp)
                        Column {
                            Text(library.creator.displayName, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
                            val count = library.videos.size
                            Text(
                                "$count video${if (count == 1) "" else "s"} · ${state.unplayedCount(library)} unwatched · ${totalLength(library.videos)}",
                                style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f),
                            )
                        }
                    }
                }
                itemsIndexed(videos, key = { _, v -> v.id }) { index, video ->
                    GalleryCard(
                        video, isCurrent = playback.mode == mode && playback.current?.id == video.id,
                        modifier = Modifier.clip(RoundedCornerShape(12.dp)).clickable { play(index) },
                    )
                }
            }
        } else {
            LazyColumn(Modifier.padding(padding)) {
                itemsIndexed(videos, key = { _, v -> v.id }) { index, video ->
                    VideoRow(
                        video, isCurrent = playback.current?.id == video.id, isPlayed = state.isPlayed(video), creator = null, isSaved = state.isSavedForLater(video),
                        modifier = Modifier.fillMaxWidth().clickable { play(index) },
                    )
                }
            }
        }
    }
}
