package local.curated.phone

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.animation.animateContentSize
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.AddCircle
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.Replay
import androidx.compose.material.icons.filled.MoveToInbox
import androidx.compose.material.icons.filled.StarBorder
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Shuffle
import androidx.compose.material.icons.filled.Star
import androidx.compose.material3.Button
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.verticalScroll
import androidx.compose.ui.semantics.Role
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.unit.IntRect
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.window.Popup
import androidx.compose.ui.window.PopupPositionProvider
import androidx.compose.ui.window.PopupProperties
import kotlinx.coroutines.launch
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.material.icons.filled.People
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import kotlin.math.roundToInt
import androidx.compose.material3.Card
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.ui.graphics.Shape
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.ui.res.painterResource
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Bookmark
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.Image
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HomeScreen(open: (Screen) -> Unit, mixButtonsInBar: Boolean = false) {
    val state = LocalContext.current.curated.state
    val playback = LocalContext.current.curated.playback
    val startMix = mixStarter(open)
    // The top bar's wordmark and buttons make up for display scaling that draws a phone screen smaller than usual.
    val zoom = displayZoomCompensation()
    // Long-pressing Automix or Top 15 picks which cards it plays from.
    var picking by remember { mutableStateOf<MixPick?>(null) }

    // Slowly drifting color behind the frosted cards; fainter than the pairing screen's so lists stay easy to read.
    Box(Modifier.fillMaxSize()) {
        AuroraBackground(intensity = 0.65f, frameIntervalMs = 50)
        Scaffold(
            containerColor = Color.Transparent,
            // A transparent container gives no text color of its own.
            contentColor = MaterialTheme.colorScheme.onBackground,
            topBar = {
                // A screen scaled down by display zoom also gets a little room above the bar.
                Column(Modifier.padding(top = if (zoom > 1f) 8.dp else 0.dp)) {
                    TopAppBar(
                        colors = TopAppBarDefaults.topAppBarColors(containerColor = Color.Transparent, scrolledContainerColor = Color.Transparent),
                        // The logo and wordmark stand in for the title, as on iOS; the long Home has its own wordmark
                        // (landscape cards).
                        title = {
                            val dark = LocalDarkTheme.current
                            Image(
                                painterResource(
                                    // The season's holiday wordmark, while that's turned on in Settings.
                                    Holiday.current()?.takeIf { state.holidayWordmarks }?.wordmark(dark, long = state.form == VideoForm.LONG)
                                        ?: if (state.form == VideoForm.LONG) {
                                            if (dark) R.drawable.wordmark_long_dark else R.drawable.wordmark_long_light
                                        } else {
                                            if (dark) R.drawable.logo_dark else R.drawable.logo_light
                                        },
                                ),
                                contentDescription = if (state.form == VideoForm.LONG) "Curated, long videos" else "Curated",
                                modifier = Modifier.height(32.dp * zoom),
                            )
                        },
                        actions = {
                            // On a phone held sideways, the main mixes are icons here instead of tiles, each lit while
                            // it's the one playing.
                            // Sideways the bar is in a narrow pane, so its buttons stand a little closer.
                            val button = (if (mixButtonsInBar) 44.dp else 48.dp) * zoom
                            if (mixButtonsInBar) {
                                val second = if (LocalDarkTheme.current) LogoCyan else LogoRed
                                val playing = playback.mode
                                if (state.form == VideoForm.SHORT) {
                                    BarMixButton(
                                        Icons.Filled.Shuffle, LogoRed, "Automix", button, zoom,
                                        on = playing is PlaybackMode.Automix && playing.category == null && playing.form == VideoForm.SHORT,
                                        onLongClick = { picking = MixPick.AUTOMIX },
                                    ) { startMix(PlaybackMode.Automix(null)) }
                                    BarMixButton(
                                        Icons.Filled.Star, second, "Top ${PlaybackMode.TOP_COUNT_ALL}", button, zoom,
                                        on = playing is PlaybackMode.Top && playing.category == null,
                                        onLongClick = { picking = MixPick.TOP },
                                    ) { startMix(PlaybackMode.Top(null)) }
                                } else {
                                    BarMixButton(
                                        Icons.Filled.Schedule, LogoRed, "Latest", button, zoom, on = playing == PlaybackMode.Latest(null),
                                    ) { startMix(PlaybackMode.Latest(null)) }
                                    BarMixButton(
                                        Icons.Filled.Shuffle, second, "Automix", button, zoom,
                                        on = playing is PlaybackMode.Automix && playing.category == null && playing.form == VideoForm.LONG,
                                        onLongClick = { picking = MixPick.AUTOMIX },
                                    ) { startMix(PlaybackMode.Automix(null, VideoForm.LONG)) }
                                }
                            }
                            if (state.pairing != null) {
                                IconButton(onClick = { state.addingCreator = true }, Modifier.size(button)) {
                                    Icon(Icons.Filled.Add, contentDescription = "Add Creator", Modifier.size(24.dp * zoom))
                                }
                            }
                            // Shows the other Home's mark: the long-video logo on the short Home, and the other way round.
                            val other = if (state.form == VideoForm.SHORT) VideoForm.LONG else VideoForm.SHORT
                            IconButton(onClick = { state.form = other }, Modifier.size(button)) {
                                // Beside the mix icons, the wide long-video mark comes down to their size.
                                CuratedMark(
                                    if (other == VideoForm.LONG) Mark.LONG else Mark.SHORT,
                                    (if (mixButtonsInBar && other == VideoForm.LONG) 19.dp else 22.dp) * zoom,
                                    Modifier.semantics { contentDescription = if (other == VideoForm.LONG) "Long videos" else "Short videos" },
                                )
                            }
                            IconButton(onClick = { open(Screen.Settings) }, Modifier.size(button)) {
                                Icon(Icons.Filled.Settings, contentDescription = "Settings", Modifier.size(24.dp * zoom))
                            }
                        },
                    )
                    if (state.isSyncing) {
                        val progress = state.syncProgress
                        if (progress != null) {
                            LinearProgressIndicator(progress = { progress }, Modifier.fillMaxWidth())
                        } else {
                            LinearProgressIndicator(Modifier.fillMaxWidth())
                        }
                        Text(
                            state.syncStep, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f),
                            modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp),
                        )
                    }
                }
            },
            bottomBar = { NowPlayingBar(open) },
        ) { padding ->
            val form = state.form
            // The long Home only shows categories that have a long-video creator.
            val shown = state.categories.filter { form == VideoForm.SHORT || state.libraries(it.id, form).isNotEmpty() }
            val others = state.uncategorizedLibraries(form)
            // The creator cards, with the ones that have nothing to play last.
            val cards = buildList {
                shown.forEach { add(HomeCard(it.id, it.name, state.libraries(it.id, form), category = it.id)) }
                if (others.isNotEmpty()) add(HomeCard(OTHER_CARD, if (shown.isEmpty()) "All Creators" else "Other Creators", others))
                // The author of every Vine on the phone, each like a creator.
                if (form == VideoForm.SHORT && state.vineLibraries.isNotEmpty()) add(HomeCard(VINE_CARD, "Vine", state.vineLibraries, vine = true))
            }.sortedBy { card -> card.libraries.none { state.unplayedCount(it) > 0 } }
            when (picking) {
                MixPick.AUTOMIX -> MixPicker(
                    MixPick.AUTOMIX, cards,
                    // As on the Automix tile: bookmarked videos stay out of it.
                    count = { card -> state.automixLibraries(setOf(card.key), form).sumOf { lib -> lib.videos.count { !state.isPlayed(it) && !state.isBookmarked(it) } } },
                    onDismiss = { picking = null },
                ) { picked ->
                    picking = null
                    startMix(PlaybackMode.Automix(null, form, picked))
                }
                // Top lists leave Vines out.
                MixPick.TOP -> MixPicker(
                    MixPick.TOP, cards.filter { !it.vine },
                    count = { card -> state.mixLibraries(setOf(card.key), VideoForm.SHORT).sumOf { state.unplayedCount(it) } },
                    onDismiss = { picking = null },
                ) { picked ->
                    picking = null
                    startMix(PlaybackMode.Top(null, picked))
                }
                null -> {}
            }
            LazyColumn(Modifier.padding(padding)) {
                if (!mixButtonsInBar) item(key = "tiles-$form") {
                    Row(
                        Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 8.dp),
                        horizontalArrangement = Arrangement.spacedBy(10.dp),
                    ) {
                        // What Automix will play: bookmarked videos stay out of it, and so do playlists.
                        val unplayed = state.automixLibraries(null, form).sumOf { lib -> lib.videos.count { !state.isPlayed(it) && !state.isBookmarked(it) } }
                        val second = if (LocalDarkTheme.current) LogoCyan else LogoRed
                        if (form == VideoForm.SHORT) {
                            WatchTile(
                                Icons.Filled.Shuffle, LogoRed, "Automix", if (unplayed > 0) "$unplayed unplayed" else "All caught up",
                                Modifier.weight(1f), onLongClick = { picking = MixPick.AUTOMIX },
                            ) { startMix(PlaybackMode.Automix(null)) }
                            WatchTile(
                                Icons.Filled.Star, second, "Top ${PlaybackMode.TOP_COUNT_ALL}", "Most viewed", Modifier.weight(1f),
                                onLongClick = { picking = MixPick.TOP },
                            ) { startMix(PlaybackMode.Top(null)) }
                        } else {
                            // Long videos: Latest (newest first) and Automix; no Top list.
                            val unwatched = state.mixLibraries(null, VideoForm.LONG).sumOf { state.unplayedCount(it) }
                            WatchTile(
                                Icons.Filled.Schedule, LogoRed, "Latest", if (unwatched > 0) "$unwatched unwatched" else "All caught up",
                                Modifier.weight(1f),
                            ) { startMix(PlaybackMode.Latest(null)) }
                            WatchTile(
                                Icons.Filled.Shuffle, second, "Automix", "Mixed creators", Modifier.weight(1f),
                                onLongClick = { picking = MixPick.AUTOMIX },
                            ) { startMix(PlaybackMode.Automix(null, VideoForm.LONG)) }
                        }
                    }
                }
                // Watch Later and Bookmarks as small icon buttons on the right, each while something is saved. A fixed
                // width, so one alone looks the same as the pair.
                val laterCount = state.watchLaterVideos(form).size
                val bookmarkCount = state.bookmarkedVideos(form).size
                if (laterCount > 0 || bookmarkCount > 0) {
                    item(key = "saved-$form") {
                        Row(
                            Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 2.dp),
                            horizontalArrangement = Arrangement.spacedBy(10.dp, Alignment.End),
                        ) {
                            if (laterCount > 0) {
                                SavedButton(Icons.Filled.MoveToInbox, "Watch Later", laterCount, PlaybackMode.WatchLater(form), open)
                            }
                            if (bookmarkCount > 0) {
                                SavedButton(Icons.Filled.Bookmark, "Bookmarks", bookmarkCount, PlaybackMode.Bookmarks(form), open)
                            }
                        }
                    }
                }

                item { SectionHeader("Creators", 0) }
                // The Mac lists its long-video creators even before any of their videos are downloaded here.
                if (form == VideoForm.LONG && state.longLibraries.all { it.videos.isEmpty() }) {
                    item(key = "noLong") { NoLongVideos(open) }
                }
                items(cards, key = { "card-$form-${it.key}" }) { card ->
                    CreatorCard(
                        card.title, card.libraries, cardKey = card.key, category = card.category, form = form, vine = card.vine, open = open,
                        modifier = Modifier.animateItem(),
                    )
                }
                // Always the last card.
                if (form == VideoForm.LONG && state.playlistLibraries.isNotEmpty()) {
                    item(key = "playlists") { PlaylistsCard(state.playlistLibraries, open) }
                }

                item { LibraryFooter() }
            }
        }
    }
}

/**
 * Opens a mix with a new queue, even when the same mix is already loaded (opening it from the Now Playing bar carries
 * on instead).
 */
@Composable
private fun mixStarter(open: (Screen) -> Unit): (PlaybackMode) -> Unit {
    val app = LocalContext.current.curated
    return { mode ->
        app.playback.start(Queues.build(mode, app.state), mode = mode)
        open(Screen.Player(mode))
    }
}

/** One of Home's creator cards: a category's, "Other Creators" or Vine. `key` is a category id, `OTHER_CARD` or `VINE_CARD`. */
private data class HomeCard(
    val key: String, val title: String, val libraries: List<CreatorLibrary>, val category: String? = null, val vine: Boolean = false,
)

/**
 * One of the main mixes as a top bar button, the size of the bar's other buttons: its tile's icon and color, on a
 * tinted circle while it's the mix that's playing. Tapping the lit one leaves it playing.
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun BarMixButton(
    icon: ImageVector, tint: Color, title: String, size: Dp, zoom: Float, on: Boolean, onLongClick: (() -> Unit)? = null,
    onClick: () -> Unit,
) {
    Box(
        Modifier.size(size).padding(4.dp * zoom).clip(CircleShape)
            .background(if (on) MaterialTheme.colorScheme.secondaryContainer else Color.Transparent)
            .combinedClickable(onLongClick = onLongClick, onClick = { if (!on) onClick() })
            .semantics { contentDescription = if (on) "$title, playing" else title },
        contentAlignment = Alignment.Center,
    ) {
        Icon(icon, contentDescription = null, tint = tint, modifier = Modifier.size(24.dp * zoom))
    }
}

/** A button for one of the main mixes, styled like the creator cards: the icon beside the text, as on iOS. */
@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun WatchTile(
    icon: ImageVector, tint: Color, title: String, subtitle: String, modifier: Modifier, onLongClick: (() -> Unit)? = null,
    onClick: () -> Unit,
) {
    val shape = RoundedCornerShape(20.dp)
    Row(
        modifier
            .frosted(shape)
            .combinedClickable(onClick = onClick, onLongClick = onLongClick)
            .padding(16.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Icon(icon, contentDescription = null, tint = tint, modifier = Modifier.size(30.dp))
        Column {
            Text(title, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold, maxLines = 1)
            Text(subtitle, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f), maxLines = 1)
        }
    }
}

private enum class MixPick { AUTOMIX, TOP }

/**
 * Long-pressing Automix or Top 15: a popup over the dimmed screen with Home's cards as round toggles (each card's glyph,
 * its name below), and under them a red round button that starts the mix (`onStart`) from the ones that are on. On,
 * the glyph turns blue and its unplayed `count` shows as a badge. The cards with something unplayed start on. Tapping
 * outside it, Back, or swiping it away closes it. As on iOS, except that iOS has the button on the right.
 */
@Composable
private fun MixPicker(
    pick: MixPick, cards: List<HomeCard>, count: (HomeCard) -> Int, onDismiss: () -> Unit, onStart: (Set<String>) -> Unit,
) {
    val state = LocalContext.current.curated.state
    val counts = cards.associate { it.key to count(it) }
    // Automix starts from the categories it plays by default (Settings > Playback).
    val off = if (pick == MixPick.AUTOMIX) state.playbackRules.cards(state.form).automixOff else emptySet()
    var picked by remember { mutableStateOf(cards.filter { counts.getValue(it.key) > 0 && it.key !in off }.map { it.key }.toSet()) }
    val total = picked.sumOf { counts.getValue(it) }
    var drag by remember { mutableStateOf(Offset.Zero) }
    val density = LocalDensity.current
    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        // A phone's popup spans the screen; a wide screen (an unfolded Fold) keeps the circles to 300dp across.
        val wide = LocalConfiguration.current.screenWidthDp >= 600
        Column(
            Modifier.padding(horizontal = 16.dp)
                .then(if (wide) Modifier else Modifier.fillMaxWidth())
                .offset { IntOffset(drag.x.roundToInt(), drag.y.roundToInt()) }
                .pointerInput(Unit) {
                    // A long drag in any direction closes it; a short one springs back.
                    detectDragGestures(
                        onDragEnd = {
                            if (drag.getDistance() > with(density) { 90.dp.toPx() }) onDismiss() else drag = Offset.Zero
                        },
                        onDragCancel = { drag = Offset.Zero },
                    ) { change, amount -> change.consume(); drag += amount }
                }
                .clip(RoundedCornerShape(34.dp))
                .background(MaterialTheme.colorScheme.surfaceContainerHigh.copy(alpha = 0.92f))
                .border(1.dp, MaterialTheme.colorScheme.onSurface.copy(alpha = 0.1f), RoundedCornerShape(34.dp))
                .padding(20.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(20.dp),
        ) {
            BoxWithConstraints(
                Modifier.then(if (wide) Modifier.widthIn(max = 300.dp) else Modifier.fillMaxWidth())
                    .heightIn(max = 460.dp).verticalScroll(rememberScrollState()),
            ) {
                val columns = maxOf(2, ((maxWidth + 12.dp) / 96.dp).toInt())
                Column(
                    Modifier.fillMaxWidth().padding(top = 8.dp), horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(18.dp),
                ) {
                    cards.chunked(columns).forEach { row ->
                        // Rows line up on the left; the grid as a whole sits centered.
                        Row(Modifier.width(96.dp * columns - 12.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                            row.forEach { card ->
                                val glyph = when {
                                    card.vine -> null
                                    card.category != null -> categoryGlyph(state.category(card.category)?.symbol)
                                    else -> Icons.Filled.People
                                }
                                PickerToggle(card.title, glyph, card.key in picked, counts.getValue(card.key)) {
                                    picked = if (card.key in picked) picked - card.key else picked + card.key
                                }
                            }
                        }
                    }
                }
            }
            val title = if (pick == MixPick.TOP) "Top ${PlaybackMode.TOP_COUNT_ALL}" else "Automix"
            Box(
                Modifier.size(64.dp).clip(CircleShape).background(LogoRed.copy(alpha = if (total > 0) 1f else 0.4f))
                    .clickable(enabled = total > 0, role = Role.Button) { onStart(picked) }
                    .semantics { contentDescription = title },
                contentAlignment = Alignment.Center,
            ) {
                Icon(if (pick == MixPick.TOP) Icons.Filled.Star else Icons.Filled.Shuffle, null, tint = Color.White, modifier = Modifier.size(28.dp))
            }
        }
    }
}

/** One card in the mix picker: a round toggle with its glyph (`null`: the Vine V), its name below and, while on, a blue glyph and a count badge. */
@Composable
private fun PickerToggle(name: String, glyph: ImageVector?, on: Boolean, count: Int, onToggle: () -> Unit) {
    val onSurface = MaterialTheme.colorScheme.onSurface
    val tint = if (on) PickerBlue else onSurface
    Column(
        Modifier.width(84.dp).clip(RoundedCornerShape(12.dp))
            .toggleable(on, role = Role.Checkbox, onValueChange = { onToggle() })
            .semantics { stateDescription = if (count > 0) "$count unplayed" else "Nothing unplayed" },
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Box {
            Box(
                Modifier.size(64.dp).clip(CircleShape).background(onSurface.copy(alpha = 0.08f))
                    .border(1.dp, onSurface.copy(alpha = 0.1f), CircleShape),
                contentAlignment = Alignment.Center,
            ) {
                if (glyph != null) {
                    Icon(glyph, null, tint = tint, modifier = Modifier.size(28.dp))
                } else {
                    Icon(painterResource(R.drawable.vine_glyph), null, tint = tint, modifier = Modifier.size(24.dp))
                }
            }
            if (on) UnplayedBadge(count, Modifier.align(Alignment.TopEnd).offset(x = 6.dp, y = (-4).dp))
        }
        Text(
            name, style = MaterialTheme.typography.labelMedium, maxLines = 1, overflow = TextOverflow.Ellipsis,
            color = if (on) onSurface else onSurface.copy(alpha = 0.6f),
        )
    }
}

/** iOS's system blue, for a picked card's glyph. */
private val PickerBlue = Color(0xFF0A84FF)

/**
 * Watch Later or Bookmarks: a frosted button with just its icon (its name and count are for TalkBack), always the
 * same size. Tapping it springs a popup list of its videos out of the button; picking one plays the list from
 * there.
 */
@Composable
private fun SavedButton(icon: ImageVector, title: String, count: Int, mode: PlaybackMode, open: (Screen) -> Unit) {
    val shape = RoundedCornerShape(16.dp)
    var showList by remember { mutableStateOf(false) }
    Box {
        Box(
            Modifier.size(width = 52.dp, height = 52.dp).frosted(shape).clickable(onClickLabel = "Show") { showList = true }
                .semantics(mergeDescendants = true) { contentDescription = "$title, $count" },
            contentAlignment = Alignment.Center,
        ) {
            Icon(icon, null, tint = Accent, modifier = Modifier.size(28.dp))
        }
        if (showList) SavedListPopup(title, mode, open) { showList = false }
    }
}

/**
 * The videos in Watch Later or Bookmarks, in a popup just below its button (above it if there's no room), as wide as a
 * phone allows and only as tall as its rows. It grows out of the button with a spring and shrinks back into it.
 */
@Composable
private fun SavedListPopup(title: String, mode: PlaybackMode, open: (Screen) -> Unit, dismiss: () -> Unit) {
    val context = LocalContext.current
    val state = context.curated.state
    val playback = context.curated.playback
    val videos = when (mode) {
        is PlaybackMode.Bookmarks -> state.bookmarkedVideos(mode.form)
        else -> state.watchLaterVideos(mode.form)
    }
    val density = LocalDensity.current
    val gap = with(density) { 8.dp.roundToPx() }
    val margin = with(density) { 12.dp.roundToPx() }
    // Where the button sits within the popup, so it grows out of (and shrinks back into) the button.
    val origin = remember { mutableStateOf(TransformOrigin(0.5f, 0f)) }
    val positioner = remember {
        object : PopupPositionProvider {
            override fun calculatePosition(anchorBounds: IntRect, windowSize: IntSize, layoutDirection: LayoutDirection, popupContentSize: IntSize): IntOffset {
                val x = anchorBounds.left.coerceIn(margin, maxOf(margin, windowSize.width - popupContentSize.width - margin))
                val below = anchorBounds.bottom + gap
                val y = if (below + popupContentSize.height <= windowSize.height - margin) below
                    else maxOf(margin, anchorBounds.top - gap - popupContentSize.height)
                val w = popupContentSize.width.coerceAtLeast(1).toFloat()
                val h = popupContentSize.height.coerceAtLeast(1).toFloat()
                origin.value = TransformOrigin(
                    ((anchorBounds.center.x - x) / w).coerceIn(0f, 1f),
                    ((anchorBounds.center.y - y) / h).coerceIn(0f, 1f),
                )
                return IntOffset(x, y)
            }
        }
    }
    val progress = remember { Animatable(0f) }
    val scope = rememberCoroutineScope()
    LaunchedEffect(Unit) { progress.animateTo(1f, spring(dampingRatio = 0.72f, stiffness = Spring.StiffnessMediumLow)) }
    val close: () -> Unit = { scope.launch { progress.animateTo(0f, tween(150)); dismiss() } }
    val screen = LocalConfiguration.current
    Popup(popupPositionProvider = positioner, onDismissRequest = close, properties = PopupProperties(focusable = true)) {
        val shape = RoundedCornerShape(24.dp)
        Column(
            Modifier.width(minOf(screen.screenWidthDp.dp - 24.dp, 400.dp))
                .heightIn(max = screen.screenHeightDp.dp * 0.6f)
                .graphicsLayer {
                    val p = progress.value
                    transformOrigin = origin.value
                    scaleX = 0.3f + 0.7f * p
                    scaleY = 0.1f + 0.9f * p
                    alpha = (p * 2.5f).coerceIn(0f, 1f)
                }
                .shadow(16.dp, shape)
                .clip(shape)
                .background(MaterialTheme.colorScheme.surfaceContainerHigh)
                .border(1.dp, MaterialTheme.colorScheme.onSurface.copy(alpha = 0.1f), shape),
        ) {
            Text(
                "$title · ${videos.size}", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold,
                modifier = Modifier.padding(start = 16.dp, end = 16.dp, top = 14.dp, bottom = 6.dp),
            )
            LazyColumn(Modifier.padding(bottom = 8.dp)) {
                itemsIndexed(videos, key = { _, v -> v.id }) { index, video ->
                    val pick = Modifier.fillMaxWidth().clickable {
                        playback.start(videos, at = index, mode = mode)
                        dismiss()
                        open(Screen.Player(mode))
                    }
                    val current = playback.current?.id == video.id
                    if (video.form == VideoForm.LONG) {
                        LongVideoRow(video, isCurrent = current, showCreator = true, modifier = pick)
                    } else {
                        VideoRow(
                            video, isCurrent = current, isPlayed = state.isPlayed(video),
                            creator = state.library(video.creator)?.creator, isSaved = state.isSavedForLater(video), modifier = pick,
                        )
                    }
                }
            }
        }
    }
}

/**
 * A category's creators as a collapsible card, like the Mac sidebar: a header with the unplayed count, a toggle for
 * the caught-up creators and the category's Automix and Top buttons, then a grid of avatars with count badges.
 * Only creators with something new show unless the toggle is on. A card with nothing to play starts collapsed.
 * The Vine card (`vine`) has the Vine V before its title and a Vine Automix button.
 */
@Composable
private fun CreatorCard(
    title: String, libraries: List<CreatorLibrary>, cardKey: String, category: String? = null,
    form: VideoForm = VideoForm.SHORT, vine: Boolean = false, open: (Screen) -> Unit, modifier: Modifier = Modifier,
) {
    val state = LocalContext.current.curated.state
    val startMix = mixStarter(open)
    val unplayed = libraries.sumOf { state.unplayedCount(it) }
    // Opened by hand while it has nothing to play; not saved, unlike collapsedCards.
    var openedWhileEmpty by rememberSaveable(cardKey) { mutableStateOf(false) }
    var showCaughtUp by rememberSaveable(cardKey) { mutableStateOf(false) }
    val expanded = if (unplayed > 0) cardKey !in state.collapsedCards else openedWhileEmpty
    val caughtUp = libraries.count { state.unplayedCount(it) == 0 }
    val shape = RoundedCornerShape(20.dp)
    Column(
        modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 5.dp)
            .frosted(shape)
            .animateContentSize(),
    ) {
        Row(
            Modifier.fillMaxWidth().heightIn(min = 48.dp)
                .clickable {
                    if (unplayed > 0) state.setCollapsed(cardKey, expanded) else openedWhileEmpty = !openedWhileEmpty
                }
                .padding(start = 12.dp, end = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            val rotation by animateFloatAsState(if (expanded) 90f else 0f, label = "chevron")
            Icon(
                Icons.Filled.ChevronRight, contentDescription = if (expanded) "Collapse" else "Expand",
                tint = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.4f), modifier = Modifier.size(20.dp).rotate(rotation),
            )
            if (vine) {
                Icon(
                    painterResource(R.drawable.vine_glyph), contentDescription = null,
                    tint = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f), modifier = Modifier.size(16.dp),
                )
            }
            Text(title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, maxLines = 1)
            CountBadge(unplayed)
            Spacer(Modifier.weight(1f))
            CaughtUpToggle(on = showCaughtUp, count = caughtUp) {
                showCaughtUp = !showCaughtUp
                if (showCaughtUp && !expanded) {
                    if (unplayed > 0) state.setCollapsed(cardKey, false) else openedWhileEmpty = true
                }
            }
            if (vine) {
                IconButton(onClick = { startMix(PlaybackMode.VineAutomix) }) {
                    Icon(Icons.Filled.Shuffle, contentDescription = "Vine Automix", tint = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f))
                }
            }
            if (category != null) {
                val tint = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f)
                if (form == VideoForm.LONG) {
                    IconButton(onClick = { startMix(PlaybackMode.Latest(category)) }) {
                        Icon(Icons.Filled.Schedule, contentDescription = "$title Latest", tint = tint)
                    }
                }
                IconButton(onClick = { startMix(PlaybackMode.Automix(category, form)) }) {
                    Icon(Icons.Filled.Shuffle, contentDescription = "$title Automix", tint = tint)
                }
                if (form == VideoForm.SHORT) {
                    IconButton(onClick = { startMix(PlaybackMode.Top(category)) }) {
                        Icon(Icons.Filled.StarBorder, contentDescription = "$title Top ${PlaybackMode.TOP_COUNT_CATEGORY}", tint = tint)
                    }
                }
            }
        }
        if (expanded) {
            // Most unplayed first, then (when shown) the caught-up ones alphabetically. An empty card has only
            // caught-up creators, so opening it shows them.
            val fresh = libraries.filter { state.unplayedCount(it) > 0 }.sortedWith(
                compareByDescending<CreatorLibrary> { state.unplayedCount(it) }
                    .thenBy(String.CASE_INSENSITIVE_ORDER) { it.creator.displayName },
            )
            val rest = if (showCaughtUp || unplayed == 0) {
                libraries.filter { state.unplayedCount(it) == 0 }.sortedWith(compareBy(String.CASE_INSENSITIVE_ORDER) { it.creator.displayName })
            } else emptyList()
            BoxWithConstraints(Modifier.fillMaxWidth().padding(start = 8.dp, end = 8.dp, bottom = 14.dp)) {
                val columns = maxOf(3, (maxWidth / 80.dp).toInt())
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    (fresh + rest).chunked(columns).forEach { row ->
                        Row(Modifier.fillMaxWidth()) {
                            row.forEach { lib ->
                                CreatorCell(lib, Modifier.weight(1f)) { open(Screen.Creator(lib.id, form)) }
                            }
                            repeat(columns - row.size) { Spacer(Modifier.weight(1f)) }
                        }
                    }
                }
            }
        }
    }
}

/** Shows or hides a card's caught-up creators. A circular arrow with a plus, after the Mac's memories.badge.plus. */
@Composable
private fun CaughtUpToggle(on: Boolean, count: Int, onToggle: () -> Unit) {
    IconButton(onClick = onToggle, enabled = count > 0) {
        val tint = when {
            count == 0 -> MaterialTheme.colorScheme.onSurface.copy(alpha = 0.25f)
            on -> Color.White
            else -> MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f)
        }
        Box(
            Modifier.size(32.dp).clip(RoundedCornerShape(8.dp)).background(if (on) Accent else Color.Transparent),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                Icons.Filled.Replay, tint = tint, modifier = Modifier.size(22.dp),
                contentDescription = if (on) "Hide $count caught-up creators" else "Show $count caught-up creators",
            )
            Icon(
                Icons.Filled.AddCircle, null, tint = tint,
                modifier = Modifier.align(Alignment.BottomEnd).padding(end = 3.dp, bottom = 3.dp).size(11.dp)
                    .background(if (on) Accent else MaterialTheme.colorScheme.surface, CircleShape),
            )
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun CreatorCell(library: CreatorLibrary, modifier: Modifier, onClick: () -> Unit) {
    val state = LocalContext.current.curated.state
    val unplayed = state.unplayedCount(library)
    var menu by remember { mutableStateOf(false) }
    Box(modifier, contentAlignment = Alignment.TopCenter) {
        Box(
            Modifier.clip(RoundedCornerShape(12.dp))
                .combinedClickable(onClick = onClick, onLongClick = { menu = true })
                .padding(4.dp),
        ) {
            Avatar(library, library.id, 58.dp, dimmed = unplayed == 0)
            UnplayedBadge(unplayed, Modifier.align(Alignment.TopEnd).offset(x = 4.dp, y = (-2).dp))
        }
        DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
            OlderVideosItem(library) { menu = false }
            OpenCreatorItem(library) { menu = false }
            MarkAllItems(library) { menu = false }
        }
    }
}

/** A long creator's videos on YouTube that aren't downloaded yet, to pick from. */
@Composable
fun OlderVideosItem(library: CreatorLibrary, dismiss: () -> Unit) {
    val state = LocalContext.current.curated.state
    if (library.form != VideoForm.LONG || !library.creator.isYouTube || library.creator.playlist) return
    DropdownMenuItem(
        text = { Text("Older Videos") },
        onClick = {
            dismiss()
            state.olderVideos = OlderVideosTarget(library.id, library.creator.displayName)
        },
    )
}

/** Long-pressing a creator or playlist: its page on YouTube or TikTok, in the app or the browser. */
@Composable
fun OpenCreatorItem(library: CreatorLibrary, dismiss: () -> Unit) {
    val context = LocalContext.current
    val url = library.creator.pageUrl ?: return
    DropdownMenuItem(
        text = { Text("Open in ${library.creator.siteName}") },
        onClick = {
            dismiss()
            runCatching { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url))) }
        },
    )
}

@Composable
fun MarkAllItems(library: CreatorLibrary, dismiss: () -> Unit) {
    val state = LocalContext.current.curated.state
    val unplayed = state.unplayedCount(library)
    // Long videos are "watched", short ones "played".
    val (on, off) = if (library.form == VideoForm.LONG) "Watched" to "Unwatched" else "Played" to "Unplayed"
    DropdownMenuItem(
        text = { Text("Mark All as $on") }, enabled = unplayed > 0,
        onClick = { state.setPlayed(library.videos, true); dismiss() },
    )
    DropdownMenuItem(
        text = { Text("Mark All as $off") }, enabled = unplayed < library.videos.size,
        onClick = { state.setPlayed(library.videos, false); dismiss() },
    )
}

@Composable
private fun LibraryFooter() {
    val state = LocalContext.current.curated.state
    val videos = state.allVideos
    val lines = buildList {
        add("${videos.size} video${if (videos.size == 1) "" else "s"} on this phone · ${formatLength(videos.sumOf { it.duration ?: 0.0 })}")
        state.lastSyncAt?.let { add("Last synced ${relativeDate(it.toEpochMilli())}") }
    }
    Column(Modifier.fillMaxWidth().padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        lines.forEach {
            Text(it, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.5f))
        }
        Spacer(Modifier.size(8.dp))
    }
}

/** The long Home with nothing synced yet: how to get long videos onto the phone. */
@Composable
private fun NoLongVideos(open: (Screen) -> Unit) {
    val state = LocalContext.current.curated.state
    Column(
        Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 5.dp).frosted(RoundedCornerShape(20.dp)).padding(20.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        CuratedMark(Mark.LONG, 36.dp)
        Text("No long videos on this phone", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
        Text(
            if (state.longLibraries.isEmpty()) "Turn on long videos for a YouTube creator (or add a playlist) on your Mac, then sync."
            else "In Settings, set Sync to Long Videos or All Videos, then tap Sync.",
            style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f),
            textAlign = TextAlign.Center,
        )
        if (state.longLibraries.isNotEmpty()) Button(onClick = { open(Screen.Settings) }) { Text("Open Settings") }
    }
}

/**
 * The long Home's last card: one row per YouTube playlist, with its thumbnail, name, how many videos are watched and
 * unwatched, and its length. A row opens the playlist's gallery.
 */
@Composable
private fun PlaylistsCard(playlists: List<CreatorLibrary>, open: (Screen) -> Unit) {
    val state = LocalContext.current.curated.state
    val expanded = "playlists" !in state.collapsedCards
    Column(
        Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 5.dp).frosted(RoundedCornerShape(20.dp)).animateContentSize(),
    ) {
        Row(
            Modifier.fillMaxWidth().heightIn(min = 48.dp).clickable { state.setCollapsed("playlists", expanded) }
                .padding(start = 12.dp, end = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            val rotation by animateFloatAsState(if (expanded) 90f else 0f, label = "chevron")
            Icon(
                Icons.Filled.ChevronRight, contentDescription = if (expanded) "Collapse" else "Expand",
                tint = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.4f), modifier = Modifier.size(20.dp).rotate(rotation),
            )
            CuratedMark(Mark.ALL, 18.dp)
            Text("Playlists", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
            CountBadge(playlists.sumOf { state.unplayedCount(it) })
        }
        if (expanded) {
            Column(Modifier.padding(start = 8.dp, end = 8.dp, bottom = 10.dp)) {
                playlists.forEach { playlist ->
                    val unwatched = state.unplayedCount(playlist)
                    val count = playlist.videos.size
                    var menu by remember { mutableStateOf(false) }
                    Row(
                        Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp))
                            .combinedClickable(onClick = { open(Screen.Creator(playlist.id, VideoForm.LONG)) }, onLongClick = { menu = true })
                            .padding(8.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                            OpenCreatorItem(playlist) { menu = false }
                            MarkAllItems(playlist) { menu = false }
                        }
                        PlaylistThumbnail(playlist, 48.dp)
                        Column(Modifier.weight(1f)) {
                            Text(playlist.creator.displayName, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.Medium, maxLines = 1)
                            val dim = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f)
                            Text("$count video${if (count == 1) "" else "s"} · ${totalLength(playlist.videos)}", style = MaterialTheme.typography.bodySmall, color = dim)
                            Text("${count - unwatched} watched / $unwatched unwatched", style = MaterialTheme.typography.bodySmall, color = dim)
                        }
                    }
                }
            }
        }
    }
}

/** A translucent panel with a soft edge, over the drifting color behind Home (Compose can't blur what's behind it). */
@Composable
private fun Modifier.frosted(shape: Shape): Modifier {
    val dark = LocalDarkTheme.current
    return clip(shape)
        .background((if (dark) Color(0xFF1C1C24) else Color.White).copy(alpha = if (dark) 0.55f else 0.6f))
        .border(1.dp, MaterialTheme.colorScheme.onSurface.copy(alpha = 0.1f), shape)
}
