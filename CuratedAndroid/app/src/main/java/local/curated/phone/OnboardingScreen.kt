package local.curated.phone

import android.os.Build
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.expandVertically
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.isImeVisible
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowDownward
import androidx.compose.material.icons.filled.Cable
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Laptop
import androidx.compose.material.icons.filled.LaptopMac
import androidx.compose.material.icons.filled.LockOpen
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.IntOffset
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.roundToInt
import kotlin.math.sin

/** The app's blue, as a fixed color for gradients. */
val CuratedBlue = Accent

private enum class OnboardingPhase { Connect, Pairing, Syncing, Done }

/**
 * The first thing an unpaired phone sees: the logo over slowly drifting color, an orb that pulses like AirDrop while
 * it looks for Curated on the network, and a glass card to pair (a found Mac, its address, or USB, and the 6-digit
 * code). After pairing, the orb turns into the first sync's progress ring, and the screen fades away when it's done.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun OnboardingScreen(onFinish: () -> Unit) {
    val context = LocalContext.current
    val state = context.curated.state
    val scope = rememberCoroutineScope()
    val focus = LocalFocusManager.current

    var phase by remember { mutableStateOf(OnboardingPhase.Connect) }
    /** Set when the sync brought nothing down (an empty Mac, or an error); the screen waits for Continue. */
    var doneMessage by remember { mutableStateOf<String?>(null) }
    var found by remember { mutableStateOf(emptyList<FoundMac>()) }
    var selected by remember { mutableStateOf<FoundMac?>(null) }
    var showAddress by remember { mutableStateOf(false) }
    var address by remember { mutableStateOf("") }
    var code by remember { mutableStateOf("") }
    var error by remember { mutableStateOf<String?>(null) }
    val shake = remember { Animatable(0f) }
    var appeared by remember { mutableStateOf(false) }
    val entrance by animateFloatAsState(if (appeared) 1f else 0f, spring(dampingRatio = 0.7f, stiffness = Spring.StiffnessVeryLow))

    // Search until a Mac turns up, then look again every few seconds for others.
    LaunchedEffect(Unit) {
        appeared = true
        while (state.pairing == null) {
            val macs = Discovery.find(context)
            found = macs
            if (selected == null || selected !in macs) selected = macs.firstOrNull()
            delay(if (macs.isEmpty()) 1500 else 6000)
        }
    }

    val target: Pair<String, Int>? = if (showAddress) parseMacAddress(address) else selected?.let { it.host to it.port }
    val canPair = target != null && code.length == 6 && phase == OnboardingPhase.Connect

    fun pair() {
        val (host, port) = target ?: return
        focus.clearFocus()
        scope.launch {
            error = null
            phase = OnboardingPhase.Pairing
            val failure = state.pair(host, port, code)
            if (failure != null) {
                error = failure
                phase = OnboardingPhase.Connect
                // Cleared for another try; it would otherwise start again with the same code.
                code = ""
                for (x in listOf(18f, -16f, 12f, -8f, 4f, 0f)) shake.animateTo(x, tween(55))
                return@launch
            }
            phase = OnboardingPhase.Syncing
            val message = state.sync()
            doneMessage = if (state.libraries.isEmpty()) message else null
            phase = OnboardingPhase.Done
            if (doneMessage == null) {
                delay(1400)
                onFinish()
            }
        }
    }

    // No Pair button: the last digit starts pairing, like a verification code (or a Mac turning up once it's in).
    LaunchedEffect(canPair) { if (canPair) pair() }

    // Not on a Material surface, so text would default to black; use the theme's text color instead.
    CompositionLocalProvider(LocalContentColor provides MaterialTheme.colorScheme.onSurface) {
        Box(Modifier.fillMaxSize()) {
            AuroraBackground()
            // The safe drawing area already leaves room for the keyboard; padding for it again doubled the gap.
            BoxWithConstraints(Modifier.fillMaxSize().safeDrawingPadding()) {
                // While typing, the logo and orb step aside so the whole card (code boxes and Pair) sits above the keyboard.
                val typing = WindowInsets.isImeVisible
                // The orb gets what's left after the header and card (measured), between 140 and 260 dp, so everything
                // fits on a shorter screen instead of running off the bottom.
                val density = LocalDensity.current
                var headerHeight by remember { mutableStateOf(0.dp) }
                var cardHeight by remember { mutableStateOf(0.dp) }
                val orbSize = (maxHeight - 32.dp - 48.dp - headerHeight - cardHeight).coerceIn(140.dp, 260.dp)
                Column(
                    Modifier.fillMaxSize().verticalScroll(rememberScrollState()).heightIn(min = maxHeight).padding(horizontal = 20.dp, vertical = 16.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(24.dp, Alignment.CenterVertically),
                ) {
                    AnimatedVisibility(!typing, enter = expandVertically() + fadeIn(), exit = shrinkVertically() + fadeOut()) {
                        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(24.dp)) {
                            // Header: the logo and wordmark, settling in.
                            Column(
                                Modifier.alpha(entrance).offset { IntOffset(0, ((1 - entrance) * 40).roundToInt()) }
                                    .onSizeChanged { headerHeight = with(density) { it.height.toDp() } },
                                horizontalAlignment = Alignment.CenterHorizontally,
                                verticalArrangement = Arrangement.spacedBy(10.dp),
                            ) {
                                Image(
                                    painterResource(if (LocalDarkTheme.current) R.drawable.logo_dark else R.drawable.logo_light),
                                    contentDescription = "Curated", modifier = Modifier.height(54.dp),
                                )
                                Text(
                                    "Your Mac picks the videos.\nThis phone plays them.",
                                    style = MaterialTheme.typography.titleMedium, textAlign = TextAlign.Center,
                                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.65f),
                                )
                            }

                            DiscoveryOrb(
                                mode = when (phase) {
                                    OnboardingPhase.Connect -> if (found.isEmpty()) OrbMode.Searching else OrbMode.Found
                                    OnboardingPhase.Pairing -> OrbMode.Working
                                    OnboardingPhase.Syncing -> OrbMode.Syncing
                                    OnboardingPhase.Done -> OrbMode.Done
                                },
                                progress = state.syncProgress,
                                size = orbSize,
                                modifier = Modifier.alpha(entrance).scale(0.8f + 0.2f * entrance),
                            )
                        }
                    }

                    GlassCard(
                        Modifier.widthIn(max = 460.dp).fillMaxWidth().alpha(entrance).offset { IntOffset(0, ((1 - entrance) * 80).roundToInt()) }
                            .onSizeChanged { cardHeight = with(density) { it.height.toDp() } },
                    ) {
                        when (phase) {
                            OnboardingPhase.Connect, OnboardingPhase.Pairing -> {
                                Text("Connect to your Mac", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
                                Text(
                                    buildAnnotatedString {
                                        append("On your Mac, open ")
                                        withStyle(SpanStyle(fontWeight = FontWeight.SemiBold)) { append("Curated › Phone Sync › Pair a Phone") }
                                        append(", then enter the code it shows.")
                                    },
                                    style = MaterialTheme.typography.bodyMedium,
                                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.65f),
                                )
                                MacPicker(
                                    found = found, selected = selected.takeIf { !showAddress },
                                    usbSelected = showAddress && address.startsWith("127.0.0.1"),
                                    onSelect = { selected = it; showAddress = false },
                                    onUsb = { showAddress = true; address = "127.0.0.1:${SyncClient.DEFAULT_PORT}" },
                                )
                                AnimatedVisibility(showAddress, enter = expandVertically() + fadeIn(), exit = shrinkVertically() + fadeOut()) {
                                    PillField(address, { address = it.trim() }, "192.168.1.20:8765", KeyboardType.Uri)
                                }
                                TextButton(onClick = { showAddress = !showAddress }, contentPadding = PaddingValues(0.dp)) {
                                    Text(
                                        if (showAddress) "Pick a Mac on this Wi-Fi instead" else "Enter your Mac's address instead",
                                        color = CuratedBlue, fontWeight = FontWeight.SemiBold, style = MaterialTheme.typography.labelLarge,
                                    )
                                }
                                Text(
                                    "Pairing code", style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.SemiBold,
                                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f),
                                )
                                CodeBoxes(code, { code = it.filter(Char::isDigit).take(6) }, Modifier.offset { IntOffset(shake.value.roundToInt(), 0) })
                                if (phase == OnboardingPhase.Pairing) {
                                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                        CircularProgressIndicator(Modifier.size(14.dp), strokeWidth = 2.dp, color = CuratedBlue)
                                        Text(
                                            "Pairing with ${selected?.takeIf { !showAddress }?.name ?: "your Mac"}…",
                                            style = MaterialTheme.typography.bodySmall,
                                            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.65f),
                                        )
                                    }
                                } else {
                                    error?.let { Text(it, color = LogoRed, style = MaterialTheme.typography.bodySmall) }
                                }
                            }
                            OnboardingPhase.Syncing -> {
                                Text("Syncing with ${state.pairing?.macName ?: "your Mac"}", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
                                Text(
                                    state.syncStep.ifEmpty { "Getting ready…" }, style = MaterialTheme.typography.bodyMedium,
                                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.65f),
                                )
                                state.syncProgress?.let { Text("${(it * 100).roundToInt()}%", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold) }
                            }
                            OnboardingPhase.Done -> {
                                val message = doneMessage
                                Text(
                                    if (message == null) "You're all set" else "Paired with ${state.pairing?.macName ?: "your Mac"}",
                                    style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold,
                                )
                                if (message == null) {
                                    Text("Your videos are ready.", color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.65f))
                                } else {
                                    Text(message, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.65f))
                                    GradientButton("Continue", enabled = true, busy = false, onClick = onFinish)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

/**
 * Slow, blurred color drifting behind everything: the logo's red and cyan and the app's blue, on near-black or
 * near-white. Behind Home it's fainter (`intensity`) and redrawn less often (`frameIntervalMs`), since it moves slowly
 * and stays on screen.
 */
@Composable
fun AuroraBackground(
    intensity: Float = 1f,
    frameIntervalMs: Long? = null,
    palette: AuroraPalette = LocalContext.current.curated.state.palette,
) {
    val dark = LocalDarkTheme.current
    val time by produceState(0f) {
        val start = withFrameNanos { it }
        while (true) {
            withFrameNanos { value = (it - start) / 1_000_000_000f }
            frameIntervalMs?.let { delay(it) }
        }
    }
    val base = if (dark) palette.darkBase else palette.lightBase
    val alpha = AuroraPalette.strength(dark) * intensity
    val colors = palette.blobs.map { (color, strength) -> AuroraPalette.shade(color, dark) to strength }
    Box(Modifier.fillMaxSize().background(base)) {
        Canvas(Modifier.fillMaxSize().then(if (Build.VERSION.SDK_INT >= 31) Modifier.blur(40.dp) else Modifier)) {
            val size = max(size.width, size.height)
            fun blob(color: Color, a: Float, x: Float, y: Float, diameter: Float) {
                val center = Offset(x * this.size.width, y * this.size.height)
                drawCircle(
                    Brush.radialGradient(listOf(color.copy(alpha = a), color.copy(alpha = 0f)), center, diameter / 2),
                    radius = diameter / 2, center = center,
                )
            }
            val t = time
            blob(colors[0].first, alpha * colors[0].second, 0.22f + 0.16f * sin(t / 7), 0.2f + 0.1f * cos(t / 9), size * 0.75f)
            blob(colors[1].first, alpha * colors[1].second, 0.82f + 0.14f * cos(t / 8), 0.38f + 0.14f * sin(t / 6.5f), size * 0.7f)
            blob(colors[2].first, alpha * colors[2].second, 0.45f + 0.2f * sin(t / 11), 0.82f + 0.1f * cos(t / 7.5f), size * 0.85f)
            blob(colors[3].first, alpha * colors[3].second, 0.65f + 0.2f * cos(t / 13), 0.62f + 0.16f * sin(t / 10), size * 0.6f)
        }
    }
}

private enum class OrbMode { Searching, Found, Working, Syncing, Done }

/**
 * A glass orb with a Mac in it. Searching, rings pulse out of it like AirDrop; found, they slow down; pairing and
 * syncing, a gradient ring spins or fills around it; done, a checkmark.
 */
@Composable
private fun DiscoveryOrb(mode: OrbMode, progress: Float?, size: Dp, modifier: Modifier = Modifier) {
    val dark = LocalDarkTheme.current
    val time by produceState(0f) {
        val start = withFrameNanos { it }
        while (true) withFrameNanos { value = (it - start) / 1_000_000_000f }
    }
    val glow by animateColorAsState(
        when (mode) {
            OrbMode.Done -> LogoCyan
            OrbMode.Working, OrbMode.Syncing -> CuratedBlue
            else -> LogoRed
        },
        tween(600), label = "glow",
    )
    val shownProgress by animateFloatAsState(progress ?: 0.3f, label = "progress")
    // Drawn at 260 dp and scaled down to `size` on shorter screens.
    Box(modifier.size(size), contentAlignment = Alignment.Center) {
        Box(Modifier.requiredSize(260.dp).scale(size / 260.dp), contentAlignment = Alignment.Center) {
            Canvas(Modifier.fillMaxSize()) {
                val center = this.center
                drawCircle(Brush.radialGradient(listOf(glow.copy(alpha = 0.5f), Color.Transparent), center, 120.dp.toPx()), 120.dp.toPx(), center)
                val core = 50.dp.toPx()
                if (mode == OrbMode.Searching || mode == OrbMode.Found) {
                    val period = if (mode == OrbMode.Searching) 2.4f else 4.2f
                    for (i in 0 until 3) {
                        val phase = ((time / period) + i / 3f) % 1f
                        drawCircle(
                            Brush.linearGradient(listOf(LogoRed, LogoCyan)),
                            radius = core * (1 + phase * 1.3f), center = center,
                            alpha = (1 - phase) * 0.85f, style = Stroke(1.5.dp.toPx()),
                        )
                    }
                }
                if (mode == OrbMode.Working || mode == OrbMode.Syncing) {
                    val r = 62.dp.toPx()
                    val stroke = 5.dp.toPx()
                    drawCircle((if (dark) Color.White else Color.Black).copy(alpha = 0.1f), r, center, style = Stroke(stroke))
                    val determinate = mode == OrbMode.Syncing && progress != null
                    val sweep = 360f * if (mode == OrbMode.Syncing) max(0.04f, shownProgress) else 0.3f
                    rotate(if (determinate) -90f else time * 260f, center) {
                        drawArc(
                            Brush.sweepGradient(listOf(LogoRed, LogoCyan, CuratedBlue, LogoRed), center),
                            startAngle = 0f, sweepAngle = sweep, useCenter = false,
                            topLeft = Offset(center.x - r, center.y - r), size = Size(r * 2, r * 2),
                            style = Stroke(stroke, cap = StrokeCap.Round),
                        )
                    }
                }
            }
            val breathe = 1f + 0.03f * sin(time * 2)
            Box(
                Modifier.size(100.dp).scale(breathe).clip(CircleShape)
                    .background((if (dark) Color.White else Color.White).copy(alpha = if (dark) 0.12f else 0.55f))
                    .border(1.dp, (if (dark) Color.White else Color.Black).copy(alpha = 0.12f), CircleShape),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    when (mode) {
                        OrbMode.Searching -> Icons.Filled.Laptop
                        OrbMode.Found -> Icons.Filled.LaptopMac
                        OrbMode.Working -> Icons.Filled.LockOpen
                        OrbMode.Syncing -> Icons.Filled.ArrowDownward
                        OrbMode.Done -> Icons.Filled.Check
                    },
                    contentDescription = null, modifier = Modifier.size(40.dp),
                    tint = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.85f),
                )
            }
        }
    }
}

/** Translucent, softly bordered, rounded: the pairing controls' card. */
@Composable
private fun GlassCard(modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    val dark = LocalDarkTheme.current
    val shape = RoundedCornerShape(28.dp)
    Column(
        modifier.clip(shape)
            .background((if (dark) Color(0xFF1C1C24) else Color.White).copy(alpha = if (dark) 0.62f else 0.66f))
            .border(1.dp, (if (dark) Color.White else Color.Black).copy(alpha = 0.1f), shape)
            .padding(22.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) { content() }
}

/** Found Macs as chips, plus USB (the Mac sets up the cable connection itself while its USB Sync is on). */
@Composable
private fun MacPicker(
    found: List<FoundMac>, selected: FoundMac?, usbSelected: Boolean, onSelect: (FoundMac) -> Unit, onUsb: () -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        if (found.isEmpty()) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp, color = CuratedBlue)
                Text(
                    "Looking for your Mac on this Wi-Fi…", style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.65f),
                )
            }
        }
        Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            found.forEach { mac -> Chip(Icons.Filled.LaptopMac, mac.name, selected == mac) { onSelect(mac) } }
            Chip(Icons.Filled.Cable, "USB", usbSelected, onClick = onUsb)
        }
    }
}

@Composable
private fun Chip(icon: ImageVector, label: String, selected: Boolean, onClick: () -> Unit) {
    val background by animateColorAsState(
        if (selected) CuratedBlue else MaterialTheme.colorScheme.onSurface.copy(alpha = 0.08f), label = "chip",
    )
    Row(
        Modifier.clip(CircleShape).background(background).clickable(onClick = onClick).padding(horizontal = 14.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        val color = if (selected) Color.White else MaterialTheme.colorScheme.onSurface
        Icon(icon, null, Modifier.size(18.dp), tint = color)
        Text(label, color = color, fontWeight = FontWeight.SemiBold, style = MaterialTheme.typography.labelLarge, maxLines = 1)
    }
}

@Composable
private fun PillField(value: String, onValueChange: (String) -> Unit, placeholder: String, keyboard: KeyboardType) {
    BasicTextField(
        value, onValueChange, singleLine = true,
        textStyle = MaterialTheme.typography.bodyLarge.copy(color = MaterialTheme.colorScheme.onSurface),
        cursorBrush = SolidColor(CuratedBlue),
        keyboardOptions = KeyboardOptions(keyboardType = keyboard),
        decorationBox = { field ->
            Box(
                Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp))
                    .background(MaterialTheme.colorScheme.onSurface.copy(alpha = 0.06f)).padding(horizontal = 14.dp, vertical = 13.dp),
            ) {
                if (value.isEmpty()) Text(placeholder, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.4f))
                field()
            }
        },
    )
}

/** Six boxes for the pairing code, filled from one number field. */
@Composable
private fun CodeBoxes(code: String, onChange: (String) -> Unit, modifier: Modifier = Modifier) {
    val focusRequester = remember { FocusRequester() }
    var focused by remember { mutableStateOf(false) }
    BasicTextField(
        code, onChange, singleLine = true,
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword),
        modifier = modifier.fillMaxWidth().focusRequester(focusRequester).onFocusChanged { focused = it.isFocused },
        decorationBox = {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                for (i in 0 until 6) {
                    val digit = code.getOrNull(i)?.toString() ?: ""
                    val active = focused && i == minOf(code.length, 5)
                    val pop by animateFloatAsState(if (digit.isEmpty()) 1f else 1.05f, spring(dampingRatio = 0.4f), label = "pop")
                    Box(
                        Modifier.weight(1f).height(56.dp).scale(pop).clip(RoundedCornerShape(14.dp))
                            .background(MaterialTheme.colorScheme.onSurface.copy(alpha = if (digit.isEmpty()) 0.05f else 0.09f))
                            .border(
                                if (active) 2.dp else 1.dp,
                                if (active) CuratedBlue else MaterialTheme.colorScheme.onSurface.copy(alpha = 0.12f),
                                RoundedCornerShape(14.dp),
                            )
                            .clickable { focusRequester.requestFocus() },
                        contentAlignment = Alignment.Center,
                    ) {
                        Text(digit, fontSize = 22.sp, fontWeight = FontWeight.SemiBold)
                    }
                }
            }
        },
    )
}

/** A capsule in the logo's red fading into the app's blue. */
@Composable
private fun GradientButton(label: String, enabled: Boolean, busy: Boolean, onClick: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().height(54.dp).alpha(if (enabled || busy) 1f else 0.45f).clip(CircleShape)
            .background(Brush.horizontalGradient(listOf(LogoRed, CuratedBlue)))
            .clickable(enabled = enabled, onClick = onClick),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (busy) {
            CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp, color = Color.White)
            Spacer(Modifier.size(8.dp))
        }
        Text(label, color = Color.White, fontWeight = FontWeight.Bold, style = MaterialTheme.typography.titleMedium)
    }
}
