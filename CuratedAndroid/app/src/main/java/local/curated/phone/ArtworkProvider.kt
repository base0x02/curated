package local.curated.phone

import android.content.ContentProvider
import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.PorterDuff
import android.graphics.PorterDuffColorFilter
import android.graphics.RadialGradient
import android.graphics.Shader
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.ParcelFileDescriptor
import androidx.annotation.DrawableRes
import androidx.compose.ui.graphics.PathFillType
import androidx.compose.ui.graphics.asAndroidPath
import androidx.compose.ui.graphics.vector.VectorGroup
import androidx.compose.ui.graphics.vector.VectorPath
import androidx.compose.ui.graphics.vector.toPath
import java.io.File
import kotlin.math.min

/** Pictures for the car and the media notification, as content URIs, since neither can read the app's files. */
object CarArtwork {
    private fun base(context: Context) = Uri.Builder().scheme("content").authority("${context.packageName}.artwork")

    /** A video's poster or, for one without (short videos), a frame from it. */
    fun video(context: Context, id: String): Uri = base(context).appendPath("video").appendPath(id).build()
    fun avatar(context: Context, creator: String): Uri = base(context).appendPath("avatar").appendPath(creator).build()
    fun tile(context: Context, tile: Tile): Uri = base(context).appendPath("tile").appendPath(tile.name).build()
    /** A category's tile: Home's glyph for it, on the color for its place in the Mac's list, so neighbors differ. */
    fun category(context: Context, name: String, symbol: String?, position: Int): Uri =
        base(context).appendPath("category").appendPath(name)
            .appendQueryParameter("symbol", symbol.orEmpty())
            .appendQueryParameter("color", position.toString())
            .build()
    /** A plain white icon, for the tabs. */
    fun icon(context: Context, @DrawableRes resource: Int): Uri =
        Uri.parse("android.resource://${context.packageName}/${context.resources.getResourceTypeName(resource)}/${context.resources.getResourceEntryName(resource)}")
}

/** The car's mix tiles, in the logo's and the aurora's colors. */
enum class Tile(@param:DrawableRes val icon: Int, val from: Long, val to: Long) {
    Latest(R.drawable.ic_car_clock, 0xFF0A84FF, 0xFF8C4DF2),
    LongAutomix(R.drawable.ic_car_shuffle, 0xFF8C4DF2, 0xFFE8344E),
    Automix(R.drawable.ic_car_shuffle, 0xFFE8344E, 0xFFFF7A45),
    Top(R.drawable.ic_car_star, 0xFF19C3D6, 0xFF0A84FF),
    Vine(R.drawable.vine_glyph, 0xFF00B488, 0xFF19C37D),
    WatchLater(R.drawable.ic_car_clock, 0xFFFF9F0A, 0xFFFF5E3A),
    Bookmarks(R.drawable.ic_car_bookmark, 0xFFEC4899, 0xFF8C4DF2),
    Queue(R.drawable.ic_car_queue, 0xFF475569, 0xFF1E293B),
    Sunshine(R.drawable.ic_car_sun, 0xFFFFC53D, 0xFFFF7A18),
    Empty(R.drawable.ic_car_grid, 0xFF475569, 0xFF1E293B),
}

/**
 * Serves pictures only, whatever asks: posters, avatars, frames taken from videos, and the tiles it draws. Those last
 * two are kept in the cache folder. Anything that isn't one of these paths gets nothing.
 */
class ArtworkProvider : ContentProvider() {
    private val frameLock = Any()

    override fun onCreate() = true

    override fun getType(uri: Uri): String = if (uri.pathSegments.firstOrNull() in setOf("tile", "category")) "image/png" else "image/jpeg"

    override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor? {
        if (mode != "r") throw SecurityException("Read only")
        val kind = uri.pathSegments.getOrNull(0)
        val name = uri.pathSegments.getOrNull(1)
        if (uri.pathSegments.size != 2 || name == null || name.contains('/') || name.startsWith(".")) return null
        val file = when (kind) {
            "video" -> videoPicture(name)
            "avatar" -> curatedStore().avatarFile(name).takeIf { it.exists() }
            "tile" -> Tile.entries.firstOrNull { it.name == name }?.let { tile -> cached("tile-v$TILE_VERSION-$name.png") { drawTile(tile) } }
            "category" -> {
                val symbol = uri.getQueryParameter("symbol")
                val color = (uri.getQueryParameter("color")?.toIntOrNull() ?: 0).mod(CATEGORY_COLORS.size)
                cached("category-v$TILE_VERSION-$color-${symbol.hashCode()}.png") { drawCategory(symbol, color) }
            }
            else -> null
        } ?: return null
        return ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
    }

    private fun curatedStore() = requireNotNull(context).curated.state.store

    private fun videoPicture(id: String): File? {
        val store = curatedStore()
        store.posterFile(id).takeIf { it.exists() }?.let { return it }
        return cached("frame-$id.jpg") { videoFrame(id) }
    }

    /** A frame a moment in, cropped square when upright, since upright video would be a sliver in a tile. */
    private fun videoFrame(id: String): Bitmap? = synchronized(frameLock) {
        val video = curatedStore().videosDir.listFiles { file -> file.name.startsWith("$id.") && !file.name.endsWith(".part") }?.firstOrNull()
            ?: return null
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(video.path)
            val frame = retriever.getFrameAtTime(1_000_000, MediaMetadataRetriever.OPTION_CLOSEST_SYNC) ?: retriever.frameAtTime ?: return null
            val square = if (frame.height > frame.width) Bitmap.createBitmap(frame, 0, (frame.height - frame.width) / 2, frame.width, frame.width) else frame
            val scale = min(1f, FRAME_SIZE.toFloat() / maxOf(square.width, square.height))
            Bitmap.createScaledBitmap(square, (square.width * scale).toInt().coerceAtLeast(1), (square.height * scale).toInt().coerceAtLeast(1), true)
        } catch (_: Exception) {
            null
        } finally {
            retriever.release()
        }
    }

    private fun cached(name: String, draw: () -> Bitmap?): File? {
        val dir = File(requireNotNull(context).cacheDir, "car-artwork").apply { mkdirs() }
        val file = File(dir, name)
        if (file.exists()) return file
        val bitmap = draw() ?: return null
        val temporary = File.createTempFile(name, ".tmp", dir)
        temporary.outputStream().use { bitmap.compress(if (name.endsWith(".png")) Bitmap.CompressFormat.PNG else Bitmap.CompressFormat.JPEG, 88, it) }
        temporary.renameTo(file)
        return file
    }

    private fun canvasWith(from: Long, to: Long, draw: (Canvas) -> Unit): Bitmap {
        val size = TILE_SIZE.toFloat()
        val bitmap = Bitmap.createBitmap(TILE_SIZE, TILE_SIZE, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        paint.shader = LinearGradient(0f, 0f, size, size, from.toInt(), to.toInt(), Shader.TileMode.CLAMP)
        canvas.drawRect(0f, 0f, size, size, paint)
        // A soft glow in one corner and shade in the other, like the aurora on Home.
        paint.shader = RadialGradient(size * 0.2f, size * 0.15f, size * 0.75f, Color.argb(90, 255, 255, 255), Color.TRANSPARENT, Shader.TileMode.CLAMP)
        canvas.drawRect(0f, 0f, size, size, paint)
        paint.shader = RadialGradient(size * 0.9f, size, size * 0.8f, Color.argb(80, 0, 0, 0), Color.TRANSPARENT, Shader.TileMode.CLAMP)
        canvas.drawRect(0f, 0f, size, size, paint)
        draw(canvas)
        return bitmap
    }

    private fun drawTile(tile: Tile): Bitmap = canvasWith(tile.from, tile.to) { canvas ->
        val icon = requireNotNull(requireNotNull(context).getDrawable(tile.icon)).mutate()
        val inset = (TILE_SIZE * 0.27f).toInt()
        icon.setBounds(inset, inset, TILE_SIZE - inset, TILE_SIZE - inset)
        icon.colorFilter = PorterDuffColorFilter(Color.WHITE, PorterDuff.Mode.SRC_IN)
        icon.draw(canvas)
    }

    private fun drawCategory(symbol: String?, colorIndex: Int): Bitmap {
        val (from, to) = CATEGORY_COLORS[colorIndex]
        val glyph = categoryGlyph(symbol)
        return canvasWith(from, to) { canvas ->
            val inset = TILE_SIZE * 0.25f
            val scale = (TILE_SIZE - 2 * inset) / glyph.viewportWidth
            canvas.translate(inset, inset)
            canvas.scale(scale, scale)
            drawGroup(canvas, glyph.root, Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.WHITE })
        }
    }

    /** Material's icons are plain filled paths, with no transforms in their groups. */
    private fun drawGroup(canvas: Canvas, group: VectorGroup, paint: Paint) {
        for (node in group) {
            when (node) {
                is VectorGroup -> drawGroup(canvas, node, paint)
                is VectorPath -> {
                    val path = node.pathData.toPath().asAndroidPath()
                    if (node.pathFillType == PathFillType.EvenOdd) path.fillType = android.graphics.Path.FillType.EVEN_ODD
                    canvas.drawPath(path, paint)
                }
            }
        }
    }

    override fun query(uri: Uri, projection: Array<out String>?, selection: String?, selectionArgs: Array<out String>?, sortOrder: String?): Cursor? = null
    override fun insert(uri: Uri, values: ContentValues?): Uri? = null
    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?) = 0
    override fun update(uri: Uri, values: ContentValues?, selection: String?, selectionArgs: Array<out String>?) = 0

    private companion object {
        /** Raise it when the tiles' drawing changes. */
        const val TILE_VERSION = 3
        const val TILE_SIZE = 384
        const val FRAME_SIZE = 512
        /** Ten different hues, so a list of up to ten categories never repeats one. */
        val CATEGORY_COLORS = listOf(
            0xFF0A84FF to 0xFF3D5AFE, // Blue
            0xFFFF9F0A to 0xFFF4511E, // Orange
            0xFF00B488 to 0xFF00897B, // Green
            0xFFEC4899 to 0xFFAD1457, // Pink
            0xFF8C4DF2 to 0xFF5E35B1, // Purple
            0xFF19C3D6 to 0xFF00838F, // Teal
            0xFFE8344E to 0xFFB71C1C, // Red
            0xFFFFC53D to 0xFFEF9F00, // Yellow
            0xFF7CB342 to 0xFF33691E, // Lime
            0xFF78909C to 0xFF37474F, // Slate
        )
    }
}
