package be.oxp.app

import org.json.JSONArray
import org.json.JSONObject
import java.net.URI
import java.time.Instant
import java.time.ZoneId

private fun JSONObject.text(key: String): String? = if (isNull(key)) null else optString(key).takeIf { it.isNotBlank() }
private fun JSONObject.date(key: String): Instant? = text(key)?.let(Instant::parse)
private fun JSONArray?.objects(): List<JSONObject> = if (this == null) emptyList() else (0 until length()).map { getJSONObject(it) }

data class Tag(val id: Int, val name: String, val category: String?)
data class Speaker(val name: String, val affiliation: String, val biography: String?, val imageUrl: String?)
data class Talk(
    val id: Int, val name: String, val kind: String, val day: String?, val startTime: String?,
    val endTime: String?, val start: Instant?, val end: Instant?, val timezone: String,
    val location: String?, val speakerLine: String?, val description: String?, val url: String?,
    val unavailable: Boolean, val comingSoon: Boolean, val tags: List<Tag>, val speakers: List<Speaker>
) {
    val timeLabel get() = listOfNotNull(startTime, endTime).joinToString("–").ifEmpty { "Time TBA" }
    val kindLabel get() = when (kind) { "social" -> "Concert"; "tba" -> "Coming soon"; else -> kind.replaceFirstChar { it.uppercase() } }
    fun happening(now: Instant) = !unavailable && start != null && end != null && now >= start && now < end
    fun matches(query: String): Boolean = (listOfNotNull(name, speakerLine, location, description) + tags.map { it.name }).any { it.contains(query.trim(), ignoreCase = true) }
}
data class Exhibitor(val id: Int, val name: String, val slogan: String?, val level: String, val country: String?, val website: String?, val url: String?, val logoUrl: String?)
data class Edition(
    val id: Int, val name: String, val shortName: String, val timezone: String, val venue: String,
    val address: String, val startsOn: String?, val endsOn: String?, val hasMap: Boolean,
    val sourceChecked: Instant?, val website: String?, val talks: List<Talk>, val exhibitors: List<Exhibitor>
) {
    val zone: ZoneId get() = ZoneId.of(timezone)
    val activeTalks get() = talks.filterNot { it.unavailable }
    val days get() = activeTalks.mapNotNull { it.day }.distinct().sorted()
    val tags get() = activeTalks.flatMap { it.tags }.distinctBy { it.id }.sortedBy { it.name }
}
data class Catalog(val schemaVersion: Int, val generatedAt: Instant?, val defaultEventId: Int, val events: List<Edition>) {
    fun talk(id: Int) = events.asSequence().flatMap { it.talks.asSequence() }.firstOrNull { it.id == id }
    fun editionFor(id: Int) = events.firstOrNull { event -> event.talks.any { it.id == id } }
}

object CatalogCodec {
    const val MAX_BYTES = 8_000_000
    fun decode(text: String): Catalog {
        val root = JSONObject(text)
        return Catalog(root.optInt("schema_version"), root.date("generated_at"), root.optInt("default_event_id", 9099), root.getJSONArray("events").objects().map { payload ->
            val event = payload.getJSONObject("event")
            Edition(event.getInt("id"), event.getString("name"), event.text("short_name") ?: event.getString("name"), event.getString("timezone"), event.getString("venue_name"), event.getString("venue_address"), event.text("starts_on"), event.text("ends_on"), event.optBoolean("has_map", event.getInt("id") == 9099), event.date("source_checked_at"), safeUrl(event.text("website_url")), payload.getJSONArray("tracks").objects().map { t ->
                Talk(t.getInt("id"), t.getString("name"), t.optString("kind", "talk"), t.text("day"), t.text("start_time"), t.text("end_time"), t.date("starts_at"), t.date("ends_at"), t.getString("timezone"), t.text("location"), t.text("speaker_line"), t.text("description_text"), safeUrl(t.text("url")), t.optBoolean("unavailable"), t.optBoolean("coming_soon"), t.optJSONArray("tags").objects().map { Tag(it.getInt("id"), it.getString("name"), it.text("category")) }, t.optJSONArray("speakers").objects().map { Speaker(it.getString("name"), listOfNotNull(it.text("function"), it.text("company")).joinToString(" · "), it.text("biography_text"), safeUrl(it.text("image_url"))) })
            }, payload.optJSONArray("exhibitors").objects().map { Exhibitor(it.getInt("id"), it.getString("name"), it.text("slogan"), it.optString("level"), it.text("country"), safeUrl(it.text("website")), safeUrl(it.text("url")), safeUrl(it.text("logo_url"))) })
        })
    }

    fun validate(candidate: Catalog, baseline: Catalog, now: Instant = Instant.now()): Catalog {
        require(candidate.schemaVersion == 1 && candidate.generatedAt != null)
        require(candidate.generatedAt >= (baseline.generatedAt ?: Instant.MIN) && candidate.generatedAt < now.plusSeconds(3600))
        require(candidate.events.isNotEmpty())
        val eventIds = candidate.events.map { it.id }
        require(eventIds.distinct().size == eventIds.size && eventIds.containsAll(baseline.events.map { it.id }))
        val talks = candidate.events.flatMap { it.talks }
        require(talks.map { it.id }.distinct().size == talks.size)
        candidate.events.forEach { event ->
            ZoneId.of(event.timezone)
            baseline.events.find { it.id == event.id }?.let { old ->
                require(event.talks.size >= (old.talks.size * 0.9).toInt())
                require((event.sourceChecked ?: Instant.MIN) >= (old.sourceChecked ?: Instant.MIN))
            }
            event.talks.forEach { talk ->
                require(talk.name.isNotBlank()); ZoneId.of(talk.timezone)
                require(talk.start == null || talk.end == null || talk.end >= talk.start)
            }
        }
        return candidate
    }
}

fun safeUrl(raw: String?): String? = runCatching {
    var text = raw?.trim()?.takeIf { it.isNotEmpty() } ?: return null
    val https = text.indexOf("https://", ignoreCase = true)
    if (https >= 0) text = text.substring(https)
    text = text.replace(Regex("\\s+"), "")
    if (text.startsWith("/")) text = "https://www.odoo.com$text"
    if (!text.contains(":")) text = "https://$text"
    val uri = URI(text)
    text.takeIf { uri.scheme.lowercase() in setOf("http", "https") && !uri.host.isNullOrBlank() }
}.getOrNull()

fun conflictingIds(talks: List<Talk>): Set<Int> {
    val scheduled = talks.filter { !it.unavailable && it.start != null && it.end != null }
    return buildSet {
        scheduled.forEachIndexed { i, a -> scheduled.drop(i + 1).forEach { b ->
            if (a.start!! < b.end!! && b.start!! < a.end!!) { add(a.id); add(b.id) }
        } }
    }
}

fun automaticRefreshDue(now: Instant, lastAttempt: Instant?): Boolean {
    val windows = listOf("2026-09-08T18:30:00Z" to "2026-09-12T18:30:00Z", "2026-09-21T22:00:00Z" to "2026-09-26T22:00:00Z")
    return windows.any { now >= Instant.parse(it.first) && now < Instant.parse(it.second) } && (lastAttempt == null || now.epochSecond - lastAttempt.epochSecond >= 7200)
}
