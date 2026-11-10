package local.curated.phone

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.LruCache
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.time.Instant

// Asking the Mac for things it does: adding a creator, and downloading a creator's older long videos. The phone never
// talks to YouTube or TikTok; the Mac checks what's asked and says how it went.

/** The add-creator form, as the Mac describes it (`GET /creators/form`). Every value is a string. */
data class CreatorForm(val version: Int, val fields: List<Field>) {
    data class Choice(val value: String, val label: String)

    data class Condition(val field: String, val equals: List<String>?, val matches: String?, val negate: Boolean) {
        fun holds(values: Map<String, String>): Boolean {
            val value = values[field].orEmpty()
            val result = when {
                equals != null -> value in equals
                matches != null -> Regex(matches, RegexOption.IGNORE_CASE).containsMatchIn(value)
                else -> true
            }
            return if (negate) !result else result
        }
    }

    data class Field(
        val key: String, val type: String, val label: String, val detail: String?, val placeholder: String?, val required: Boolean,
        val choices: List<Choice>, val default: String, val showIf: List<List<Condition>>?,
    ) {
        val isKnownType: Boolean get() = type in listOf("text", "choice", "toggle", "number")

        fun isShown(values: Map<String, String>): Boolean = showIf?.any { group -> group.all { it.holds(values) } } ?: true
    }

    companion object {
        fun fromJson(json: JSONObject) = CreatorForm(
            json.getInt("version"),
            json.getJSONArray("fields").objects().map { field ->
                Field(
                    field.getString("key"), field.getString("type"), field.getString("label"),
                    field.optString("detail").ifEmpty { null }, field.optString("placeholder").ifEmpty { null }, field.optBoolean("required"),
                    field.optJSONArray("choices").objects().map { Choice(it.getString("value"), it.getString("label")) },
                    field.optString("default"),
                    field.optJSONArray("showIf")?.let { groups ->
                        (0 until groups.length()).map { i ->
                            groups.getJSONArray(i).objects().map { c ->
                                Condition(
                                    c.getString("field"),
                                    c.optJSONArray("equals")?.let { a -> (0 until a.length()).map(a::getString) },
                                    c.optString("matches").ifEmpty { null }, c.optBoolean("negate"),
                                )
                            }
                        }
                    },
                )
            },
        )
    }
}

data class OlderVideo(val id: String, val title: String?, val date: Instant?, val duration: Double?)

/** What a Mac too old for these requests answers. */
private fun macMessage(e: Exception): String =
    if (e is SyncException && e.status == 404 && e.message?.contains("Not found") == true) "Update Curated on your Mac to do this from here."
    else e.message ?: "Something went wrong."

private const val UNREACHABLE = "Couldn't reach your Mac. Make sure Curated is open there with phone sync on."

/** A form drawn from what the Mac sent. Only the fields showing are sent back, and the Mac has the last word on them. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AddCreatorScreen(onBack: () -> Unit) {
    val state = LocalContext.current.curated.state
    val scope = rememberCoroutineScope()
    var form by remember { mutableStateOf<CreatorForm?>(null) }
    val values = remember { mutableStateMapOf<String, String>() }
    var loadError by remember { mutableStateOf<String?>(null) }
    var sending by remember { mutableStateOf(false) }
    var message by remember { mutableStateOf<String?>(null) }
    val fieldErrors = remember { mutableStateMapOf<String, String>() }
    var added by remember { mutableStateOf<String?>(null) }
    BackHandler(onBack = onBack)

    suspend fun load() {
        try {
            val client = state.macClient() ?: throw SyncException(UNREACHABLE)
            val loaded = withContext(Dispatchers.IO) { client.creatorForm() }
            if (loaded.fields.any { it.required && !it.isKnownType }) {
                loadError = "Update Curated on this phone to add creators from here."
                return
            }
            // What's been typed stays, if the form was fetched again.
            loaded.fields.forEach { if (it.key !in values) values[it.key] = it.default }
            form = loaded
            loadError = null
        } catch (e: Exception) {
            loadError = macMessage(e)
        }
    }
    LaunchedEffect(Unit) { load() }

    val shown = form?.fields.orEmpty().filter { it.isKnownType && it.isShown(values) }
    val canSend = !sending && form != null && shown.none { it.required && values[it.key].orEmpty().isBlank() }

    fun send() {
        val current = form ?: return
        scope.launch {
            sending = true
            message = null
            fieldErrors.clear()
            try {
                val client = state.macClient() ?: throw SyncException(UNREACHABLE)
                val sent = shown.associate { it.key to values[it.key].orEmpty() }
                val reply = withContext(Dispatchers.IO) { client.addCreator(current.version, sent) }
                if (reply.optBoolean("added")) {
                    added = reply.getString("message")
                } else {
                    val errors = reply.optJSONObject("fieldErrors")
                    errors?.keys()?.forEach { fieldErrors[it] = errors.getString(it) }
                    // Beside the field where there is one.
                    if (fieldErrors.isEmpty() || fieldErrors.keys.any { key -> shown.none { it.key == key } }) message = reply.getString("message")
                    if (reply.optBoolean("formChanged")) load()
                }
            } catch (e: Exception) {
                message = macMessage(e)
            }
            sending = false
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Add Creator") },
                navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back") } },
                actions = {
                    if (sending) CircularProgressIndicator(Modifier.padding(end = 16.dp).size(22.dp), strokeWidth = 2.dp)
                    else TextButton(onClick = ::send, enabled = canSend) { Text("Add") }
                },
            )
        },
    ) { padding ->
        when {
            loadError != null -> Box(Modifier.fillMaxSize().padding(padding).padding(24.dp), contentAlignment = Alignment.Center) {
                Text(loadError.orEmpty(), textAlign = TextAlign.Center)
            }
            form == null -> Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
            else -> Column(
                Modifier.fillMaxSize().padding(padding).verticalScroll(rememberScrollState()).padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                message?.let { Text(it, color = MaterialTheme.colorScheme.error) }
                shown.forEach { field ->
                    FormField(field, values[field.key].orEmpty(), fieldErrors[field.key]) {
                        values[field.key] = it
                        fieldErrors.remove(field.key)
                        message = null
                    }
                }
            }
        }
    }
    added?.let {
        AlertDialog(
            onDismissRequest = onBack,
            title = { Text("Added") }, text = { Text(it) },
            confirmButton = { TextButton(onClick = onBack) { Text("OK") } },
        )
    }
}

@Composable
private fun FormField(field: CreatorForm.Field, value: String, problem: String?, onChange: (String) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        when (field.type) {
            "toggle" -> Row(verticalAlignment = Alignment.CenterVertically) {
                Text(field.label, Modifier.weight(1f))
                Switch(checked = value == "true", onCheckedChange = { onChange(if (it) "true" else "false") })
            }
            "choice" -> {
                Text(field.label)
                Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    field.choices.forEach { choice ->
                        FilterChip(selected = choice.value == value, onClick = { onChange(choice.value) }, label = { Text(choice.label) })
                    }
                }
            }
            "number" -> OutlinedTextField(
                value, { onChange(it.filter(Char::isDigit)) }, Modifier.fillMaxWidth(), label = { Text(field.label) }, singleLine = true,
                isError = problem != null, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
            )
            else -> OutlinedTextField(
                value, onChange, Modifier.fillMaxWidth(), label = { Text(field.label) }, singleLine = true, isError = problem != null,
                placeholder = field.placeholder?.let { { Text(it) } }, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri),
            )
        }
        problem?.let { Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall) }
        field.detail?.let {
            Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
        }
    }
}

private const val OLDER_PER_LOAD = 40
private val OLDER_HEIGHTS = listOf(1080, 720, 480, 144)

/**
 * A creator's long videos on YouTube that aren't downloaded yet, listed by the Mac. Shows 40 at a time, and thumbnails load
 * as they come on screen, through the Mac. Picks are sent to the Mac, which downloads them.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun OlderVideosScreen(target: OlderVideosTarget, onBack: () -> Unit) {
    val state = LocalContext.current.curated.state
    val scope = rememberCoroutineScope()
    var client by remember { mutableStateOf<SyncClient?>(null) }
    val videos = remember { mutableStateListOf<OlderVideo>() }
    var limit by remember { mutableIntStateOf(OLDER_PER_LOAD) }
    var loading by remember { mutableStateOf(true) }
    var error by remember { mutableStateOf<String?>(null) }
    val picked = remember { mutableStateMapOf<String, Boolean>() }
    val skipped = remember { mutableStateMapOf<String, Boolean>() }
    val heights = remember { mutableStateMapOf<String, Int>() }
    var sending by remember { mutableStateOf(false) }
    var result by remember { mutableStateOf<String?>(null) }
    var finished by remember { mutableStateOf(false) }
    BackHandler(onBack = onBack)

    // Leaving cancels this, which closes the connection and stops the Mac's listing.
    LaunchedEffect(target.id) {
        try {
            val connected = state.macClient() ?: throw SyncException(UNREACHABLE)
            client = connected
            connected.followOlderVideos(target.id) { event ->
                val seen = videos.map { it.id }.toSet()
                videos += event.videos.filter { it.id !in seen }
                event.error?.let { error = it }
            }
        } catch (e: kotlinx.coroutines.CancellationException) {
            throw e
        } catch (e: Exception) {
            error = macMessage(e)
        }
        loading = false
    }

    fun send() {
        val connected = client ?: return
        scope.launch {
            sending = true
            try {
                val reply = withContext(Dispatchers.IO) {
                    connected.requestOlderVideos(target.id, picked.keys.toList(), skipped.keys.toList(), heights.filterKeys { it in picked })
                }
                finished = reply.optBoolean("ok")
                result = reply.getString("message")
                if (reply.optBoolean("started")) {
                    state.followRequestedVideos(picked.keys.toList())
                    val count = picked.size
                    result = if (count == 1) "Your Mac is downloading 1 video. It'll come here when it's done, or the next time you open Curated."
                    else "Your Mac is downloading $count videos. They'll come here when it's done, or the next time you open Curated."
                }
            } catch (e: Exception) {
                finished = false
                result = macMessage(e)
            }
            sending = false
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(target.name, maxLines = 1, overflow = TextOverflow.Ellipsis) },
                navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back") } },
                actions = {
                    if (sending) {
                        CircularProgressIndicator(Modifier.padding(end = 16.dp).size(22.dp), strokeWidth = 2.dp)
                    } else {
                        TextButton(onClick = ::send, enabled = picked.isNotEmpty() || skipped.isNotEmpty()) {
                            Text(if (picked.isEmpty() && skipped.isNotEmpty()) "Skip ${skipped.size}" else if (picked.isEmpty()) "Download" else "Download ${picked.size}")
                        }
                    }
                },
            )
        },
    ) { padding ->
        when {
            videos.isEmpty() && !loading -> Box(Modifier.fillMaxSize().padding(padding).padding(24.dp), contentAlignment = Alignment.Center) {
                Text(error ?: "Every long video from this creator is already downloaded, watched or skipped.", textAlign = TextAlign.Center)
            }
            videos.isEmpty() -> Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
            else -> LazyVerticalGrid(
                // Lazy, so a thumbnail is only asked for near the screen.
                GridCells.Adaptive(minSize = 165.dp), Modifier.padding(padding),
                contentPadding = PaddingValues(12.dp),
                horizontalArrangement = Arrangement.spacedBy(12.dp), verticalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                item(span = { GridItemSpan(maxLineSpan) }) {
                    val shownCount = minOf(limit, videos.size)
                    val parts = buildList {
                        add((if (videos.size > shownCount) "$shownCount of ${videos.size}" else "$shownCount") + " video" + (if (videos.size == 1) "" else "s") + if (loading) "…" else "")
                        if (picked.isNotEmpty()) add("${picked.size} selected")
                        if (skipped.isNotEmpty()) add("${skipped.size} to skip")
                    }
                    Text(parts.joinToString(" · "), style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
                }
                items(videos.take(limit), key = { it.id }) { video ->
                    OlderTile(
                        video, client, video.id in picked, video.id in skipped, heights[video.id],
                        onTap = {
                            skipped.remove(video.id)
                            if (video.id in picked) picked.remove(video.id) else picked[video.id] = true
                        },
                        onSkip = {
                            if (video.id in skipped) {
                                skipped.remove(video.id)
                            } else {
                                skipped[video.id] = true
                                picked.remove(video.id)
                            }
                        },
                        onHeight = { if (it == null) heights.remove(video.id) else heights[video.id] = it },
                    )
                }
                item(span = { GridItemSpan(maxLineSpan) }) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        if (videos.size > limit) {
                            TextButton(onClick = { limit += OLDER_PER_LOAD }) { Text("Load More") }
                        } else if (loading) {
                            CircularProgressIndicator(Modifier.size(22.dp), strokeWidth = 2.dp)
                        }
                        Text(
                            "Tap to pick; press and hold to skip one or change its resolution. Videos you pick come first until you've watched them, and stay however old they are.",
                            style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f),
                        )
                    }
                }
            }
        }
    }
    result?.let {
        AlertDialog(
            onDismissRequest = { result = null; if (finished) onBack() },
            title = { Text(if (finished) "Sent to your Mac" else "Not downloaded") }, text = { Text(it) },
            confirmButton = { TextButton(onClick = { result = null; if (finished) onBack() }) { Text("OK") } },
        )
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun OlderTile(
    video: OlderVideo, client: SyncClient?, isPicked: Boolean, isSkipped: Boolean, height: Int?,
    onTap: () -> Unit, onSkip: () -> Unit, onHeight: (Int?) -> Unit,
) {
    var menu by remember { mutableStateOf(false) }
    val shape = RoundedCornerShape(10.dp)
    Column(
        Modifier.alpha(if (isSkipped) 0.45f else 1f).combinedClickable(onClick = onTap, onLongClick = { menu = true }),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Box(
            Modifier.fillMaxWidth().aspectRatio(16f / 9f).clip(shape).background(MaterialTheme.colorScheme.surfaceVariant)
                .then(if (isPicked) Modifier.border(3.dp, MaterialTheme.colorScheme.primary, shape) else Modifier),
        ) {
            val image by produceState<Bitmap?>(olderThumbnails.get(video.id), video.id, client) {
                if (value == null && client != null) {
                    value = withContext(Dispatchers.IO) {
                        runCatching { client.olderThumbnail(video.id).let { BitmapFactory.decodeByteArray(it, 0, it.size) } }.getOrNull()
                            ?.also { olderThumbnails.put(video.id, it) }
                    }
                }
            }
            image?.let { Image(it.asImageBitmap(), null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop) }
            if (isPicked) {
                Icon(Icons.Filled.CheckCircle, "Selected", Modifier.align(Alignment.TopEnd).padding(6.dp), tint = MaterialTheme.colorScheme.primary)
            }
            if (isSkipped) {
                Text(
                    "Skip", Modifier.align(Alignment.Center).background(Color.Black.copy(alpha = 0.7f), RoundedCornerShape(50)).padding(horizontal = 10.dp, vertical = 3.dp),
                    color = Color.White, style = MaterialTheme.typography.labelMedium,
                )
            }
            DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                DropdownMenuItem(text = { Text(if (isSkipped) "Don't skip" else "Skip and mark as watched") }, onClick = { menu = false; onSkip() })
                HorizontalDivider()
                DropdownMenuItem(text = { Text("Creator's resolution") }, onClick = { menu = false; onHeight(null) })
                DropdownMenuItem(text = { Text("Best") }, onClick = { menu = false; onHeight(0) })
                OLDER_HEIGHTS.forEach { option ->
                    DropdownMenuItem(text = { Text("Up to ${option}p") }, onClick = { menu = false; onHeight(option) })
                }
            }
        }
        Text(video.title ?: video.id, style = MaterialTheme.typography.bodySmall, fontWeight = FontWeight.Medium, maxLines = 2, minLines = 2, overflow = TextOverflow.Ellipsis)
        val line = listOfNotNull(
            video.date?.let { relativeDate(it.toEpochMilli()) }, video.duration?.let { formatLength(it) },
            height?.let { if (it == 0) "Best" else "${it}p" },
        ).joinToString(" · ")
        Text(
            line, style = MaterialTheme.typography.labelSmall, maxLines = 1, overflow = TextOverflow.Ellipsis,
            color = if (height != null) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f),
        )
    }
}

/** Thumbnails kept in memory for a while, by video id. */
private val olderThumbnails = LruCache<String, Bitmap>(120)
