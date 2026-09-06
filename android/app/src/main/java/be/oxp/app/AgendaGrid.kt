package be.oxp.app

import androidx.compose.foundation.background
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.Alignment
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.graphics.compositeOver
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import java.time.Instant

/** Greedy interval lanes keep simultaneous sessions in the same room individually tappable. */
data class AgendaPlacement(val talk: Talk, val lane: Int)
fun isSharedAgendaEvent(talk: Talk) = talk.location.isNullOrBlank() &&
    (talk.kind in setOf("keynote", "opening", "break", "social") || talk.name.trim().equals("Break", ignoreCase = true))
fun agendaRoom(talk: Talk) = talk.location?.takeIf { it.isNotBlank() } ?: "Room TBA"

/** Keep shared events in every real column, including when a filter hides the room's talks. */
fun agendaColumns(talks: List<Talk>, dayTalks: List<Talk> = talks): Map<String, List<Talk>> {
    val shared = talks.filter(::isSharedAgendaEvent)
    val local = talks.filterNot(::isSharedAgendaEvent)
    val rooms = (if (shared.isEmpty()) local else dayTalks.filterNot(::isSharedAgendaEvent))
        .map(::agendaRoom).distinct().ifEmpty { listOf("Venue") }
    val officialOrder = listOf("Hall 6.A", "Hall 6.B", "Hall 6.C", "Hall 6.D", "Hall 6.E", "Hall 7.A", "Hall 7.B", "Auditorium 500", "Auditorium 2000 A", "Auditorium 2000 B", "Auditorium 2000 C", "Auditorium 4000 A", "Auditorium 4000 B", "Auditorium 4000 C", "Auditorium 4000 D", "Education Village")
    return rooms.sortedWith(compareBy<String> { officialOrder.indexOf(it).takeIf { index -> index >= 0 } ?: Int.MAX_VALUE }.thenBy { it })
        .associateWith { room -> (local.filter { agendaRoom(it) == room } + shared).distinctBy { it.id } }
}

fun agendaLanes(talks: List<Talk>): List<AgendaPlacement> {
    val ends = mutableListOf<Instant>()
    return talks.filter { it.start != null && it.end != null }.sortedBy { it.start }.map { talk ->
        var lane = ends.indexOfFirst { it <= talk.start }
        if (lane < 0) { lane = ends.size; ends.add(talk.end!!) } else ends[lane] = talk.end!!
        AgendaPlacement(talk, lane)
    }
}
@Composable
fun AgendaGrid(talks: List<Talk>, event: Edition, now: Instant, saved: Set<Int>, open: (Talk) -> Unit) {
    val scheduled = talks.filter { it.start != null && it.end != null }
    val unscheduled = talks.filter { it.start == null || it.end == null }
    if (scheduled.isEmpty()) { EmptyState("Times coming soon", "Use List to see talks without a confirmed time."); return }
    val start = scheduled.minOf { it.start!! }.atZone(event.zone).withMinute(0).withSecond(0).toInstant()
    val end = scheduled.maxOf { it.end!! }.plusSeconds(3600).atZone(event.zone).withMinute(0).withSecond(0).toInstant()
    val minutes = ((end.epochSecond - start.epochSecond) / 60).toInt().coerceAtLeast(60)
    val columns = remember(talks, event) {
        val days = scheduled.mapNotNull { it.day }.toSet()
        agendaColumns(scheduled, event.activeTalks.filter { it.day in days && it.start != null && it.end != null })
    }
    val placementsByRoom = remember(columns) { columns.mapValues { agendaLanes(it.value) } }
    val scale = 4.8f * LocalDensity.current.fontScale.coerceAtLeast(1f)
    val laneWidth = 224
    val cardWidth = 212
    val vertical = rememberScrollState()
    val horizontal = rememberScrollState()
    Column {
        if (unscheduled.isNotEmpty()) Text("${unscheduled.size} talks without confirmed times — see List", Modifier.padding(horizontal = 16.dp), style = MaterialTheme.typography.labelSmall)
        Row(Modifier.horizontalScroll(horizontal).padding(horizontal = 16.dp)) {
            Spacer(Modifier.width(64.dp))
            placementsByRoom.forEach { (room, placements) ->
                val lanes = (placements.maxOfOrNull { it.lane } ?: 0) + 1
                Row(Modifier.width((laneWidth * lanes).dp).padding(top = 12.dp, bottom = 14.dp, end = 12.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Box(Modifier.width(4.dp).height(20.dp).background(roomColor(room), RoundedCornerShape(2.dp)))
                    Text(room, style = MaterialTheme.typography.titleSmall)
                }
            }
        }
        Row(Modifier.verticalScroll(vertical).horizontalScroll(horizontal).padding(horizontal = 16.dp)) {
            Box(Modifier.width(64.dp).height((minutes * scale).dp)) {
                for (minute in 0..minutes step 60) Text(start.plusSeconds(minute * 60L).atZone(event.zone).toLocalTime().toString(), Modifier.offset(y = (minute * scale).dp), style = MaterialTheme.typography.labelMedium)
            }
            placementsByRoom.forEach { (_, placements) ->
                val lanes = (placements.maxOfOrNull { it.lane } ?: 0) + 1
                Box(Modifier.width((laneWidth * lanes).dp).height((minutes * scale).dp)) {
                    for (minute in 0..minutes step 30) HorizontalDivider(Modifier.offset(y = (minute * scale).dp), color = MaterialTheme.colorScheme.outlineVariant)
                    placements.forEach { (talk, lane) ->
                        val top = (talk.start!!.epochSecond - start.epochSecond) / 60f * scale
                        val height = ((talk.end!!.epochSecond - talk.start.epochSecond) / 60f * scale).coerceAtLeast(50f)
                        AgendaCard(talk, talk.id in saved, height - 10,
                            Modifier.offset(x = (lane * laneWidth).dp, y = top.dp).width(cardWidth.dp).height((height - 10).dp),
                            open = { open(talk) })
                    }
                    if (now >= start && now < end) Box(Modifier.offset(y = ((now.epochSecond - start.epochSecond) / 60f * scale).dp).fillMaxWidth().height(2.dp).background(Color(0xFFC44152)))
                }
            }
        }
    }
}

@Composable
private fun AgendaCard(talk: Talk, saved: Boolean, height: Float, modifier: Modifier, open: () -> Unit) {
    val accent = talkAccent(talk)
    val tags = cardTags(talk)
    val fontScale = LocalDensity.current.fontScale
    val hasTags = tags.isNotEmpty()
    val showSpeaker = height / fontScale > 180 && talk.speakerLine != null
    val titleLines = ((height - 24 - (if (hasTags) 30 else 0) * fontScale - (if (showSpeaker) 24 else 0) * fontScale - 30 * fontScale) / (18 * fontScale)).toInt().coerceIn(1, 5)
    Card(onClick = open, modifier = modifier.semantics {
        contentDescription = listOfNotNull(talk.name, talk.timeLabel, talk.location, tags.joinToString { it.name }.takeIf { it.isNotBlank() }, "Saved".takeIf { saved }).joinToString(", ")
    }, shape = RoundedCornerShape(14.dp), border = BorderStroke(if (saved) 1.5.dp else .5.dp, if (saved) OxpRose else MaterialTheme.colorScheme.outlineVariant), colors = CardDefaults.cardColors(containerColor = accent.copy(alpha = .045f).compositeOver(MaterialTheme.colorScheme.surface))) {
        Row(Modifier.fillMaxSize().padding(12.dp), horizontalArrangement = Arrangement.spacedBy(9.dp)) {
            Box(Modifier.width(3.dp).fillMaxHeight().background(accent.copy(alpha = .85f), RoundedCornerShape(2.dp)))
            Column(Modifier.weight(1f).fillMaxHeight(), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    Text(talk.timeLabel, Modifier.weight(1f), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    if (saved) Icon(Icons.Default.Favorite, "Saved", Modifier.size(13.dp), tint = OxpRose)
                }
                Text(talk.name, style = MaterialTheme.typography.labelLarge, maxLines = titleLines, overflow = TextOverflow.Ellipsis)
                if (showSpeaker) Text(talk.speakerLine!!, style = MaterialTheme.typography.bodySmall, maxLines = 1, overflow = TextOverflow.Ellipsis, color = MaterialTheme.colorScheme.onSurfaceVariant)
                if (hasTags) {
                    if (height / fontScale <= 180) Spacer(Modifier.weight(1f))
                    TalkTags(talk, compact = true)
                }
            }
        }
    }
}
