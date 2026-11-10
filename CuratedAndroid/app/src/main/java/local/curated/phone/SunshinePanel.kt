package local.curated.phone

import android.provider.Settings
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.Shadow
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlin.math.PI
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sin

// Twilight → morning.
private val SkyTop = Color(0xFF141C3D) to Color(0xFF5991CC)
private val SkyMiddle = Color(0xFF383866) to Color(0xFFA1C2E3)
private val SkyHorizon = Color(0xFF8C5C70) to Color(0xFFFFD6AB)
private val SunCore = Color(0xFFFFFAE6)
private val SunEdge = Color(0xFFFFD98C)
private val Glow = Color(0xFFFFCC8C)

/** A layer of hills, back to front: its twilight and morning colors, where it sits, and how much it fades into the haze. */
private class Hill(val night: Color, val day: Color, val base: Float, val height: Float, val haze: Float, val seed: Float)

private val Hills = listOf(
    Hill(Color(0xFF474063), Color(0xFF8FA8A8), -0.02f, 0.025f, 0.45f, 1.3f),
    Hill(Color(0xFF2B2B4A), Color(0xFF578070), 0.045f, 0.03f, 0.2f, 4.1f),
    Hill(Color(0xFF17192B), Color(0xFF2B5245), 0.12f, 0.035f, 0f, 7.7f),
)

/**
 * The end of a time-limited or Top mix, or of a creator's videos: the whole panel turns into a quiet daybreak. It opens
 * on a twilight sky with a few stars; over about three seconds the sun rises from behind layered hills, the sky warms
 * to morning and the stars fade, then the message fades up. After that only the clouds drift and the sun's glow
 * breathes, slowly. Draws nothing that takes touches, so swiping back to the previous video still works. With
 * animations turned off it shows the finished scene, standing still. The iOS app's `SunshinePanel.swift` draws the same scene.
 */
@Composable
fun SunshinePanel(headline: String, modifier: Modifier = Modifier) {
    val context = LocalContext.current
    val still = Settings.Global.getFloat(context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f
    val t by produceState(if (still) 30f else 0f) {
        if (still) return@produceState
        val start = withFrameNanos { it }
        while (true) withFrameNanos { value = (it - start) / 1e9f }
    }

    Box(modifier.fillMaxSize()) {
        Canvas(Modifier.fillMaxSize().graphicsLayer { alpha = ease(t, 0f, 0.8f) }) { drawDaybreak(t) }

        val shadow = Shadow(Color(0x2E000000), Offset(0f, 4f), blurRadius = 20f)
        val title = ease(t, 1.8f, 1.2f)
        val subtitle = ease(t, 2.3f, 1.2f)
        Column(Modifier.fillMaxSize().padding(horizontal = 24.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Spacer(Modifier.weight(0.75f))
            Text(
                headline, textAlign = TextAlign.Center, color = Color.White,
                style = TextStyle(fontSize = 32.sp, lineHeight = 38.sp, fontWeight = FontWeight.SemiBold, shadow = shadow),
                modifier = Modifier.fillMaxWidth().graphicsLayer { alpha = title; translationY = (1 - title) * 10.dp.toPx() },
            )
            Spacer(Modifier.height(10.dp))
            Text(
                "Time to enjoy some sunshine", textAlign = TextAlign.Center, color = Color.White.copy(alpha = 0.85f),
                style = TextStyle(fontSize = 20.sp, lineHeight = 26.sp, shadow = shadow),
                modifier = Modifier.fillMaxWidth().graphicsLayer { alpha = subtitle; translationY = (1 - subtitle) * 10.dp.toPx() },
            )
            Spacer(Modifier.weight(2.25f))
        }
    }
}

/** Ease-out from 0 to 1. */
private fun ease(t: Float, delay: Float, duration: Float): Float {
    val x = ((t - delay) / duration).coerceIn(0f, 1f)
    return 1 - (1 - x).pow(3)
}

/** Ease-in-out from 0 to 1, for the sunrise: it starts and settles gently. */
private fun easeInOut(t: Float, delay: Float, duration: Float): Float {
    val x = ((t - delay) / duration).coerceIn(0f, 1f)
    return x * x * (3 - 2 * x)
}

private fun DrawScope.drawDaybreak(t: Float) {
    val w = size.width
    val h = size.height
    val horizon = h * 0.72f
    // How far the morning has come: 0 at twilight, 1 once the sun is up.
    val light = easeInOut(t, 0.2f, 3.4f)
    val low = lerp(SkyHorizon.first, SkyHorizon.second, light)
    drawRect(Brush.verticalGradient(
        0f to lerp(SkyTop.first, SkyTop.second, light),
        0.5f to lerp(SkyMiddle.first, SkyMiddle.second, light),
        0.74f to low,
    ))

    // Stars, fading as it gets light.
    val stars = 1 - ease(t, 0.4f, 2.4f)
    if (stars > 0f) {
        val density = density
        for (i in 0 until 28) {
            val x = noise(i * 1.7f) * w
            val y = noise(i * 3.1f + 0.5f) * h * 0.5f
            val r = (0.6f + noise(i * 5.3f) * 0.9f) * density
            val twinkle = 0.75f + 0.25f * sin(t * 1.3f + i)
            drawCircle(Color.White.copy(alpha = 0.75f * stars * twinkle), r, Offset(x, y))
        }
    }

    // The sun's glow and the sun, rising from behind the hills.
    val r = min(w, h) * 0.085f
    val sun = Offset(w / 2, horizon + r * 1.6f - light * (r * 1.6f + h * 0.11f))
    val glowRadius = r * 6 * (1 + 0.04f * sin(t * 2 * PI.toFloat() / 8))
    drawCircle(Brush.radialGradient(
        0f to Glow.copy(alpha = 0.55f * light), 0.5f to Glow.copy(alpha = 0.18f * light), 1f to Color.Transparent,
        center = sun, radius = glowRadius,
    ), glowRadius, sun)
    drawCircle(Brush.radialGradient(
        0.72f to SunEdge.copy(alpha = 0.5f), 1f to SunEdge.copy(alpha = 0f), center = sun, radius = r * 1.25f,
    ), r * 1.25f, sun)
    drawCircle(Brush.radialGradient(0f to SunCore, 0.5f to SunCore, 1f to SunEdge, center = sun, radius = r), r, sun)

    // Soft wisps of cloud, catching the light as it comes.
    val cloud = lerp(Color(0xFF9E8CB8), Color(0xFFFFF2E6), light)
    val drift = t / 150
    drawWisp(wrap(0.18f + drift, w, r * 4), h * 0.2f, r, cloud)
    drawWisp(wrap(0.7f + drift * 1.4f, w, r * 4), h * 0.33f, r * 0.75f, cloud)

    // The hills, back to front, rising a little into place (the far ones less, for depth).
    Hills.forEachIndexed { i, hill ->
        val rise = (1 - ease(t, 0.1f * i, 1.8f)) * h * 0.03f * (i + 1)
        val color = lerp(lerp(hill.night, hill.day, light), low, hill.haze)
        drawPath(ridge(w, h, horizon + h * hill.base + rise, h * hill.height, hill.seed), color)
        // Morning haze lying in front of the far hills.
        if (i == 0) {
            val band = horizon + h * 0.02f
            drawRect(
                Brush.verticalGradient(
                    0f to low.copy(alpha = 0f), 0.5f to low.copy(alpha = 0.35f * light), 1f to low.copy(alpha = 0f),
                    startY = band - h * 0.06f, endY = band + h * 0.06f,
                ),
                topLeft = Offset(0f, band - h * 0.06f), size = androidx.compose.ui.geometry.Size(w, h * 0.12f),
            )
        }
    }
}

/** A gently rolling hilltop at `base`, filled down past the bottom of the panel. */
private fun ridge(w: Float, h: Float, base: Float, height: Float, seed: Float): Path = Path().apply {
    val steps = max((w / 12).toInt(), 24)
    for (step in 0..steps) {
        val x = w * step / steps
        val u = x / w * 2 * PI.toFloat()
        val y = base - height * (0.6f * sin(u * 0.9f + seed) + 0.4f * sin(u * 2.3f + seed * 1.7f))
        if (step == 0) moveTo(x, y) else lineTo(x, y)
    }
    lineTo(w, h * 1.5f)
    lineTo(0f, h * 1.5f)
    close()
}

/** A long, soft-edged streak of cloud. */
private fun DrawScope.drawWisp(x: Float, y: Float, r: Float, color: Color) {
    for ((dx, dy, scale, alpha) in listOf(Wisp(0f, 0f, 1f, 0.45f), Wisp(r * 1.4f, r * 0.25f, 0.7f, 0.35f))) {
        val center = Offset(x + dx, y + dy)
        val radius = r * 3 * scale
        scale(1f, 0.16f, center) {
            drawCircle(Brush.radialGradient(0f to color.copy(alpha = alpha), 1f to color.copy(alpha = 0f), center = center, radius = radius), radius, center)
        }
    }
}

private data class Wisp(val dx: Float, val dy: Float, val scale: Float, val alpha: Float)

/** A steady pseudo-random number from 0 to 1, so the stars sit in the same places on every frame. */
private fun noise(seed: Float): Float {
    val x = sin(seed.toDouble() * 12.9898) * 43758.5453
    return (x - floor(x)).toFloat()
}

/** An x position moving from left to right across the width, starting again off the left edge. */
private fun wrap(progress: Float, width: Float, margin: Float): Float =
    (progress % 1f) * (width + margin * 2) - margin

/** Whether the queue ends with the sunshine panel (a time-limited or Top mix, or a creator) rather than the caught-up card. */
val Playback.endsInSunshine: Boolean
    get() = timeLimitMinutes != null || mode?.topLimit != null || mode is PlaybackMode.Creator
