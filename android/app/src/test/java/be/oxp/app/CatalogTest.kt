package be.oxp.app

import org.junit.Assert.*
import org.junit.Test
import java.time.Instant

class CatalogTest {
    private fun feed(catalog: Catalog) = catalog.copy(schemaVersion = 1, generatedAt = Instant.parse("2026-09-05T00:00:00Z"))
    private fun bundled() = javaClass.classLoader!!.getResourceAsStream("catalog.json")!!.bufferedReader().use { CatalogCodec.decode(it.readText()) }
    @Test fun bundledCatalogContainsSeparateEditionsAndValidGlobalIds() {
        val catalog = bundled()
        assertEquals(5, catalog.events.size)
        assertEquals(9099, catalog.defaultEventId)
        assertEquals(listOf(9099), catalog.events.filter { it.hasMap }.map { it.id })
        assertEquals(feed(catalog), CatalogCodec.validate(feed(catalog), catalog))
        assertTrue(catalog.events.first { it.id == 9099 }.talks.isNotEmpty())
        val emptyEdition = catalog.events.first().copy(talks = emptyList())
        assertTrue(emptyEdition.activeTalks.isEmpty())
        assertTrue(emptyEdition.days.isEmpty())
        assertTrue(catalog.events.flatMap { it.talks }.any { it.matches("odoo") })
    }
    @Test fun rejectsRollbackMissingEditionAndDuplicateTrackIds() {
        val catalog = feed(bundled())
        fun rejects(candidate: Catalog) { assertThrows(IllegalArgumentException::class.java) { CatalogCodec.validate(candidate, catalog) } }
        rejects(catalog.copy(generatedAt = catalog.generatedAt!!.minusSeconds(1)))
        rejects(catalog.copy(events = catalog.events.drop(1)))
        val first = catalog.events.first { it.id == 9099 }
        rejects(catalog.copy(events = catalog.events.map { if (it.id == first.id) first.copy(talks = first.talks + first.talks.first()) else it }))
        rejects(catalog.copy(events = catalog.events.map { if (it.id == first.id) first.copy(talks = emptyList()) else it }))
        rejects(catalog.copy(generatedAt = Instant.now().plusSeconds(7200)))
    }
    @Test fun validatesTimeZonesAndIntervals() {
        val catalog = feed(bundled())
        val event = catalog.events.first { it.id == 9099 }
        val track = event.talks.first { it.start != null && it.end != null }
        fun withTrack(talk: Talk) = catalog.copy(events = catalog.events.map { edition -> if (edition.id == event.id) edition.copy(talks = edition.talks.map { if (it.id == talk.id) talk else it }) else edition })
        assertThrows(Exception::class.java) { CatalogCodec.validate(withTrack(track.copy(timezone = "Invalid/Zone")), catalog) }
        assertThrows(IllegalArgumentException::class.java) { CatalogCodec.validate(withTrack(track.copy(end = track.start!!.minusSeconds(1))), catalog) }
        assertFalse(track.happening(track.end!!))
    }
    @Test fun touchingTalksDoNotConflictAndOverlapsDo() {
        val template = bundled().events.first { it.id == 9099 }.talks.first()
        val a = template.copy(id = 1, start = Instant.parse("2026-09-24T08:00:00Z"), end = Instant.parse("2026-09-24T09:00:00Z"), unavailable = false)
        val b = a.copy(id = 2, start = a.end, end = a.end!!.plusSeconds(3600))
        val c = a.copy(id = 3, start = a.start!!.plusSeconds(1800), end = a.end)
        assertTrue(conflictingIds(listOf(a, b)).isEmpty())
        assertEquals(setOf(1, 3), conflictingIds(listOf(a, b, c)))
        assertTrue(conflictingIds(listOf(a, c.copy(unavailable = true))).isEmpty())
        assertEquals(listOf(0, 1, 0), agendaLanes(listOf(b, c, a)).map { it.lane })
    }
    @Test fun feedRefreshUsesRealConferenceWindowsAndTwoHourThrottle() {
        val active = Instant.parse("2026-09-24T12:00:00Z")
        assertTrue(automaticRefreshDue(active, null))
        assertFalse(automaticRefreshDue(active, active.minusSeconds(7199)))
        assertTrue(automaticRefreshDue(active, active.minusSeconds(7200)))
        assertFalse(automaticRefreshDue(Instant.parse("2026-09-05T12:00:00Z"), null))
    }
    @Test fun sharedAgendaEventsAppearInEveryRoomWithoutInventingRoomAssignments() {
        val event = bundled().events.first { it.id == 9099 }
        val day = event.activeTalks.filter { it.day == "2026-09-24" && it.start != null && it.end != null }
        val columns = agendaColumns(day)
        assertFalse("All venues" in columns.keys)
        val keynote = day.first { it.kind == "keynote" && it.location == null }
        assertTrue(columns.size > 1)
        columns.forEach { (room, talks) ->
            assertEquals(1, talks.count { it.id == keynote.id })
            assertTrue(talks.filterNot(::isSharedAgendaEvent).all { agendaRoom(it) == room })
        }
        val filtered = agendaColumns(listOf(keynote), day)
        assertEquals(columns.keys, filtered.keys)
        assertTrue(filtered.values.all { it.single().id == keynote.id })
        val unknown = keynote.copy(id = -1, kind = "talk", name = "Unassigned session")
        assertFalse(isSharedAgendaEvent(unknown))
        assertEquals(setOf("Room TBA"), agendaColumns(listOf(unknown)).keys)
        assertEquals(listOf(keynote), agendaColumns(listOf(keynote)).getValue("Venue"))
    }
    @Test fun sponsorLinksAreNormalizedAndNonWebSchemesRejected() {
        assertEquals("https://example.com", safeUrl("http:// https://example.com"))
        assertEquals("https://example.com", safeUrl("example.com"))
        assertEquals("https://www.odoo.com/test", safeUrl("/test"))
        assertNull(safeUrl("javascript:alert(1)"))
        assertNull(safeUrl("file:///etc/passwd"))
        assertNull(safeUrl("https://"))
    }
    @Test fun mapHasRoomsAndAuditoriumAliases() {
        val event = bundled().events.first { it.id == 9099 }
        val roomRefs = venueFeatures.map { it.ref }.toSet()
        event.activeTalks.mapNotNull { it.location }.distinct().filter { it.startsWith("Hall ") || it.startsWith("Auditorium ") || it == "Education Village" }.forEach { assertTrue("Missing room: $it", mapRef(it) in roomRefs) }
        assertEquals(229, venueBooths.size)
        assertEquals(229, venueBooths.map { it.ref }.distinct().size)
        assertEquals(4, mapLocations("Main stage").size)
        assertEquals(3, mapLocations("Auditorium 2000").size)
        assertTrue(venueFeatures.all { it.x >= 0 && it.y >= 0 && it.x + it.width <= 1.01f && it.y + it.height <= 1.01f })
    }
}
