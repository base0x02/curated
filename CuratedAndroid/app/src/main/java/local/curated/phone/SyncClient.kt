package local.curated.phone

import org.json.JSONArray
import java.time.Instant
import kotlinx.coroutines.ensureActive
import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import org.json.JSONObject
import java.io.File
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import kotlin.coroutines.resume

class SyncException(message: String, val status: Int = 0) : IOException(message)

/** One `GET /creators/<id>/older` event. */
data class OlderVideosEvent(val videos: List<OlderVideo>, val error: String?)

/** What the Mac sends back for `/positions`. */
data class PositionsReply(val positions: Map<String, PositionMark>, val nowPlaying: NowPlayingMark?, val playback: PlaybackRules?)

/** Talks to Curated's sync server on the Mac. All calls block; run them on Dispatchers.IO. */
class SyncClient(val host: String, val port: Int, private val token: String? = null) {
    private val base = "http://${if (':' in host) "[$host]" else host}:$port"

    /** Name and API version; answers without a token, so it's a quick "is the Mac there?" check. */
    fun info(timeoutMs: Int = 2000): JSONObject = JSONObject(request("GET", "/info", timeoutMs = timeoutMs))

    fun pair(code: String, deviceName: String): JSONObject =
        JSONObject(request("POST", "/pair", JSONObject().put("code", code).put("deviceName", deviceName)))

    /**
     * Short videos only unless `forms` asks for long ones too, and the Vines with `vine` (a Mac from before long
     * videos or Vines ignores what it doesn't know).
     */
    fun manifest(forms: SyncForms = SyncForms.Short, vine: Boolean = false): String {
        val query = listOfNotNull(if (forms == SyncForms.Short) null else "forms=${forms.query}", if (vine) "vine=1" else null)
        return request("GET", "/manifest" + if (query.isEmpty()) "" else query.joinToString("&", prefix = "?"))
    }

    /** Sends this phone's watched history, Watch Later list and bookmarks; returns the Mac's merged ones. */
    fun played(
        marks: Map<String, PlayedMark>, watchLater: Map<String, WatchLaterMark>, bookmarks: Map<String, WatchLaterMark>,
    ): Triple<Map<String, PlayedMark>, Map<String, WatchLaterMark>, Map<String, WatchLaterMark>> {
        val body = JSONObject().put("marks", PlayedMark.toJson(marks)).put("watchLater", WatchLaterMark.toJson(watchLater))
            .put("bookmarks", WatchLaterMark.toJson(bookmarks))
        val response = JSONObject(request("POST", "/played", body))
        return Triple(
            PlayedMark.fromJson(response.getJSONObject("marks")),
            WatchLaterMark.fromJson(response.optJSONObject("watchLater")),
            // An older Mac doesn't know bookmarks yet; keep ours.
            response.optJSONObject("bookmarks")?.let { WatchLaterMark.fromJson(it) } ?: bookmarks,
        )
    }

    /**
     * Sends where this phone left off in long videos; returns the Mac's merged positions. Macs older than API 4 answer
     * with an error.
     */
    fun positions(marks: Map<String, PositionMark>, nowPlaying: NowPlayingMark, playback: PlaybackRules): PositionsReply {
        val body = JSONObject().put("positions", PositionMark.toJson(marks)).put("nowPlaying", nowPlaying.toJson()).put("playback", playback.toJson())
        val reply = JSONObject(request("POST", "/positions", body))
        return PositionsReply(
            PositionMark.fromJson(reply.optJSONObject("positions")),
            NowPlayingMark.fromJson(reply.optJSONObject("nowPlaying")),
            PlaybackRules.fromJson(reply.optJSONObject("playback")),
        )
    }

    /** Asks the Mac to start a total download; returns why not, or null if it did. Macs older than API 6 answer 404. */
    fun forceDownload(): String? {
        val reply = JSONObject(request("POST", "/download", JSONObject()))
        return if (reply.optBoolean("started")) null else reply.getString("message")
    }

    /** The add-creator form. A Mac older than API 10 answers 404. */
    fun creatorForm(): CreatorForm = CreatorForm.fromJson(JSONObject(request("GET", "/creators/form")))

    fun addCreator(formVersion: Int, values: Map<String, String>): JSONObject =
        JSONObject(request("POST", "/creators", JSONObject().put("formVersion", formVersion).put("values", JSONObject(values))))

    /** Follows the Mac's listing of a creator's older videos. Returns when it's done; cancelling closes it at the next event. */
    suspend fun followOlderVideos(creator: String, onEvent: suspend (OlderVideosEvent) -> Unit) {
        withContext(Dispatchers.IO) {
            val connection = open("GET", "/creators/$creator/older", 30_000)
            try {
                val status = connection.responseCode
                if (status !in 200..299) throw errorFrom(connection, status)
                connection.inputStream.bufferedReader().use { reader ->
                    while (true) {
                        ensureActive()
                        val line = reader.readLine() ?: break
                        if (!line.startsWith("data: ")) continue
                        val json = JSONObject(line.removePrefix("data: "))
                        val event = OlderVideosEvent(
                            json.optJSONArray("videos").objects().map {
                                OlderVideo(
                                    it.getString("id"), it.optString("title").ifEmpty { null },
                                    runCatching { Instant.parse(it.getString("date")) }.getOrNull(),
                                    if (it.has("duration")) it.getDouble("duration") else null,
                                )
                            },
                            json.optString("error").ifEmpty { null },
                        )
                        withContext(Dispatchers.Main) { onEvent(event) }
                    }
                }
            } finally {
                connection.disconnect()
            }
        }
    }

    fun requestOlderVideos(creator: String, ids: List<String>, skip: List<String>, heights: Map<String, Int>): JSONObject =
        JSONObject(
            request(
                "POST", "/creators/$creator/older",
                JSONObject().put("ids", JSONArray(ids)).put("skip", JSONArray(skip)).put("heights", JSONObject(heights as Map<*, *>)),
            ),
        )

    fun olderThumbnail(id: String): ByteArray {
        val connection = open("GET", "/older-thumbnail/$id", 30_000)
        try {
            val status = connection.responseCode
            if (status !in 200..299) throw errorFrom(connection, status)
            return connection.inputStream.use { it.readBytes() }
        } finally {
            connection.disconnect()
        }
    }

    /**
     * Follows the Mac's download, calling `onEvent` about once a second. Returns when the Mac closes the connection,
     * which it does when nothing's downloading. Cancelling closes it from this end, at the next event.
     */
    suspend fun followDownload(onEvent: suspend (MacDownloadProgress) -> Unit) {
        val connection = open("GET", "/download/progress", 15_000)
        try {
            val status = connection.responseCode
            if (status !in 200..299) throw errorFrom(connection, status)
            connection.inputStream.bufferedReader().use { reader ->
                while (true) {
                    val line = reader.readLine() ?: break
                    if (line.startsWith("data: ")) onEvent(MacDownloadProgress.parse(JSONObject(line.removePrefix("data: "))))
                }
            }
        } finally {
            connection.disconnect()
        }
    }

    /** Downloads to `partial`, resuming where a previous attempt stopped, then renames it to `dest`. */
    fun download(path: String, partial: File, dest: File, onBytes: (Long) -> Unit) {
        val resumeFrom = if (partial.exists()) partial.length() else 0L
        val connection = open("GET", path, timeoutMs = 15_000)
        if (resumeFrom > 0) connection.setRequestProperty("Range", "bytes=$resumeFrom-")
        try {
            val status = connection.responseCode
            if (status !in 200..299) throw errorFrom(connection, status)
            val append = status == 206
            if (!append) onBytes(-resumeFrom)  // server sent the whole file again
            connection.inputStream.use { input ->
                java.io.FileOutputStream(partial, append).use { output ->
                    val buffer = ByteArray(256 * 1024)
                    while (true) {
                        val n = input.read(buffer)
                        if (n < 0) break
                        output.write(buffer, 0, n)
                        onBytes(n.toLong())
                    }
                }
            }
            if (!partial.renameTo(dest)) throw IOException("Couldn't save ${dest.name}")
        } finally {
            connection.disconnect()
        }
    }

    private fun request(method: String, path: String, body: JSONObject? = null, timeoutMs: Int = 15_000): String {
        val connection = open(method, path, timeoutMs)
        try {
            if (body != null) {
                connection.doOutput = true
                connection.setRequestProperty("Content-Type", "application/json")
                connection.outputStream.use { it.write(body.toString().toByteArray()) }
            }
            val status = connection.responseCode
            if (status !in 200..299) throw errorFrom(connection, status)
            return connection.inputStream.bufferedReader().use { it.readText() }
        } finally {
            connection.disconnect()
        }
    }

    private fun open(method: String, path: String, timeoutMs: Int): HttpURLConnection =
        (URL(base + path).openConnection() as HttpURLConnection).apply {
            requestMethod = method
            connectTimeout = timeoutMs
            readTimeout = maxOf(timeoutMs, 15_000)
            token?.let { setRequestProperty("Authorization", "Bearer $it") }
        }

    private fun errorFrom(connection: HttpURLConnection, status: Int): SyncException {
        val message = runCatching {
            JSONObject(connection.errorStream.bufferedReader().use { it.readText() }).getString("error")
        }.getOrNull()
        return SyncException(message ?: "The Mac answered with error $status", status)
    }

    companion object {
        const val DEFAULT_PORT = 8765
    }
}

data class FoundMac(val name: String, val host: String, val port: Int)

/** Finds Macs advertising Curated's sync service on this network. */
object Discovery {
    private const val SERVICE_TYPE = "_curated._tcp."

    /** With `name`, stops as soon as that Mac appears and only looks that one up, rather than waiting out `durationMs`. */
    suspend fun find(context: Context, durationMs: Long = 3000, name: String? = null): List<FoundMac> {
        val nsd = context.getSystemService(NsdManager::class.java) ?: return emptyList()
        val services = mutableListOf<NsdServiceInfo>()
        val listener = object : NsdManager.DiscoveryListener {
            override fun onServiceFound(info: NsdServiceInfo) { synchronized(services) { services.add(info) } }
            override fun onServiceLost(info: NsdServiceInfo) {}
            override fun onDiscoveryStarted(type: String) {}
            override fun onDiscoveryStopped(type: String) {}
            override fun onStartDiscoveryFailed(type: String, error: Int) {}
            override fun onStopDiscoveryFailed(type: String, error: Int) {}
        }
        withContext(Dispatchers.Main) { nsd.discoverServices(SERVICE_TYPE, NsdManager.PROTOCOL_DNS_SD, listener) }
        val deadline = System.currentTimeMillis() + durationMs
        while (System.currentTimeMillis() < deadline && (name == null || synchronized(services) { services.none { it.serviceName == name } })) {
            delay(if (name == null) 250 else 25)
        }
        withContext(Dispatchers.Main) { runCatching { nsd.stopServiceDiscovery(listener) } }
        val unique = synchronized(services) { services.distinctBy { it.serviceName } }.filter { name == null || it.serviceName == name }
        // Older Androids can only resolve one service at a time.
        return unique.mapNotNull { resolve(nsd, it) }.distinctBy { it.name }
    }

    @Suppress("DEPRECATION")
    private suspend fun resolve(nsd: NsdManager, info: NsdServiceInfo): FoundMac? = withTimeoutOrNull(3000) {
        suspendCancellableCoroutine { continuation ->
            nsd.resolveService(info, object : NsdManager.ResolveListener {
                override fun onServiceResolved(resolved: NsdServiceInfo) {
                    val host = resolved.host?.hostAddress
                    if (continuation.isActive) {
                        continuation.resume(host?.let { FoundMac(resolved.serviceName, it.substringBefore('%'), resolved.port) })
                    }
                }

                override fun onResolveFailed(failed: NsdServiceInfo, error: Int) {
                    if (continuation.isActive) continuation.resume(null)
                }
            })
        }
    }
}
