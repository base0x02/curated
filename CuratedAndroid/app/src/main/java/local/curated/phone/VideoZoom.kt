package local.curated.phone

import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animate
import androidx.compose.animation.core.spring
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.calculateCentroid
import androidx.compose.foundation.gestures.calculatePan
import androidx.compose.foundation.gestures.calculateZoom
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.input.pointer.pointerInput
import kotlin.math.abs
import kotlin.math.exp
import kotlin.math.ln
import kotlin.math.max
import kotlin.math.sign
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch

/**
 * Pinch zoom for a long video. A scale of 1 shows the whole video (fit); `fill` is where it covers the whole screen.
 * Around `fill` the pinch holds still for a stretch (with a tick), so it's easy to land on, then carries on past it.
 * While zoomed in, one finger pans, never past the video's edges.
 */
class VideoZoom(private val onSnap: () -> Unit) {
    var scale by mutableFloatStateOf(1f); private set
    var pan by mutableStateOf(Offset.Zero); private set

    /** The video area's size and the video's width / height, kept up to date by the player. */
    var container = Size.Zero
        set(value) {
            if (value != field) reset()
            field = value
        }
    var aspect = 16f / 9f

    /** The pinch's own scale, before the hold at fill; scale is worked out from it. */
    private var raw = 1f

    /** The video's size on screen at a scale of 1. */
    private val fitted: Size
        get() {
            if (container.width <= 0 || container.height <= 0 || aspect <= 0) return container
            return if (container.width / container.height > aspect) Size(container.height * aspect, container.height)
            else Size(container.width, container.width / aspect)
        }

    val fill: Float
        get() = fitted.takeIf { it.width > 0 && it.height > 0 }
            ?.let { max(container.width / it.width, container.height / it.height) } ?: 1f

    private val maxScale get() = max(4f, fill * 2f)
    private val hasSnap get() = fill > 1.02f

    fun reset() {
        scale = 1f
        raw = 1f
        pan = Offset.Zero
    }

    /** The scale shown for a raw pinch scale: the same, less a band around fill (in log terms) that sticks at fill. */
    private fun shown(raw: Float): Float {
        if (!hasSnap) return raw
        val r = ln(raw / fill)
        return if (abs(r) < SNAP_BAND) fill else fill * exp(r - sign(r) * SNAP_BAND)
    }

    private fun rawFor(shown: Float): Float {
        if (!hasSnap || shown == fill) return shown
        val r = ln(shown / fill)
        return fill * exp(r + sign(r) * SNAP_BAND)
    }

    private fun clamped(offset: Offset, scale: Float): Offset {
        val maxX = max(0f, (fitted.width * scale - container.width) / 2)
        val maxY = max(0f, (fitted.height * scale - container.height) / 2)
        return Offset(offset.x.coerceIn(-maxX, maxX), offset.y.coerceIn(-maxY, maxY))
    }

    /** Two fingers: zoom by `factor` about `centroid` (in the video area), moving by `drag` as well. */
    fun pinch(factor: Float, centroid: Offset, drag: Offset) {
        raw *= factor
        var next = shown(raw)
        if (next !in 1f..maxScale) {
            next = next.coerceIn(1f, maxScale)
            raw = rawFor(next)
        }
        if (next == fill && scale != fill && hasSnap) onSnap()
        // Keep the point under the fingers where it is.
        val c = centroid - Offset(container.width / 2, container.height / 2)
        pan = clamped(c + (pan - c) * (next / scale) + drag, next)
        scale = next
    }

    fun drag(by: Offset) {
        pan = clamped(pan + by, scale)
    }

    /** Fingers lifted: a scale only just above 1 settles back to the whole video. */
    fun settle(scope: CoroutineScope) {
        if (scale >= 1.05f || scale == 1f) return
        val from = scale
        val fromPan = pan
        scope.launch {
            animate(0f, 1f, animationSpec = spring(stiffness = Spring.StiffnessMediumLow)) { t, _ ->
                scale = from + (1f - from) * t
                pan = fromPan * (1f - t)
            }
            reset()
        }
    }

    companion object {
        /** How much pinching (as a log of the scale, about ±12%) the hold at fill takes up. */
        private const val SNAP_BAND = 0.12f
    }
}

/**
 * Two fingers zoom; one finger pans once zoomed in, after moving past the touch slop, so taps and double taps on the
 * video still work. Movement it uses is consumed, which keeps those taps from firing.
 */
fun Modifier.videoZoom(zoom: VideoZoom, scope: CoroutineScope, enabled: Boolean): Modifier =
    if (!enabled) this else pointerInput(zoom) {
        awaitEachGesture {
            awaitFirstDown(requireUnconsumed = false)
            var panning = false
            var travelled = Offset.Zero
            while (true) {
                val event = awaitPointerEvent()
                val pressed = event.changes.count { it.pressed }
                if (pressed == 0) break
                val drag = event.calculatePan()
                if (pressed >= 2) {
                    zoom.pinch(event.calculateZoom(), event.calculateCentroid(useCurrent = true), drag)
                    event.changes.forEach { it.consume() }
                    panning = true
                } else if (zoom.scale > 1f) {
                    if (!panning) {
                        travelled += drag
                        panning = travelled.getDistance() > viewConfiguration.touchSlop
                    }
                    if (panning) {
                        zoom.drag(drag)
                        event.changes.forEach { it.consume() }
                    }
                }
            }
            zoom.settle(scope)
        }
    }
