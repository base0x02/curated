package local.curated.phone

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.MediaMetadataRetriever
import android.text.format.DateUtils
import android.util.DisplayMetrics
import android.util.LruCache
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.MoveToInbox
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.ColorMatrix
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.PlatformTextStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File

@Composable
fun Avatar(library: CreatorLibrary?, username: String, size: Dp, dimmed: Boolean = false) {
    val context = LocalContext.current
    val file = remember(username) { context.curated.state.store.avatarFile(username) }
    val bitmap by produceState<Bitmap?>(null, file, file.lastModified()) {
        value = withContext(Dispatchers.IO) { if (file.exists()) BitmapFactory.decodeFile(file.path) else null }
    }
    val image = bitmap
    val ring = Modifier.border(maxOf(1.5.dp, size / 24), platformRing(username), CircleShape)
    // Caught-up creators: grayscale and faded, so the ones with something new stand out.
    val fade = if (dimmed) Modifier.alpha(0.45f) else Modifier
    if (image != null) {
        Image(
            image.asImageBitmap(), contentDescription = library?.creator?.displayName,
            contentScale = ContentScale.Crop,
            colorFilter = if (dimmed) grayscale else null,
            modifier = Modifier.size(size).then(fade).clip(CircleShape).then(ring),
        )
    } else {
        Box(
            // Vine authors without a picture get Vine green.
            Modifier.size(size).then(fade).clip(CircleShape).background(
                (if (username.startsWith(VINE_KEY_PREFIX)) VineGreen else Accent).let { Brush.verticalGradient(listOf(it, it.copy(alpha = 0.6f))) },
            ).then(ring),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                // A Vine author's key is a number, so their name's first letter.
                (if (username.startsWith(VINE_KEY_PREFIX)) library?.creator?.displayName.orEmpty() else username.removePrefix(YOUTUBE_KEY_PREFIX))
                    .take(1).uppercase(), color = Color.White, fontWeight = FontWeight.SemiBold,
                fontSize = (size.value * 0.45f).sp,
            )
        }
    }
}

/** Avatar outline: YouTube red, Vine green, or TikTok's cyan-to-magenta. */
fun platformRing(creatorKey: String): Brush = when {
    isYouTubeKey(creatorKey) -> SolidColor(YouTubeRed)
    creatorKey.startsWith(VINE_KEY_PREFIX) -> SolidColor(VineGreen)
    else -> Brush.linearGradient(listOf(TikTokCyan, TikTokMagenta))
}

/** Creator names in queues. */
val Creator.tint: Color get() = when {
    isYouTube -> YouTubeRed
    isVine -> VineGreen
    else -> TikTokCyan
}

private val grayscale = ColorFilter.colorMatrix(ColorMatrix().apply { setToSaturation(0f) })

/**
 * An app-icon-style count for an avatar's corner: a circle for one digit, a capsule for more. Hidden at zero. Its
 * height is fixed, since the text's own line height (font padding included) made single digits taller than wide.
 */
@Composable
fun UnplayedBadge(count: Int, modifier: Modifier = Modifier) {
    if (count <= 0) return
    Box(
        modifier
            .border(2.dp, MaterialTheme.colorScheme.background, CircleShape)
            .padding(1.dp)
            .clip(CircleShape).background(Accent)
            .height(20.dp)
            .defaultMinSize(minWidth = 20.dp)
            .padding(horizontal = 5.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            if (count > 99) "99+" else "$count",
            color = Color.White, textAlign = TextAlign.Center,
            style = TextStyle(
                fontSize = 11.sp, lineHeight = 11.sp, fontWeight = FontWeight.Bold,
                platformStyle = PlatformTextStyle(includeFontPadding = false),
            ),
        )
    }
}

private val thumbnailCache = LruCache<String, Bitmap>(200)

/** A frame from half a second in, like the Mac's thumbnails. */
@Composable
fun Thumbnail(file: File, modifier: Modifier = Modifier) {
    val bitmap by produceState(thumbnailCache.get(file.path), file) {
        if (value != null) return@produceState
        value = withContext(Dispatchers.IO) {
            runCatching {
                val retriever = MediaMetadataRetriever()
                try {
                    retriever.setDataSource(file.path)
                    retriever.getScaledFrameAtTime(500_000, MediaMetadataRetriever.OPTION_CLOSEST_SYNC, 180, 320)
                } finally {
                    retriever.release()
                }
            }.getOrNull()?.also { thumbnailCache.put(file.path, it) }
        }
    }
    Box(modifier.background(MaterialTheme.colorScheme.onSurface.copy(alpha = 0.08f))) {
        bitmap?.let {
            Image(it.asImageBitmap(), contentDescription = null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
        }
    }
}

private val stillCache = LruCache<String, Bitmap>(8)

/** A video's first frame at screen size, shown while it slides in during a swipe. */
@Composable
fun VideoStill(file: File, modifier: Modifier = Modifier) {
    val bitmap by produceState(stillCache.get(file.path), file) {
        if (value == null) value = loadStill(file)
    }
    Box(modifier.background(Color.Black)) {
        bitmap?.let {
            Image(it.asImageBitmap(), contentDescription = null, contentScale = ContentScale.Fit, modifier = Modifier.fillMaxSize())
        }
    }
}

/** Reads (and caches) a video's first frame, so it's ready before a swipe starts. */
suspend fun loadStill(file: File): Bitmap? = stillCache.get(file.path) ?: withContext(Dispatchers.IO) {
    runCatching {
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(file.path)
            retriever.getScaledFrameAtTime(0, MediaMetadataRetriever.OPTION_CLOSEST_SYNC, 1080, 1920)
        } finally {
            retriever.release()
        }
    }.getOrNull()?.also { stillCache.put(file.path, it) }
}

@Composable
fun VideoRow(
    video: Video, isCurrent: Boolean, isPlayed: Boolean, creator: Creator?, modifier: Modifier = Modifier, isSaved: Boolean = false,
) {
    val context = LocalContext.current
    Row(
        modifier
            .background(if (isCurrent) Accent.copy(alpha = 0.15f) else Color.Transparent)
            .padding(horizontal = 16.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Box {
            Thumbnail(
                context.curated.state.store.videoFile(video),
                Modifier.size(54.dp, 96.dp).clip(RoundedCornerShape(6.dp))
                    .alpha(if (isPlayed && !isCurrent) 0.45f else 1f)
                    .then(if (isCurrent) Modifier.border(2.dp, Accent, RoundedCornerShape(6.dp)) else Modifier),
            )
            if (isCurrent) {
                Icon(Icons.Filled.PlayArrow, null, tint = Color.White, modifier = Modifier.align(Alignment.Center))
            }
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            if (creator != null) {
                Text(creator.displayName, style = MaterialTheme.typography.labelMedium, color = creator.tint, fontWeight = FontWeight.SemiBold)
            }
            Text(
                video.caption.ifEmpty { "No caption" },
                style = MaterialTheme.typography.bodyMedium,
                color = if (video.caption.isEmpty() || isPlayed) MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f) else MaterialTheme.colorScheme.onSurface,
                maxLines = 3, overflow = TextOverflow.Ellipsis,
            )
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                val meta = MaterialTheme.typography.labelSmall
                val dim = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f)
                if (isPlayed) {
                    Icon(Icons.Filled.CheckCircle, null, tint = dim, modifier = Modifier.size(12.dp))
                    Text("Played ·", style = meta, color = dim)
                } else if (isSaved) {
                    Icon(Icons.Filled.MoveToInbox, null, tint = dim, modifier = Modifier.size(12.dp))
                    Text("Later ·", style = meta, color = dim)
                }
                Text(videoMeta(video), style = meta, color = dim, maxLines = 1)
            }
        }
    }
}

fun videoMeta(video: Video): String = buildList {
    add(relativeDate(video.date.toEpochMilli()))
    video.viewCount?.let { add("${compactNumber(it)} views") }
    video.duration?.let { add(formatClock(it)) }
}.joinToString(" · ")

fun relativeDate(millis: Long): String =
    DateUtils.getRelativeTimeSpanString(millis, System.currentTimeMillis(), DateUtils.MINUTE_IN_MILLIS).toString()

fun compactNumber(n: Long): String = when {
    n >= 1_000_000_000 -> "%.1fB".format(n / 1e9)
    n >= 1_000_000 -> "%.1fM".format(n / 1e6)
    n >= 1_000 -> "%.1fK".format(n / 1e3)
    else -> n.toString()
}.replace(".0", "")

@Composable
fun CountBadge(count: Int) {
    if (count <= 0) return
    Text(
        "$count",
        style = MaterialTheme.typography.labelMedium,
        modifier = Modifier.clip(CircleShape).background(MaterialTheme.colorScheme.onSurface.copy(alpha = 0.12f)).padding(horizontal = 8.dp, vertical = 2.dp),
    )
}

@Composable
fun SectionHeader(title: String, unplayed: Int) {
    Row(Modifier.padding(start = 16.dp, end = 16.dp, top = 20.dp, bottom = 6.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(title.uppercase(), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
        Spacer(Modifier.weight(1f))
        CountBadge(unplayed)
    }
}

/**
 * How much smaller than at its native density a phone-sized screen draws things because of display scaling (Screen
 * zoom on a Galaxy Fold's outer screen can put it at 360 dpi instead of 420), so a few key controls can be drawn that
 * much bigger. 1 on larger screens (a Fold's inner one looks right as it is) and at the native density.
 */
@Composable
fun displayZoomCompensation(): Float {
    val configuration = LocalConfiguration.current
    if (configuration.smallestScreenWidthDp >= 600) return 1f
    return (DisplayMetrics.DENSITY_DEVICE_STABLE.toFloat() / configuration.densityDpi).coerceIn(1f, 1.3f)
}
