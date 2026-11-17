package local.curated.phone

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.PersonAdd
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch

/** Suggested creators' dashed avatar ring, as on the Mac. */
val SuggestedPink = Color(0xFFFF8EEA)

/** A dashed pink ring around a suggested creator's avatar, in place of the platform's. */
fun Modifier.suggestedRing(size: Dp): Modifier = drawWithContent {
    drawContent()
    val width = maxOf(2.dp, size / 18).toPx()
    val dash = maxOf(3.dp, size / 9).toPx()
    val gap = maxOf(2.5.dp, size / 14).toPx()
    drawCircle(
        SuggestedPink, radius = this.size.minDimension / 2 - width / 2,
        style = Stroke(width, cap = androidx.compose.ui.graphics.StrokeCap.Round, pathEffect = PathEffect.dashPathEffect(floatArrayOf(dash, gap))),
    )
}

/**
 * Shown with a suggested creator's video: adds them to the Mac's creators in a category (FollowSuggestedDialog).
 * Once asked for while the Mac was out of reach, it says it's waiting for the next sync.
 */
@Composable
fun SuggestedFollowButton(creatorKey: String) {
    if (!isSuggestedKey(creatorKey)) return
    val state = LocalContext.current.curated.state
    if (state.isFollowPending(creatorKey)) {
        Row(
            Modifier.background(Color.White.copy(alpha = 0.18f), CircleShape).padding(horizontal = 10.dp, vertical = 6.dp)
                .semantics { contentDescription = "Will be added to your creators at the next sync" },
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            Icon(Icons.Filled.Schedule, null, tint = Color.White, modifier = Modifier.size(14.dp))
            Text("Next sync", color = Color.White, style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.SemiBold)
        }
    } else {
        Row(
            Modifier.background(SuggestedPink, CircleShape).clickable { state.followingSuggested = creatorKey }
                .padding(horizontal = 10.dp, vertical = 6.dp)
                .semantics { contentDescription = "Add to your creators" },
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            Icon(Icons.Filled.PersonAdd, null, tint = Color.Black, modifier = Modifier.size(16.dp))
            Text("Add", color = Color.Black, style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.Bold)
        }
    }
}

/** Long-pressing a suggested creator: add them to the Mac's creators. */
@Composable
fun AddToCreatorsItem(library: CreatorLibrary, dismiss: () -> Unit) {
    val state = LocalContext.current.curated.state
    if (!library.creator.isSuggested) return
    DropdownMenuItem(
        text = { Text("Add to Creators…") },
        onClick = {
            dismiss()
            state.followingSuggested = library.id
        },
    )
}

/** Adding a suggested creator to the Mac's creators: who, and which category. */
@Composable
fun FollowSuggestedDialog(creatorKey: String, onDismiss: () -> Unit) {
    val state = LocalContext.current.curated.state
    val scope = rememberCoroutineScope()
    val library = state.library(creatorKey)
    var category by remember { mutableStateOf<String?>(null) }
    var sending by remember { mutableStateOf(false) }
    var message by remember { mutableStateOf<String?>(null) }
    AlertDialog(
        onDismissRequest = onDismiss,
        icon = { Avatar(library, creatorKey, 56.dp) },
        title = { Text("Add ${library?.creator?.displayName ?: "@${creatorHandle(creatorKey)}"}") },
        text = {
            Column(Modifier.verticalScroll(rememberScrollState())) {
                val done = message
                if (done != null) {
                    Text(done)
                } else {
                    Text(
                        "Your Mac adds them to your creators and downloads their recent videos. Pick a category:",
                        style = MaterialTheme.typography.bodyMedium,
                    )
                    val choices = listOf<Pair<String?, String>>(null to "None") + state.categories.map { it.id to it.name }
                    choices.forEach { (id, name) ->
                        Row(
                            Modifier.fillMaxWidth().selectable(selected = category == id) { category = id }.padding(vertical = 2.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            RadioButton(selected = category == id, onClick = { category = id })
                            Text(name)
                        }
                    }
                }
            }
        },
        confirmButton = {
            when {
                message != null -> TextButton(onClick = onDismiss) { Text("Done") }
                sending -> CircularProgressIndicator(Modifier.size(24.dp), strokeWidth = 2.dp)
                else -> TextButton(onClick = {
                    sending = true
                    scope.launch {
                        message = state.followSuggested(creatorKey, category)
                        sending = false
                    }
                }) { Text("Add") }
            }
        },
        dismissButton = { if (message == null) TextButton(onClick = onDismiss) { Text("Cancel") } },
    )
}
