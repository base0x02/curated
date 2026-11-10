package local.curated.phone

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
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
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.Shadow
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.min
import kotlin.math.sin

private val Lilita = FontFamily(Font(R.font.lilita_one))

private val SkyTop = Color(0xFF29B6F6)
private val SkyMid = Color(0xFF81D4FA)
private val SkyGlow = Color(0xFFFFE0B2)
private val BackHill = Color(0xFF9CCC65)
private val FrontHill = Color(0xFF43A047)
private val PetalColors = listOf(Color(0xFFFF6F91), Color(0xFFFFFFFF), Color(0xFFBA68C8), Color(0xFFFF8A65), Color(0xFFFFF176))

/** Where each flower sits on the front hill, as fractions of the width and of the height below the horizon. */
private val Flowers = listOf(0.08f to 0.55f, 0.2f to 0.3f, 0.33f to 0.7f, 0.46f to 0.42f, 0.6f to 0.72f, 0.72f to 0.35f, 0.85f to 0.62f, 0.94f to 0.28f)

/**
 * The end of a time-limited or Top mix, or of a creator's videos: the whole panel turns into a sunny morning. The sky fades in, hills roll up,
 * the sun pops up over them with a bounce, then the message and a few flowers. Clouds, birds and the sun's rays keep
 * moving after that. Draws nothing that takes touches, so swiping back to the previous video still works.
 */
@Composable
fun SunshinePanel(headline: String, modifier: Modifier = Modifier) {
    val sky = remember { Animatable(0f) }
    val hills = remember { Animatable(0f) }
    val sun = remember { Animatable(0f) }
    val title = remember { Animatable(0f) }
    val subtitle = remember { Animatable(0f) }
    val flowers = remember { Flowers.map { Animatable(0f) } }
    LaunchedEffect(Unit) {
        launch { sky.animateTo(1f, tween(600)) }
        launch { delay(150); hills.animateTo(1f, tween(900, easing = FastOutSlowInEasing)) }
        launch { delay(450); sun.animateTo(1f, spring(dampingRatio = 0.42f, stiffness = Spring.StiffnessVeryLow)) }
        launch { delay(950); title.animateTo(1f, spring(dampingRatio = 0.45f, stiffness = Spring.StiffnessLow)) }
        launch { delay(1250); subtitle.animateTo(1f, spring(dampingRatio = 0.5f, stiffness = Spring.StiffnessLow)) }
        flowers.forEachIndexed { i, flower ->
            launch { delay(1300L + i * 90L); flower.animateTo(1f, spring(dampingRatio = 0.35f, stiffness = Spring.StiffnessMediumLow)) }
        }
    }
    val loop = rememberInfiniteTransition(label = "sunshine")
    val turn by loop.animateFloat(0f, 360f, infiniteRepeatable(tween(24_000, easing = LinearEasing)), label = "rays")
    val drift by loop.animateFloat(0f, 1f, infiniteRepeatable(tween(40_000, easing = LinearEasing)), label = "clouds")
    val pulse by loop.animateFloat(0f, 1f, infiniteRepeatable(tween(1_800, easing = FastOutSlowInEasing), RepeatMode.Reverse), label = "pulse")
    val flap by loop.animateFloat(0f, 2f * PI.toFloat(), infiniteRepeatable(tween(700, easing = LinearEasing)), label = "flap")
    val sway by loop.animateFloat(-1f, 1f, infiniteRepeatable(tween(1_400, easing = FastOutSlowInEasing), RepeatMode.Reverse), label = "sway")

    Box(modifier.fillMaxSize()) {
        Canvas(Modifier.fillMaxSize().graphicsLayer { alpha = sky.value }) {
            val w = size.width
            val h = size.height
            val horizon = h * 0.74f
            drawRect(Brush.verticalGradient(0f to SkyTop, 0.55f to SkyMid, 0.8f to SkyGlow))

            val r = min(w, h) * 0.17f
            // Clouds drift across behind the sun, wrapping around.
            drawCloud(wrap(0.1f + drift, w, r * 2.4f), h * 0.12f, r * 0.45f)
            drawCloud(wrap(0.65f + drift * 1.6f, w, r * 2.4f), h * 0.22f, r * 0.32f)
            drawCloud(wrap(0.4f + drift * 0.7f, w, r * 2.4f), h * 0.52f, r * 0.38f)

            // The sun: rises from behind the hills to just above them.
            val sunY = horizon + r * 2.2f - sun.value * (r * 3.3f)
            val sunCenter = Offset(w / 2, sunY)
            drawCircle(Brush.radialGradient(listOf(Color(0x99FFF59D), Color(0x00FFF59D)), sunCenter, r * 3f), r * 3f, sunCenter)
            rotate(turn, sunCenter) {
                for (i in 0 until 12) {
                    val a = i * PI.toFloat() / 6
                    val inner = r * 1.22f
                    val outer = r * (if (i % 2 == 0) 1.75f else 1.5f) + pulse * r * 0.12f
                    drawLine(
                        Color(0xFFFFCA28), sunCenter + Offset(cos(a), sin(a)) * inner, sunCenter + Offset(cos(a), sin(a)) * outer,
                        strokeWidth = r * 0.16f, cap = StrokeCap.Round,
                    )
                }
            }
            val face = r * (1f + pulse * 0.03f)
            drawCircle(Brush.radialGradient(listOf(Color(0xFFFFF59D), Color(0xFFFFC107), Color(0xFFFF9800)), sunCenter, face), face, sunCenter)
            drawSunFace(sunCenter, face)

            // Birds drift across, wrapping around.
            val birdX = wrap(0.3f + drift * 3f, w, r)
            drawBird(Offset(birdX, h * 0.38f), r * 0.22f, flap)
            drawBird(Offset(birdX + r * 0.6f, h * 0.35f), r * 0.17f, flap + 1.3f)
            drawBird(Offset(birdX - r * 0.5f, h * 0.41f), r * 0.15f, flap + 2.4f)

            // Hills roll up from the bottom, covering the sun's start.
            translate(top = (1f - hills.value) * h * 0.4f) {
                drawPath(Path().apply {
                    moveTo(0f, horizon - h * 0.01f)
                    cubicTo(w * 0.25f, horizon - h * 0.09f, w * 0.55f, horizon + h * 0.02f, w, horizon - h * 0.05f)
                    lineTo(w, h * 1.5f); lineTo(0f, h * 1.5f); close()
                }, BackHill)
                val front = horizon + h * 0.06f
                drawPath(Path().apply {
                    moveTo(0f, front)
                    cubicTo(w * 0.3f, front - h * 0.07f, w * 0.7f, front + h * 0.05f, w, front - h * 0.03f)
                    lineTo(w, h * 1.5f); lineTo(0f, h * 1.5f); close()
                }, FrontHill)
                Flowers.forEachIndexed { i, (fx, fy) ->
                    val y = front + (h - front) * fy
                    drawFlower(Offset(w * fx, y), r * 0.2f * flowers[i].value, PetalColors[i % PetalColors.size], sway * 8f * (if (i % 2 == 0) 1 else -1))
                }
            }
        }

        val text = Shadow(Color(0xFFE65100), Offset(0f, 6f), blurRadius = 0f)
        Column(Modifier.fillMaxSize().padding(horizontal = 24.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Spacer(Modifier.weight(0.75f))
            Text(
                headline, textAlign = TextAlign.Center, color = Color.White,
                style = TextStyle(fontFamily = Lilita, fontSize = 42.sp, lineHeight = 46.sp, shadow = text),
                modifier = Modifier.fillMaxWidth().graphicsLayer {
                    scaleX = title.value; scaleY = title.value; alpha = title.value.coerceIn(0f, 1f)
                },
            )
            Spacer(Modifier.height(12.dp))
            Text(
                "Time to enjoy some sunshine", textAlign = TextAlign.Center, color = Color(0xFFFFFDE7),
                style = TextStyle(fontFamily = Lilita, fontSize = 26.sp, lineHeight = 30.sp, shadow = text.copy(offset = Offset(0f, 4f))),
                modifier = Modifier.fillMaxWidth().graphicsLayer {
                    scaleX = subtitle.value; scaleY = subtitle.value; alpha = subtitle.value.coerceIn(0f, 1f)
                    rotationZ = (1f - subtitle.value) * -8f
                },
            )
            Spacer(Modifier.weight(2.25f))
        }
    }
}

/** An x position moving from left to right across the width, starting again off the left edge. */
private fun wrap(progress: Float, width: Float, margin: Float): Float =
    (progress % 1f) * (width + margin * 2) - margin

private fun DrawScope.drawSunFace(center: Offset, r: Float) {
    val eye = Color(0xFF6D4C41)
    drawCircle(eye, r * 0.08f, center + Offset(-r * 0.3f, -r * 0.12f))
    drawCircle(eye, r * 0.08f, center + Offset(r * 0.3f, -r * 0.12f))
    drawCircle(Color(0x66FF7043), r * 0.13f, center + Offset(-r * 0.5f, r * 0.15f))
    drawCircle(Color(0x66FF7043), r * 0.13f, center + Offset(r * 0.5f, r * 0.15f))
    drawArc(
        eye, startAngle = 20f, sweepAngle = 140f, useCenter = false,
        topLeft = center + Offset(-r * 0.32f, -r * 0.2f), size = Size(r * 0.64f, r * 0.5f),
        style = Stroke(width = r * 0.08f, cap = StrokeCap.Round),
    )
}

private fun DrawScope.drawCloud(x: Float, y: Float, r: Float) {
    val white = Color.White
    drawCircle(white, r, Offset(x, y))
    drawCircle(white, r * 1.3f, Offset(x + r * 1.1f, y - r * 0.45f))
    drawCircle(white, r * 0.95f, Offset(x + r * 2.2f, y))
    drawRoundRect(white, Offset(x, y - r * 0.2f), Size(r * 2.2f, r * 1.2f), CornerRadius(r * 0.6f))
}

private fun DrawScope.drawBird(at: Offset, r: Float, phase: Float) {
    val lift = sin(phase) * r * 0.6f
    val wing = Path().apply {
        moveTo(at.x - r, at.y - lift)
        quadraticTo(at.x - r * 0.45f, at.y - r * 0.5f, at.x, at.y)
        quadraticTo(at.x + r * 0.45f, at.y - r * 0.5f, at.x + r, at.y - lift)
    }
    drawPath(wing, Color(0xFF37474F), style = Stroke(width = r * 0.22f, cap = StrokeCap.Round))
}

private fun DrawScope.drawFlower(base: Offset, r: Float, petals: Color, tilt: Float) {
    if (r <= 0f) return
    rotate(tilt, base) {
        drawLine(Color(0xFF2E7D32), base, base - Offset(0f, r * 3f), strokeWidth = r * 0.35f, cap = StrokeCap.Round)
        val head = base - Offset(0f, r * 3f)
        for (i in 0 until 5) {
            val a = i * 2 * PI.toFloat() / 5
            drawCircle(petals, r * 0.6f, head + Offset(cos(a), sin(a)) * (r * 0.7f))
        }
        drawCircle(Color(0xFFFFB300), r * 0.45f, head)
    }
}

/** Whether the queue ends with the sunshine panel (a time-limited or Top mix, or a creator) rather than the caught-up card. */
val Playback.endsInSunshine: Boolean
    get() = timeLimitMinutes != null || mode?.topLimit != null || mode is PlaybackMode.Creator
