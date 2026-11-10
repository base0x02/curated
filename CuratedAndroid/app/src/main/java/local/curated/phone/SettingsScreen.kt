package local.curated.phone

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.displayCutout
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.VerticalDivider
import androidx.compose.material.icons.automirrored.filled.List
import androidx.compose.material.icons.filled.Palette
import androidx.compose.material.icons.filled.People
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Storage
import androidx.compose.material.icons.filled.Sync
import androidx.compose.material.icons.filled.PersonAdd
import androidx.compose.material.icons.filled.Download
import androidx.compose.material.icons.filled.ArrowDropDown
import androidx.compose.material3.Checkbox
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.FilterChip
import androidx.compose.runtime.key
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.draw.clip
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Computer
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.animation.Crossfade
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.layout.Box
import androidx.compose.material.icons.filled.ArrowDownward
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.text.style.TextOverflow
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SegmentedButton
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.Spacer
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch
import android.os.Build
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.border
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.blur
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.style.TextAlign
import kotlin.math.max

/** Settings' pages. */
private enum class SettingsPage(val title: String, val icon: ImageVector, val tint: Color) {
    Sync("Sync", Icons.Filled.Sync, Color(0xFF34A853)),
    Playback("Playback", Icons.Filled.PlayArrow, LogoRed),
    Appearance("Appearance", Icons.Filled.Palette, Color(0xFFFF9500)),
    Storage("Storage", Icons.Filled.Storage, Color(0xFFAF52DE)),
}

/**
 * The whole window. An upright phone or a Fold's cover screen gets tabs along the bottom. Anything wider, a phone on its
 * side or a Fold's inner screen either way up, gets the pages listed on the left and the chosen one on the right. The
 * chosen page carries over when the shape changes.
 */
@Composable
fun SettingsScreen(onBack: () -> Unit) {
    var page by rememberSaveable { mutableStateOf(SettingsPage.Sync) }
    BoxWithConstraints(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background)) {
        if (maxWidth >= 600.dp || maxWidth > maxHeight) {
            val listWidth = (maxWidth * 0.32f).coerceIn(220.dp, 320.dp)
            Row(Modifier.fillMaxSize().windowInsetsPadding(WindowInsets.displayCutout.only(WindowInsetsSides.Horizontal))) {
                SettingsBar("Settings", onBack, Modifier.width(listWidth)) { padding ->
                    Column(Modifier.padding(padding).verticalScroll(rememberScrollState()).padding(8.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        SettingsPage.entries.forEach { option -> SettingsRow(option, selected = option == page) { page = option } }
                    }
                }
                VerticalDivider()
                SettingsBar(page.title, null, Modifier.weight(1f)) { padding -> PageContent(page, padding) }
            }
        } else {
            SettingsBar(
                page.title, onBack,
                bottomBar = {
                    NavigationBar {
                        SettingsPage.entries.forEach { option ->
                            NavigationBarItem(
                                selected = option == page, onClick = { page = option },
                                icon = { Icon(option.icon, null) }, label = { Text(option.title) },
                            )
                        }
                    }
                },
            ) { padding -> PageContent(page, padding) }
        }
    }
}

/** A title, with a Back arrow if there's somewhere to go back to, over `content`. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SettingsBar(
    title: String, onBack: (() -> Unit)?, modifier: Modifier = Modifier, bottomBar: @Composable () -> Unit = {},
    content: @Composable (PaddingValues) -> Unit,
) {
    Scaffold(
        modifier,
        topBar = {
            TopAppBar(
                title = { Text(title) },
                navigationIcon = { if (onBack != null) IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back") } },
            )
        },
        bottomBar = bottomBar,
        content = content,
    )
}

/** Each page starts at its top. */
@Composable
private fun PageContent(page: SettingsPage, padding: PaddingValues) {
    key(page) {
        Column(
            Modifier.padding(padding).verticalScroll(rememberScrollState()).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            when (page) {
                SettingsPage.Sync -> SyncPage()
                SettingsPage.Playback -> PlaybackPage()
                SettingsPage.Appearance -> AppearancePage()
                SettingsPage.Storage -> StoragePage()
            }
        }
    }
}

/** A page in the list on the left: a white icon on a rounded square of color and its name, lit while chosen. */
@Composable
private fun SettingsRow(page: SettingsPage, selected: Boolean, onClick: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp))
            .background(if (selected) MaterialTheme.colorScheme.primary.copy(alpha = 0.16f) else Color.Transparent)
            .clickable(onClick = onClick).padding(horizontal = 10.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Box(Modifier.size(30.dp).clip(RoundedCornerShape(8.dp)).background(page.tint), contentAlignment = Alignment.Center) {
            Icon(page.icon, null, Modifier.size(19.dp), tint = Color.White)
        }
        Text(page.title, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

/** Pairing, or once paired, the Mac and what syncs from it. */
@Composable
private fun SyncPage() {
    val pairing = LocalContext.current.curated.state.pairing
    if (pairing == null) PairSection() else SyncSection(pairing)
    VersionFooter()
}

@Composable
private fun AppearancePage() {
    AppearancePicker()
    BackgroundPicker()
    HolidayWordmarksRow()
}

/** What's on this phone: the videos with the space they take, and how long they'd take to watch. */
@Composable
private fun StoragePage() {
    val state = LocalContext.current.curated.state
    val videos = state.allVideos
    val bytes = remember(videos.size) { state.store.bytesUsed() }
    SettingsHeader("On this phone")
    InfoRow("Videos", "${videos.size} · ${formatBytes(bytes)}")
    InfoRow("Watch time", formatLength(videos.sumOf { it.duration ?: 0.0 }))
    Text(
        "Videos your Mac deletes are removed here on the next sync. Watched videos sync both ways.",
        style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f),
    )
}

/** Short and long videos' options. Autoplay is this phone's; the rest is shared with the Mac and other phones. */
@Composable
private fun PlaybackPage() {
    val state = LocalContext.current.curated.state
    // See what another device changed. If the Mac can't be reached, these still work here.
    LaunchedEffect(Unit) { state.exchangePositions() }
    SettingsHeader("Short videos")
    SwitchRow("Autoplay", "With this off, each video plays on a loop.", state.autoplayShort, state::updateAutoplayShort)
    Text("Time limit", style = MaterialTheme.typography.bodyLarge)
    ChoiceChips(
        (PlaybackRules.TIME_LIMIT_CHOICES + state.timeLimitMinutes).distinct().sorted(), state.timeLimitMinutes, { "$it min" },
    ) { minutes -> state.updatePlaybackRules { it.copy(timeLimitMinutes = minutes) } }
    Text(
        "How long a Time Limit mix plays before suggesting some sunshine.",
        style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f),
    )
    CategoryRules(VideoForm.SHORT)

    Spacer(Modifier.height(8.dp))
    SettingsHeader("Long videos")
    SwitchRow("Autoplay", "With this off, a video stops at its end with an Up Next card.", state.autoplayLong, state::updateAutoplayLong)
    Text("Back up when resuming", style = MaterialTheme.typography.bodyLarge)
    ChoiceChips(
        (PlaybackRules.REWIND_CHOICES + state.playbackRules.resumeRewindSeconds).distinct().sorted(), state.playbackRules.resumeRewindSeconds,
        { if (it == 0) "Off" else "$it sec" },
    ) { seconds -> state.updatePlaybackRules { it.copy(resumeRewindSeconds = seconds) } }
    Text(
        "Starts a video a little before where you left off.",
        style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f),
    )
    CategoryRules(VideoForm.LONG)
}

@Composable
private fun SwitchRow(title: String, detail: String, checked: Boolean, onChange: (Boolean) -> Unit) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f).padding(end = 12.dp)) {
            Text(title)
            Text(detail, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
        }
        Switch(checked = checked, onCheckedChange = onChange)
    }
}

@Composable
private fun ChoiceChips(choices: List<Int>, selected: Int, label: (Int) -> String, onPick: (Int) -> Unit) {
    Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        choices.forEach { choice ->
            FilterChip(selected = choice == selected, onClick = { onPick(choice) }, label = { Text(label(choice)) })
        }
    }
}

private data class RuleRow(val key: String, val name: String, val glyph: ImageVector?, val inMixes: Boolean = true)

/** A form's cards from Home in rows: whether Automix plays each by default, and whether it stays at 1x. */
@Composable
private fun CategoryRules(form: VideoForm) {
    val state = LocalContext.current.curated.state
    // As in the Automix picker, plus long videos' playlists, which are never in a mix.
    val shown = state.categories.filter { form == VideoForm.SHORT || state.libraries(it.id, form).isNotEmpty() }
    val rows = buildList {
        shown.forEach { add(RuleRow(it.id, it.name, categoryGlyph(it.symbol))) }
        if (state.uncategorizedLibraries(form).isNotEmpty()) add(RuleRow(OTHER_CARD, if (shown.isEmpty()) "All Creators" else "Other Creators", Icons.Filled.People))
        if (form == VideoForm.SHORT && state.vineLibraries.isNotEmpty()) add(RuleRow(VINE_CARD, "Vine", null))
        if (form == VideoForm.LONG && state.playlistLibraries.isNotEmpty()) add(RuleRow(PLAYLIST_CARD, "Playlists", Icons.AutoMirrored.Filled.List, inMixes = false))
    }
    if (rows.isEmpty()) return
    val cards = state.playbackRules.cards(form)
    fun change(edit: (PlaybackRules.Cards) -> PlaybackRules.Cards) = state.updatePlaybackRules {
        if (form == VideoForm.LONG) it.copy(long = edit(it.long)) else it.copy(short = edit(it.short))
    }
    val column = 64.dp
    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(vertical = 6.dp)) {
            Row(Modifier.padding(horizontal = 16.dp, vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                Text("Categories", Modifier.weight(1f), style = MaterialTheme.typography.labelMedium)
                Text("Automix", Modifier.width(column), style = MaterialTheme.typography.labelSmall, textAlign = TextAlign.Center)
                Text("1x only", Modifier.width(column), style = MaterialTheme.typography.labelSmall, textAlign = TextAlign.Center)
            }
            rows.forEach { row ->
                Row(Modifier.padding(start = 16.dp, end = 16.dp), verticalAlignment = Alignment.CenterVertically) {
                    Box(Modifier.width(32.dp)) {
                        if (row.glyph != null) {
                            Icon(row.glyph, null, Modifier.size(20.dp), tint = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
                        } else {
                            Icon(painterResource(R.drawable.vine_glyph), null, Modifier.size(18.dp), tint = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
                        }
                    }
                    Text(row.name, Modifier.weight(1f), maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Box(Modifier.width(column), contentAlignment = Alignment.Center) {
                        if (row.inMixes) {
                            Checkbox(checked = row.key !in cards.automixOff, onCheckedChange = { on ->
                                change { it.copy(automixOff = if (on) it.automixOff - row.key else it.automixOff + row.key) }
                            })
                        } else {
                            Text("–", color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.4f))
                        }
                    }
                    Box(Modifier.width(column), contentAlignment = Alignment.Center) {
                        Checkbox(checked = row.key in cards.normalSpeed, onCheckedChange = { on ->
                            change { it.copy(normalSpeed = if (on) it.normalSpeed + row.key else it.normalSpeed - row.key) }
                        })
                    }
                }
            }
        }
    }
    Text(
        "Automix plays the checked categories. Long-pressing it still lets you pick others for that mix, and a category's own Automix always plays it. A 1x only category plays at normal speed, and your chosen speed comes back on the next video.",
        style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f),
    )
}

/** The app's version and build, centered under everything else, as on iOS: "Curated 2.0 (11)". */
@Composable
private fun VersionFooter() {
    val context = LocalContext.current
    val version = remember {
        runCatching { context.packageManager.getPackageInfo(context.packageName, 0) }.getOrNull()
            ?.let { "Curated ${it.versionName} (${it.longVersionCode})" } ?: "Curated"
    }
    Text(
        version, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f),
        textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth().padding(vertical = 8.dp),
    )
}

/** A label with its value on the right, like a row in iOS Settings. */
@Composable
private fun InfoRow(label: String, value: String) {
    Row(Modifier.fillMaxWidth()) {
        Text(label, Modifier.weight(1f))
        Text(value, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
    }
}

/** Aurora or Holiday behind Home, then that style's palettes as round swatches to tap. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun BackgroundPicker() {
    val state = LocalContext.current.curated.state
    SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
        BackgroundStyle.entries.forEachIndexed { i, option ->
            SegmentedButton(
                selected = state.backgroundStyle == option,
                onClick = { state.updateBackgroundStyle(option) },
                shape = SegmentedButtonDefaults.itemShape(i, BackgroundStyle.entries.size),
            ) { Text(option.label) }
        }
    }
    val palettes = if (state.backgroundStyle == BackgroundStyle.Holiday) AuroraPalette.holiday else AuroraPalette.aurora
    Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        palettes.forEach { palette ->
            val selected = state.palette.id == palette.id
            Column(
                Modifier.width(80.dp).clip(RoundedCornerShape(10.dp)).clickable { state.updatePalette(palette.id) }.padding(vertical = 4.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                Box(
                    Modifier.size(54.dp)
                        .border(2.5.dp, if (selected) MaterialTheme.colorScheme.primary else Color.Transparent, CircleShape)
                        .padding(4.dp)
                        .clip(CircleShape),
                ) { PaletteSwatch(palette) }
                Text(
                    palette.name, style = MaterialTheme.typography.labelSmall, textAlign = TextAlign.Center, minLines = 2, maxLines = 2,
                    color = if (selected) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f),
                )
            }
        }
    }
}

/** A still of a palette's aurora: its four blobs at rest, blurred over its base, in light or dark to match. */
@Composable
private fun PaletteSwatch(palette: AuroraPalette) {
    val dark = LocalDarkTheme.current
    Box(Modifier.fillMaxSize()) {
        Canvas(Modifier.fillMaxSize()) { drawRect(if (dark) palette.darkBase else palette.lightBase) }
        Canvas(Modifier.fillMaxSize().then(if (Build.VERSION.SDK_INT >= 31) Modifier.blur(6.dp) else Modifier)) {
            val side = max(size.width, size.height) * 1.3f
            val spots = listOf(Triple(0.22f, 0.2f, 0.75f), Triple(0.82f, 0.38f, 0.7f), Triple(0.45f, 0.82f, 0.85f), Triple(0.65f, 0.62f, 0.6f))
            spots.zip(palette.blobs).forEach { (spot, blob) ->
                val color = AuroraPalette.shade(blob.first, dark).copy(alpha = (AuroraPalette.strength(dark) * 1.3f * blob.second).coerceAtMost(1f))
                val center = Offset(spot.first * size.width, spot.second * size.height)
                val radius = side * spot.third / 2
                drawCircle(Brush.radialGradient(listOf(color, color.copy(alpha = 0f)), center, radius), radius, center)
            }
        }
    }
}

/** Home's wordmark becomes the season's holiday one; all three shown, faded while it's off. */
@Composable
private fun HolidayWordmarksRow() {
    val state = LocalContext.current.curated.state
    val dark = LocalDarkTheme.current
    Row(verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text("Holiday wordmarks")
            // The short Home's, then the long Home's.
            Column(
                Modifier.horizontalScroll(rememberScrollState()).alpha(if (state.holidayWordmarks) 1f else 0.45f),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                listOf(false, true).forEach { long ->
                    Row(horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                        Holiday.entries.forEach { holiday ->
                            Image(
                                painterResource(holiday.wordmark(dark, long)),
                                if (long) "${holiday.label}, long videos" else holiday.label, Modifier.height(20.dp),
                            )
                        }
                    }
                }
            }
        }
        Switch(checked = state.holidayWordmarks, onCheckedChange = state::updateHolidayWordmarks)
    }
}

@Composable
private fun SettingsHeader(title: String) {
    Text(title.uppercase(), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
}

/** System, Light or Dark. The player stays dark either way. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun AppearancePicker() {
    val state = LocalContext.current.curated.state
    SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
        Appearance.entries.forEachIndexed { i, option ->
            SegmentedButton(
                selected = state.appearance == option,
                onClick = { state.updateAppearance(option) },
                shape = SegmentedButtonDefaults.itemShape(i, Appearance.entries.size),
            ) { Text(option.label) }
        }
    }
}

@Composable
private fun PairSection() {
    val context = LocalContext.current
    val state = context.curated.state
    val scope = rememberCoroutineScope()
    var found by remember { mutableStateOf(emptyList<FoundMac>()) }
    var searching by remember { mutableStateOf(false) }
    var selected by remember { mutableStateOf<FoundMac?>(null) }
    var address by remember { mutableStateOf("") }
    var code by remember { mutableStateOf("") }
    var pairing by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }

    fun search() {
        scope.launch {
            searching = true
            found = Discovery.find(context)
            if (selected == null && address.isBlank()) selected = found.firstOrNull()
            searching = false
        }
    }
    LaunchedEffect(Unit) { search() }

    Text(
        "On your Mac, open Curated, click the phone button at the bottom of the sidebar and choose Pair a Phone. " +
            "Then pick your Mac here and enter the code it shows.",
        color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.8f),
    )

    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(vertical = 8.dp)) {
            Row(Modifier.padding(horizontal = 16.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                Text("Macs on this network", style = MaterialTheme.typography.titleSmall, modifier = Modifier.weight(1f))
                if (searching) CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
                else TextButton(onClick = ::search) { Text("Search Again") }
            }
            if (found.isEmpty() && !searching) {
                Text(
                    "None found. Check that phone sync is on and the Mac is discoverable, or enter its address below.",
                    style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f),
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp),
                )
            }
            for (mac in found) {
                Row(
                    Modifier.fillMaxWidth().clickable { selected = mac; address = "" }.padding(horizontal = 8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    RadioButton(selected = selected == mac && address.isBlank(), onClick = { selected = mac; address = "" })
                    Icon(Icons.Filled.Computer, null, Modifier.padding(end = 8.dp))
                    Column {
                        Text(mac.name)
                        Text("${mac.host}:${mac.port}", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
                    }
                }
            }
        }
    }

    OutlinedTextField(
        value = address, onValueChange = { address = it.trim() },
        label = { Text("Or enter the Mac's address") },
        placeholder = { Text("192.168.1.20:8765") },
        supportingText = { Text("Shown in the Mac's sync panel. For USB, use 127.0.0.1 (see below).") },
        singleLine = true, modifier = Modifier.fillMaxWidth(),
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri),
    )

    OutlinedTextField(
        value = code, onValueChange = { code = it.filter(Char::isDigit).take(6) },
        label = { Text("Pairing code") },
        singleLine = true, modifier = Modifier.fillMaxWidth(),
        textStyle = MaterialTheme.typography.headlineSmall.copy(fontFamily = FontFamily.Monospace),
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword),
    )

    val target: Pair<String, Int>? = if (address.isNotBlank()) parseMacAddress(address) else selected?.let { it.host to it.port }
    error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
    Button(
        onClick = {
            val (host, port) = target ?: return@Button
            scope.launch {
                pairing = true
                error = state.pair(host, port, code)
                pairing = false
                if (error == null) state.syncInBackground()
            }
        },
        enabled = target != null && code.length == 6 && !pairing,
        modifier = Modifier.fillMaxWidth(),
    ) {
        Text(if (pairing) "Pairing…" else "Pair")
    }

    HorizontalDivider()
    UsbHelp()
}

@Composable
private fun SyncSection(pairing: Pairing) {
    val state = LocalContext.current.curated.state
    var confirmUnpair by remember { mutableStateOf(false) }
    var choosingForms by remember { mutableStateOf(false) }

    // Only while this is on screen is the Mac's download followed.
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    DisposableEffect(lifecycle) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) state.watchMacDownload()
            if (event == Lifecycle.Event.ON_PAUSE) state.stopWatchingMacDownload(keepingRequested = true)
        }
        lifecycle.addObserver(observer)
        onDispose {
            lifecycle.removeObserver(observer)
            state.stopWatchingMacDownload(keepingRequested = true)
        }
    }

    val faint = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f)
    SettingsHeader("Paired Mac")
    Card(Modifier.fillMaxWidth()) {
        Row(Modifier.padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Filled.Computer, null, Modifier.padding(end = 12.dp))
            Column(Modifier.weight(1f)) {
                Text(pairing.macName, style = MaterialTheme.typography.titleMedium)
                Text("${pairing.host}:${pairing.port}", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
            }
            OutlinedButton(onClick = { confirmUnpair = true }, enabled = !state.isSyncing) { Text("Unpair") }
        }
    }

    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Button(onClick = { state.syncInBackground() }, enabled = !state.isSyncing) {
                    Icon(Icons.Filled.Sync, null, Modifier.padding(end = 8.dp).size(18.dp))
                    Text(if (state.isSyncing) "Syncing…" else "Sync")
                }
                if (!state.isSyncing) {
                    val last = state.lastSyncAt?.let { " · ${relativeDate(it.toEpochMilli())}" } ?: ""
                    state.lastSyncMessage?.let { Text(it + last, Modifier.weight(1f), style = MaterialTheme.typography.bodySmall, color = faint, textAlign = TextAlign.End) }
                }
            }
            if (state.isSyncing) {
                val progress = state.syncProgress
                if (progress != null) LinearProgressIndicator(progress = { progress }, Modifier.fillMaxWidth())
                else LinearProgressIndicator(Modifier.fillMaxWidth())
                Text(state.syncStep, style = MaterialTheme.typography.bodySmall)
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("Sync:", Modifier.weight(1f))
                Box {
                    TextButton(onClick = { choosingForms = true }) {
                        Text("${state.syncForms.label} Videos")
                        Icon(Icons.Filled.ArrowDropDown, null)
                    }
                    DropdownMenu(expanded = choosingForms, onDismissRequest = { choosingForms = false }) {
                        SyncForms.entries.forEach { option ->
                            DropdownMenuItem(text = { Text("${option.label} Videos") }, onClick = {
                                choosingForms = false
                                state.updateSyncForms(option)
                            })
                        }
                    }
                }
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("Sync automatically", Modifier.weight(1f))
                Switch(checked = state.autoSync, onCheckedChange = state::updateAutoSync)
            }
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                OutlinedButton(onClick = state::forceDownload, enabled = !state.isRequestingDownload && state.macDownload == null) {
                    Icon(Icons.Filled.Download, null, Modifier.padding(end = 8.dp).size(18.dp))
                    Text("Update Mac")
                }
                Text(
                    state.lastMacDownloadAt?.let { "Last: ${relativeDate(it.toEpochMilli())}" } ?: "",
                    Modifier.weight(1f), style = MaterialTheme.typography.bodySmall, color = faint, textAlign = TextAlign.End,
                )
                MacDownloadIndicator()
            }
            state.macDownload?.let { download ->
                Text(
                    buildList {
                        add("Downloading on your Mac")
                        if (download.done != null && download.total != null) add("${download.done} of ${download.total}")
                        if (download.current.isNotEmpty()) add(download.current.joinToString(", "))
                    }.joinToString(" · "),
                    style = MaterialTheme.typography.bodySmall, maxLines = 2, overflow = TextOverflow.Ellipsis,
                )
            }
            state.forceDownloadMessage?.let { Text(it, style = MaterialTheme.typography.bodySmall) }
        }
    }

    HorizontalDivider()
    UsbHelp()
    HorizontalDivider()

    OutlinedButton(onClick = { state.addingCreator = true }, modifier = Modifier.fillMaxWidth()) {
        Icon(Icons.Filled.PersonAdd, null, Modifier.padding(end = 8.dp).size(18.dp))
        Text("Add Creator")
    }

    if (confirmUnpair) {
        AlertDialog(
            onDismissRequest = { confirmUnpair = false },
            title = { Text("Unpair from ${pairing.macName}?") },
            text = { Text("Its videos and your watched history, Watch Later and bookmarks are removed from this phone. Your Mac keeps its copies, so pairing again brings them back. You can also remove this phone from the Mac's list.") },
            confirmButton = { TextButton(onClick = { state.unpair(); confirmUnpair = false }) { Text("Unpair") } },
            dismissButton = { TextButton(onClick = { confirmUnpair = false }) { Text("Cancel") } },
        )
    }
}

/** The right of the Force Download row: a ring that fills as the Mac downloads, then a checkmark until the next sync. */
@Composable
private fun MacDownloadIndicator() {
    val state = LocalContext.current.curated.state
    val stage = when {
        state.macDownloadFinished -> 2
        state.macDownload != null || state.isRequestingDownload -> 1
        else -> 0
    }
    val progress by animateFloatAsState((state.macDownload?.progress ?: 0.0).toFloat(), label = "macDownload")
    Crossfade(stage, Modifier.padding(start = 8.dp).size(24.dp), label = "macDownloadStage") { shown ->
        Box(Modifier.size(24.dp), contentAlignment = Alignment.Center) {
            when (shown) {
                2 -> Icon(Icons.Filled.CheckCircle, "Download finished on your Mac", Modifier.size(24.dp), tint = Color(0xFF34A853))
                1 -> {
                    CircularProgressIndicator(progress = { progress }, Modifier.size(24.dp), strokeWidth = 2.5.dp, color = MaterialTheme.colorScheme.primary)
                    Icon(Icons.Filled.ArrowDownward, "Downloading on your Mac", Modifier.size(13.dp), tint = MaterialTheme.colorScheme.primary)
                }
            }
        }
    }
}

@Composable
private fun UsbHelp() {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text("Sync over USB", style = MaterialTheme.typography.titleSmall)
        Text(
            "Turn on USB debugging on this phone and plug it into your Mac. With USB Sync on in the Mac's Phone Sync " +
                "panel (it's on whenever Curated starts), sync goes over the cable automatically. The Mac needs adb " +
                "from Android's platform tools.",
            style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f),
        )
    }
}

/** A Mac's address as typed: "host" or "host:port". */
fun parseMacAddress(text: String): Pair<String, Int>? {
    val trimmed = text.removePrefix("http://").trimEnd('/')
    if (trimmed.isEmpty()) return null
    val colon = trimmed.lastIndexOf(':')
    if (colon > 0 && trimmed.count { it == ':' } == 1) {
        val port = trimmed.substring(colon + 1).toIntOrNull() ?: return null
        return trimmed.substring(0, colon) to port
    }
    return trimmed to SyncClient.DEFAULT_PORT
}
