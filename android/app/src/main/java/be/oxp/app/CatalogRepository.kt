package be.oxp.app

import android.content.Context
import android.util.AtomicFile
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.time.Instant

/** A single atomic envelope keeps the catalog and its ETag consistent after interrupted writes. */
class CatalogRepository(context: Context) {
    private val app = context.applicationContext
    private val file = AtomicFile(File(app.filesDir, "agenda-cache.json"))
    private var cachedText: String? = null
    private var etag: String? = null
    var lastChecked: Instant? = null
        private set

    fun load(): Catalog {
        val bundled = app.assets.open("catalog.json").bufferedReader().use { CatalogCodec.decode(it.readText()) }
        return runCatching {
            val envelope = JSONObject(file.openRead().bufferedReader().use { it.readText() })
            val text = envelope.getString("catalog")
            val catalog = CatalogCodec.validate(CatalogCodec.decode(text), bundled)
            cachedText = text
            etag = envelope.optString("etag").takeIf { it.isNotBlank() }
            lastChecked = Instant.parse(envelope.getString("checked_at"))
            catalog
        }.getOrDefault(bundled)
    }

    fun refresh(baseline: Catalog): Catalog {
        val connection = URL(ENDPOINT).openConnection() as HttpURLConnection
        try {
            connection.connectTimeout = 15_000
            connection.readTimeout = 30_000
            connection.setRequestProperty("Accept", "application/json")
            etag?.let { connection.setRequestProperty("If-None-Match", it) }
            val text = when (connection.responseCode) {
                304 -> requireNotNull(cachedText)
                200 -> {
                    require(connection.contentLengthLong <= CatalogCodec.MAX_BYTES)
                    val bytes = connection.inputStream.use { input ->
                        val output = java.io.ByteArrayOutputStream()
                        val buffer = ByteArray(8192)
                        while (true) {
                            val count = input.read(buffer)
                            if (count < 0) break
                            require(output.size() + count <= CatalogCodec.MAX_BYTES)
                            output.write(buffer, 0, count)
                        }
                        output.toByteArray()
                    }
                    require(bytes.isNotEmpty() && bytes.size <= CatalogCodec.MAX_BYTES)
                    bytes.toString(Charsets.UTF_8)
                }
                else -> error("Unexpected feed response")
            }
            val catalog = CatalogCodec.validate(CatalogCodec.decode(text), baseline)
            val checked = Instant.now()
            val newTag = connection.getHeaderField("ETag") ?: etag.takeIf { connection.responseCode == 304 }
            val envelope = JSONObject().put("catalog", text).put("etag", newTag).put("checked_at", checked.toString()).toString()
            val output = file.startWrite()
            try { output.write(envelope.toByteArray()); file.finishWrite(output) }
            catch (error: Exception) { file.failWrite(output); throw error }
            cachedText = text; etag = newTag; lastChecked = checked
            return catalog
        } finally { connection.disconnect() }
    }

    companion object { const val ENDPOINT = "https://oxp-site.jonathanbertholet.workers.dev/agenda/catalog.json" }
}
