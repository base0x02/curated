package local.curated.phone

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.MediaMetadataRetriever
import android.util.LruCache
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Bookmark
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.MoveToInbox
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

// The pieces of the long-video screens: the Curated marks, 16:9 thumbnails, list rows and playlist art.

/** Which Curated mark: the short (portrait cards), long (landscape cards) or playlist one. */
enum class Mark { SHORT, LONG, ALL }

/** A Curated mark in this theme's colors, `height` tall. */
@Composable
fun CuratedMark(mark: Mark, height: Dp, modifier: Modifier = Modifier) {
    val dark = LocalDarkTheme.current
    val res = when (mark) {
        Mark.SHORT -> if (dark) R.drawable.mark_short_dark else R.drawable.mark_short_light
        Mark.LONG -> if (dark) R.drawable.mark_long_dark else R.drawable.mark_long_light
        Mark.ALL -> if (dark) R.drawable.mark_all_dark else R.drawable.mark_all_light
    }
    Image(painterResource(res), contentDescription = null, modifier = modifier.height(height), contentScale = ContentScale.FillHeight)
}

private val posterCache = LruCache<String, Bitmap>(120)

/**
 * A long video's 16:9 thumbnail with rounded corners: the Mac's poster (YouTube's thumbnail) or, without one, a frame
 * a little way in. Its length sits in the bottom-right corner, a red bar shows how far it's been watched, and a watched
 * one is dimmed.
 */
@Composable
fun LongThumbnail(video: Video, modifier: Modifier = Modifier, isCurrent: Boolean = false, corner: Dp = 10.dp) {
    val state = LocalContext.current.curated.state
    val poster = state.store.posterFile(video)
    val file = state.store.videoFile(video)
    val bitmap by produceState(posterCache.get(video.id), video.id, poster.exists()) {
        if (value != null) return@produceState
        value = withContext(Dispatchers.IO) {
            runCatching {
                if (poster.exists()) {
                    BitmapFactory.decodeFile(poster.path)
                } else {
                    val retriever = MediaMetadataRetriever()
                    try {
                        retriever.setDataSource(file.path)
                        val at = ((video.duration ?: 0.0) * 0.1).coerceAtMost(60.0) * 1_000_000
                        retriever.getScaledFrameAtTime(at.toLong(), MediaMetadataRetriever.OPTION_CLOSEST_SYNC, 640, 360)
                    } finally {
                        retriever.release()
                    }
                }
            }.getOrNull()?.also { posterCache.put(video.id, it) }
        }
    }
    val shape = RoundedCornerShape(corner)
    val progress = state.progress(video)
    Box(
        modifier.aspectRatio(16f / 9f).clip(shape)
            .background(MaterialTheme.colorScheme.onSurface.copy(alpha = 0.08f))
            .alpha(if (state.isPlayed(video) && !isCurrent) 0.5f else 1f)
            .then(if (isCurrent) Modifier.border(2.5.dp, Accent, shape) else Modifier),
    ) {
        bitmap?.let {
            Image(it.asImageBitmap(), contentDescription = null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
        }
        if (progress != null) {
            // A dark track so the red reads on any thumbnail.
            Box(Modifier.align(Alignment.BottomStart).fillMaxWidth().height(6.dp).background(Color.Black.copy(alpha = 0.7f))) {
                Box(Modifier.align(Alignment.BottomStart).fillMaxWidth(progress).height(4.dp).background(Color.Red))
            }
        }
        video.duration?.takeIf { it > 0 }?.let { length ->
            Text(
                formatClock(length), color = Color.White, style = MaterialTheme.typography.labelSmall, fontWeight = FontWeight.SemiBold,
                modifier = Modifier.align(Alignment.BottomEnd)
                    .padding(end = 6.dp, bottom = if (progress != null) 10.dp else 6.dp)
                    .background(Color.Black.copy(alpha = 0.75f), RoundedCornerShape(4.dp))
                    .padding(horizontal = 5.dp, vertical = 1.dp),
            )
        }
        if (isCurrent) {
            Icon(Icons.Filled.PlayArrow, null, tint = Color.White, modifier = Modifier.align(Alignment.Center).size(36.dp))
        }
    }
}

/** "Watched · 3 days ago · 1.2M views", with Watch Later and bookmark marks. */
@Composable
fun LongVideoMeta(video: Video) {
    val state = LocalContext.current.curated.state
    val dim = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f)
    val style = MaterialTheme.typography.labelSmall
    Row(horizontalArrangement = Arrangement.spacedBy(5.dp), verticalAlignment = Alignment.CenterVertically) {
        when {
            state.isPlayed(video) -> {
                Icon(Icons.Filled.CheckCircle, null, tint = dim, modifier = Modifier.size(12.dp))
                Text("Watched ·", style = style, color = dim)
            }
            state.isSavedForLater(video) -> {
                Icon(Icons.Filled.MoveToInbox, null, tint = dim, modifier = Modifier.size(12.dp))
                Text("Later ·", style = style, color = dim)
            }
        }
        if (state.isBookmarked(video)) Icon(Icons.Filled.Bookmark, "Bookmarked", tint = dim, modifier = Modifier.size(12.dp))
        val parts = listOfNotNull(
            relativeDate(video.date.toEpochMilli()),
            video.viewCount?.let { "${compactNumber(it)} views" },
        )
        Text(parts.joinToString(" · "), style = style, color = dim, maxLines = 1)
    }
}

/** A long video in a list (Up Next): the wide thumbnail, then its title, creator, description and details. */
@Composable
fun LongVideoRow(video: Video, isCurrent: Boolean, showCreator: Boolean, modifier: Modifier = Modifier) {
    val state = LocalContext.current.curated.state
    Row(
        modifier.background(if (isCurrent) Accent.copy(alpha = 0.15f) else Color.Transparent)
            .padding(horizontal = 16.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        LongThumbnail(video, Modifier.width(150.dp), isCurrent = isCurrent, corner = 8.dp)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(video.displayTitle, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold, maxLines = 2, overflow = TextOverflow.Ellipsis)
            if (showCreator) {
                state.library(video.creator, VideoForm.LONG)?.let {
                    Text(it.creator.displayName, style = MaterialTheme.typography.labelMedium, color = YouTubeRed, fontWeight = FontWeight.SemiBold, maxLines = 1)
                }
            }
            if (video.details.isNotEmpty()) {
                Text(
                    video.details, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f),
                    maxLines = 2, overflow = TextOverflow.Ellipsis,
                )
            }
            LongVideoMeta(video)
        }
    }
}

/** One video in a creator's gallery: the thumbnail, then title, description and details underneath. */
@Composable
fun GalleryCard(video: Video, isCurrent: Boolean, modifier: Modifier = Modifier) {
    Column(modifier, verticalArrangement = Arrangement.spacedBy(6.dp)) {
        LongThumbnail(video, Modifier.fillMaxWidth(), isCurrent = isCurrent, corner = 12.dp)
        Text(video.displayTitle, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold, maxLines = 2, overflow = TextOverflow.Ellipsis)
        if (video.details.isNotEmpty()) {
            Text(
                video.details, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f),
                maxLines = 3, overflow = TextOverflow.Ellipsis,
            )
        }
        LongVideoMeta(video)
    }
}

/** A playlist's YouTube thumbnail cropped to a rounded square, or the playlist mark until it has one. */
@Composable
fun PlaylistThumbnail(library: CreatorLibrary, size: Dp) {
    val state = LocalContext.current.curated.state
    val file = state.store.avatarFile(library.id)
    val bitmap by produceState<Bitmap?>(null, file, file.lastModified()) {
        value = withContext(Dispatchers.IO) { if (file.exists()) BitmapFactory.decodeFile(file.path) else null }
    }
    val shape = RoundedCornerShape(size * 0.22f)
    Box(
        Modifier.size(size).clip(shape).background(MaterialTheme.colorScheme.onSurface.copy(alpha = 0.08f))
            .border(1.dp, Color.White.copy(alpha = 0.15f), shape),
        contentAlignment = Alignment.Center,
    ) {
        val image = bitmap
        if (image != null) {
            Image(image.asImageBitmap(), contentDescription = null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
        } else {
            CuratedMark(Mark.ALL, size * 0.55f)
        }
    }
}

/** The total length of some videos, as "4h 20m". */
fun totalLength(videos: List<Video>): String = formatLength(videos.sumOf { it.duration ?: 0.0 })
