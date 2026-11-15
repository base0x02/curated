package local.curated.phone

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics

/**
 * Long videos' Latest as a gallery, like a creator's: the unwatched Suggestions first, then everything else newest
 * first (AppState.latestVideos). Picking a video plays the list from there. Upright it's its own screen (long videos
 * open on it); in two panes it's the right-hand pane, beside Home, with no Back.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LatestScreen(category: String?, open: (Screen) -> Unit, onBack: (() -> Unit)?, home: (() -> Unit)? = null) {
    val app = LocalContext.current.curated
    val state = app.state
    val playback = app.playback
    val mode = PlaybackMode.Latest(category)
    val title = listOfNotNull(state.category(category)?.name, "Latest").joinToString(" ")
    val videos = state.latestVideos(category)
    val dim = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f)

    Scaffold(
        topBar = {
            Column {
            TopAppBar(
                title = { Text(title, maxLines = 1) },
                navigationIcon = {
                    if (onBack != null) IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back") }
                },
                actions = { if (onBack != null && category == null) FormSwitchButton() },
            )
            if (home != null) {
                CreatorStrip(category, open = { open(Screen.Creator(it, VideoForm.LONG)) }, all = home)
            }
            }
        },
        bottomBar = { if (onBack != null) NowPlayingBar(open) },
    ) { padding ->
        LazyVerticalGrid(
            GridCells.Adaptive(minSize = 280.dp), Modifier.padding(padding),
            contentPadding = PaddingValues(16.dp),
            horizontalArrangement = Arrangement.spacedBy(16.dp), verticalArrangement = Arrangement.spacedBy(22.dp),
        ) {
            item(span = { GridItemSpan(maxLineSpan) }) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                    Box(Modifier.size(56.dp).clip(RoundedCornerShape(14.dp)).background(LogoRed), contentAlignment = Alignment.Center) {
                        Icon(Icons.Filled.Schedule, null, tint = Color.White, modifier = Modifier.size(30.dp))
                    }
                    Column {
                        Text(title, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
                        Text("${videos.size} unwatched · ${totalLength(videos)}", style = MaterialTheme.typography.bodySmall, color = dim)
                    }
                }
            }
            if (videos.isEmpty()) {
                item(span = { GridItemSpan(maxLineSpan) }) {
                    Text(
                        "All caught up. New long videos appear here after the next sync.",
                        color = dim, textAlign = TextAlign.Center, modifier = Modifier.fillMaxSize().padding(32.dp),
                    )
                }
            }
            itemsIndexed(videos, key = { _, v -> v.id }) { index, video ->
                GalleryCard(
                    video, isCurrent = playback.mode == mode && playback.current?.id == video.id, showCreator = true,
                    modifier = Modifier.clip(RoundedCornerShape(12.dp)).clickable {
                        playback.start(videos, at = index, mode = mode)
                        open(Screen.Player(mode))
                    },
                )
            }
        }
    }
}

/** Back to short videos from Latest, which long videos open on, without going back to Home first. */
@Composable
private fun FormSwitchButton() {
    val state = LocalContext.current.curated.state
    IconButton(onClick = { state.form = VideoForm.SHORT }) {
        CuratedMark(Mark.SHORT, 22.dp, Modifier.semantics { contentDescription = "Short videos" })
    }
}

/**
 * Latest's row of creators upright on a phone: every long creator and playlist, scrolling sideways, the ones with the
 * newest unwatched video first. Picking one opens its gallery; All, pinned at the end with the row scrolling under it,
 * goes to the long Home.
 */
@Composable
private fun CreatorStrip(category: String?, open: (String) -> Unit, all: () -> Unit) {
    val state = LocalContext.current.curated.state
    val background = MaterialTheme.colorScheme.background
    val size = 52.dp
    val libraries = state.libraries(category, VideoForm.LONG)
        .filter { it.videos.isNotEmpty() }
        .sortedWith(
            compareByDescending<CreatorLibrary> { lib -> lib.videos.filter { !state.isPlayed(it) }.maxOfOrNull { it.date } != null }
                .thenByDescending { lib -> lib.videos.filter { !state.isPlayed(it) }.maxOfOrNull { it.date } ?: lib.videos.maxOf { it.date } },
        )
    // The row sets the height; All's fade matches it (matchParentSize). Lazy lists have no intrinsic size to ask for.
    Box(Modifier.fillMaxWidth()) {
        LazyRow(
            contentPadding = PaddingValues(start = 16.dp, end = 76.dp, top = 4.dp, bottom = 8.dp),
            horizontalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            items(libraries, key = { it.id }) { library ->
                val unwatched = state.unplayedCount(library)
                Column(
                    Modifier.width(size + 12.dp).clip(RoundedCornerShape(10.dp)).clickable { open(library.id) },
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    Box {
                        if (library.creator.playlist) {
                            Box(if (unwatched == 0) Modifier.alpha(0.45f) else Modifier) { PlaylistThumbnail(library, size) }
                        } else {
                            Avatar(library, library.id, size, dimmed = unwatched == 0)
                        }
                        if (unwatched > 0) {
                            Box(
                                Modifier.align(Alignment.TopEnd).size(12.dp).clip(CircleShape).background(background)
                                    .padding(2.dp).clip(CircleShape).background(YouTubeRed),
                            )
                        }
                    }
                    Text(
                        library.creator.displayName, style = MaterialTheme.typography.labelSmall, maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        color = MaterialTheme.colorScheme.onSurface.copy(alpha = if (unwatched == 0) 0.6f else 1f),
                        modifier = Modifier.padding(top = 4.dp),
                    )
                }
            }
        }
        // The row fades out as it slides under All.
        Box(Modifier.matchParentSize(), contentAlignment = Alignment.CenterEnd) {
            Box(
                Modifier.fillMaxHeight()
                    .background(Brush.horizontalGradient(0f to Color.Transparent, 0.35f to background))
                    .padding(start = 24.dp, end = 12.dp),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    "All", style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.SemiBold,
                    modifier = Modifier.clip(CircleShape).background(MaterialTheme.colorScheme.onSurface.copy(alpha = 0.08f))
                        .clickable(onClick = all).padding(horizontal = 14.dp, vertical = 8.dp),
                )
            }
        }
    }
}
