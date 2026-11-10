package local.curated.phone

import androidx.annotation.DrawableRes
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import java.time.DayOfWeek
import java.time.LocalDate
import java.time.temporal.TemporalAdjusters

// The aurora's palettes and the holiday wordmarks, as on the Mac (Aurora.swift and LogoView there).

/** What's behind Home: the aurora in one of its palettes, or in a holiday's. */
enum class BackgroundStyle(val label: String) { Aurora("Aurora"), Holiday("Holiday") }

/** The aurora's colors: four blobs drifting over a near-black base (near-white in light mode). */
class AuroraPalette(
    val id: String,
    val name: String,
    /** Each blob's color and how strong it is, in the order of `AuroraBackground`'s drifts. */
    val blobs: List<Pair<Color, Float>>,
    val darkBase: Color,
    val lightBase: Color,
) {
    companion object {
        private fun rgb(r: Double, g: Double, b: Double) = Color(r.toFloat(), g.toFloat(), b.toFloat())
        private val night = rgb(0.03, 0.03, 0.06)
        private val day = rgb(0.96, 0.96, 0.98)

        /** The logo's red and cyan and the app's blue, with a little violet. */
        val Curated = AuroraPalette(
            "curated", "Curated",
            listOf(LogoRed to 1f, LogoCyan to 1f, CuratedBlue to 1f, Color(0xFF8C4DF2) to 0.7f), night, day,
        )

        val aurora = listOf(
            Curated,
            AuroraPalette("northernLights", "Northern Lights", listOf(
                rgb(0.2, 0.9, 0.5) to 1f, rgb(0.1, 0.7, 0.8) to 1f, rgb(0.5, 0.3, 0.9) to 1f, rgb(0.15, 0.35, 0.85) to 0.7f,
            ), rgb(0.02, 0.04, 0.06), rgb(0.95, 0.97, 0.97)),
            AuroraPalette("ocean", "Ocean", listOf(
                rgb(0.0, 0.6, 0.7) to 1f, rgb(0.3, 0.85, 0.9) to 1f, rgb(0.05, 0.25, 0.75) to 1f, rgb(0.2, 0.75, 0.55) to 0.7f,
            ), rgb(0.02, 0.04, 0.07), rgb(0.95, 0.97, 0.98)),
            AuroraPalette("sunset", "Sunset", listOf(
                rgb(1.0, 0.4, 0.35) to 1f, rgb(1.0, 0.6, 0.2) to 1f, rgb(0.85, 0.25, 0.6) to 1f, rgb(0.45, 0.25, 0.8) to 0.7f,
            ), rgb(0.06, 0.03, 0.05), rgb(0.98, 0.96, 0.95)),
            AuroraPalette("forest", "Forest", listOf(
                rgb(0.35, 0.6, 0.25) to 1f, rgb(0.8, 0.7, 0.3) to 0.8f, rgb(0.1, 0.45, 0.3) to 1f, rgb(0.55, 0.7, 0.55) to 0.7f,
            ), rgb(0.03, 0.05, 0.03), rgb(0.96, 0.97, 0.95)),
            AuroraPalette("blossom", "Blossom", listOf(
                rgb(1.0, 0.55, 0.7) to 1f, rgb(0.75, 0.6, 0.95) to 1f, rgb(0.9, 0.35, 0.5) to 1f, rgb(1.0, 0.75, 0.6) to 0.7f,
            ), rgb(0.06, 0.03, 0.05), rgb(0.98, 0.96, 0.97)),
        )

        val holiday = listOf(
            // Glowing jack-o'-lanterns and lamps in a misty blue night.
            AuroraPalette("halloween", "Halloween", listOf(
                rgb(1.0, 0.45, 0.05) to 1f, rgb(0.25, 0.4, 0.5) to 1f, rgb(0.95, 0.3, 0.05) to 0.9f, rgb(1.0, 0.7, 0.2) to 0.7f,
            ), rgb(0.03, 0.05, 0.07), rgb(0.97, 0.95, 0.92)),
            // A haunted house under a violet sky and a lavender moon, with a pumpkin's orange.
            AuroraPalette("halloween2", "Halloween 2", listOf(
                rgb(0.55, 0.25, 0.8) to 1f, rgb(0.85, 0.75, 0.95) to 0.9f, rgb(0.3, 0.1, 0.45) to 1f, rgb(1.0, 0.6, 0.15) to 0.6f,
            ), rgb(0.06, 0.03, 0.09), rgb(0.97, 0.95, 0.99)),
            // Pumpkin, harvest gold, cranberry and brown on warm tan.
            AuroraPalette("thanksgiving", "Thanksgiving", listOf(
                rgb(0.9, 0.5, 0.15) to 1f, rgb(0.95, 0.75, 0.3) to 1f, rgb(0.75, 0.2, 0.15) to 0.9f, rgb(0.5, 0.3, 0.15) to 0.8f,
            ), rgb(0.07, 0.05, 0.03), rgb(0.96, 0.92, 0.85)),
            // Red ornaments and golden bokeh on frosted blue pine.
            AuroraPalette("christmas1", "Christmas 1", listOf(
                rgb(0.8, 0.08, 0.12) to 1f, rgb(1.0, 0.75, 0.4) to 1f, rgb(0.45, 0.6, 0.75) to 1f, rgb(0.15, 0.35, 0.3) to 0.7f,
            ), rgb(0.03, 0.05, 0.08), rgb(0.95, 0.96, 0.97)),
            // Red, green and white.
            AuroraPalette("christmas2", "Christmas 2", listOf(
                rgb(0.85, 0.1, 0.15) to 1f, rgb(0.1, 0.6, 0.25) to 1f, rgb(1.0, 1.0, 1.0) to 0.7f, rgb(0.05, 0.4, 0.2) to 0.8f,
            ), rgb(0.04, 0.05, 0.04), rgb(0.96, 0.97, 0.96)),
            // Snowy whites and ice blues; the light base is a cool grey so the white still shows.
            AuroraPalette("christmas3", "Christmas 3", listOf(
                rgb(1.0, 1.0, 1.0) to 1f, rgb(0.75, 0.88, 1.0) to 1f, rgb(0.85, 0.88, 0.92) to 1f, rgb(0.6, 0.75, 0.95) to 0.8f,
            ), rgb(0.08, 0.1, 0.14), rgb(0.86, 0.9, 0.95)),
        )

        /** Picks `id` from `palettes`, or the first one. */
        fun named(id: String?, palettes: List<AuroraPalette>) = palettes.firstOrNull { it.id == id } ?: palettes.first()

        /** How strong the blobs are at full intensity; light mode is stronger so the colors don't wash out. */
        fun strength(dark: Boolean) = if (dark) 0.6f else 0.7f

        /** A blob's color as drawn: as is in dark mode; richer in light mode, where blending into white pales it. */
        fun shade(color: Color, dark: Boolean): Color {
            if (dark) return color
            val hsv = FloatArray(3)
            android.graphics.Color.colorToHSV(color.toArgb(), hsv)
            hsv[1] = (hsv[1] * 1.3f).coerceAtMost(1f)
            hsv[2] *= 0.92f
            return Color(android.graphics.Color.HSVToColor(hsv))
        }
    }
}

/**
 * The holidays with their own wordmarks, used on Home in place of the usual ones while holiday wordmarks are on: one
 * for the short Home and one, with landscape cards, for the long Home.
 */
enum class Holiday(
    val label: String,
    @DrawableRes val light: Int, @DrawableRes val dark: Int,
    @DrawableRes val longLight: Int, @DrawableRes val longDark: Int,
) {
    Halloween("Halloween", R.drawable.wordmark_halloween_light, R.drawable.wordmark_halloween_dark,
        R.drawable.wordmark_long_halloween_light, R.drawable.wordmark_long_halloween_dark),
    Thanksgiving("Thanksgiving", R.drawable.wordmark_thanksgiving_light, R.drawable.wordmark_thanksgiving_dark,
        R.drawable.wordmark_long_thanksgiving_light, R.drawable.wordmark_long_thanksgiving_dark),
    Christmas("Christmas", R.drawable.wordmark_christmas_light, R.drawable.wordmark_christmas_dark,
        R.drawable.wordmark_long_christmas_light, R.drawable.wordmark_long_christmas_dark);

    @DrawableRes fun wordmark(dark: Boolean, long: Boolean = false) = when {
        long -> if (dark) longDark else longLight
        else -> if (dark) this.dark else light
    }

    companion object {
        /**
         * October is Halloween; November is Thanksgiving, up to and including Thanksgiving Day (the fourth Thursday);
         * Christmas runs from the day after through January 5.
         */
        fun current(date: LocalDate = LocalDate.now()): Holiday? = when (date.monthValue) {
            10 -> Halloween
            11 -> if (date.dayOfMonth <= thanksgivingDay(date.year)) Thanksgiving else Christmas
            12 -> Christmas
            1 -> if (date.dayOfMonth <= 5) Christmas else null
            else -> null
        }

        /** The day of November that's its fourth Thursday. */
        fun thanksgivingDay(year: Int) =
            LocalDate.of(year, 11, 1).with(TemporalAdjusters.dayOfWeekInMonth(4, DayOfWeek.THURSDAY)).dayOfMonth
    }
}
