package be.oxp.app

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.compose.foundation.background
import androidx.compose.foundation.BorderStroke
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import coil.compose.AsyncImage
import androidx.compose.material.icons.automirrored.filled.EventNote
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import java.time.Instant
import java.time.LocalDate
import java.time.format.DateTimeFormatter

fun dayLabel(day: String) = runCatching { LocalDate.parse(day).format(DateTimeFormatter.ofPattern("EEE, d MMM")) }.getOrDefault(day)
fun openUrl(context: Context, url: String?) {
    safeUrl(url)?.let { runCatching { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(it))) } }
}

@Composable
fun EmptyState(title: String, description: String, action: (() -> Unit)? = null) {
    Column(Modifier.fillMaxWidth().padding(32.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Icon(Icons.AutoMirrored.Filled.EventNote, null, Modifier.size(40.dp), tint = MaterialTheme.colorScheme.primary)
        Text(title, style = MaterialTheme.typography.titleLarge)
        if (description.isNotBlank()) Text(description, style = MaterialTheme.typography.bodyMedium)
        if (action != null) Button(onClick = action) { Text("Explore schedule") }
    }
}
@Composable
fun Heading(title: String) {
    Row(Modifier.padding(top = 12.dp, bottom = 4.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        val icon = when (title) { "Happening now" -> Icons.Default.Sensors; "Coming up", "Up next" -> Icons.Default.Schedule; "Discover the program" -> Icons.Default.AutoAwesome; "Speakers" -> Icons.Default.People; else -> null }
        if (icon != null) Icon(icon, null, Modifier.size(19.dp), tint = MaterialTheme.colorScheme.primary)
        Text(title, style = MaterialTheme.typography.titleLarge)
    }
}

@Composable
fun TalkCard(talk: Talk, saved: Boolean, open: () -> Unit, toggle: () -> Unit, showDay: Boolean = false, conflict: Boolean = false) {
    Card(onClick = open, modifier = Modifier.fillMaxWidth(), shape = RoundedCornerShape(20.dp), colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface), border = BorderStroke(.5.dp, MaterialTheme.colorScheme.outlineVariant)) {
        Row(Modifier.padding(18.dp), verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(7.dp)) {
                Box(Modifier.width(3.dp).height(44.dp).background(talkAccent(talk), RoundedCornerShape(2.dp)))
                Column(Modifier.width(44.dp)) {
                    Text(talk.startTime ?: "TBA", style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    talk.endTime?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = .65f)) }
                }
            }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                if (showDay) Text(talk.day?.let(::dayLabel) ?: "Date TBA", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.primary)
                Text(talk.name, style = MaterialTheme.typography.titleMedium)
                talk.speakerLine?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 2, overflow = TextOverflow.Ellipsis) }
                Text(talk.location ?: "Room TBA", style = MaterialTheme.typography.labelSmall, color = roomColor(talk.location))
                TalkTags(talk)
                if (talk.unavailable) Text("No longer on the agenda", color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.labelMedium)
                if (conflict) Text("Overlaps another saved talk", color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.labelMedium)
            }
            IconButton(onClick = toggle, modifier = Modifier.size(48.dp)) { Icon(if (saved) Icons.Default.Favorite else Icons.Default.FavoriteBorder, if (saved) "Unsave ${talk.name}" else "Save ${talk.name}", modifier = Modifier.size(20.dp), tint = if (saved) OxpRose else MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = .6f)) }
        }
    }
}

@Composable
fun TodayScreen(event: Edition, now: Instant, saved: Set<Int>, open: (Talk) -> Unit, toggle: (Talk) -> Unit, schedule: () -> Unit) {
    val context = LocalContext.current
    val live = event.activeTalks.filter { it.happening(now) }.sortedBy { it.location }
    val next = event.activeTalks.filter { it.start?.isAfter(now) == true }.sortedBy { it.start }.take(12)
    val featured = event.activeTalks.sortedBy { if (it.kind == "keynote") 0 else if (it.tags.any { tag -> tag.name == "Invited Speaker" }) 1 else 2 }.take(8)
    val local = now.atZone(event.zone)
    LazyColumn(contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        item {
            Column(Modifier.fillMaxWidth().background(Brush.linearGradient(listOf(Color(0xFF573354), Color(0xFF875675))), RoundedCornerShape(24.dp)).clip(RoundedCornerShape(24.dp)).drawBehind {
                drawCircle(Color.White.copy(alpha = .06f), radius = 86.dp.toPx(), center = Offset(size.width - 8.dp.toPx(), 4.dp.toPx()), style = Stroke(22.dp.toPx()))
                drawCircle(Color.White.copy(alpha = .08f), radius = 114.dp.toPx(), center = Offset(size.width - 8.dp.toPx(), 4.dp.toPx()), style = Stroke(1.dp.toPx()))
            }.padding(22.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text("YOUR CONFERENCE COMPANION", color = Color(0xFFE8CADF), style = MaterialTheme.typography.labelLarge)
                Text("Odoo Experience 2026", color = Color.White, style = MaterialTheme.typography.headlineMedium)
                Text(event.shortName, color = Color(0xFFE8CADF), style = MaterialTheme.typography.titleMedium)
                Text("${event.startsOn?.let(::dayLabel) ?: "Dates TBA"}${if (event.endsOn != event.startsOn) " – ${event.endsOn?.let(::dayLabel) ?: ""}" else ""}", color = Color.White)
                Text(event.venue, color = Color.White)
                Text("${local.format(DateTimeFormatter.ofPattern("EEE d MMM · HH:mm"))} · ${event.timezone}", color = Color(0xFFE8CADF), style = MaterialTheme.typography.bodySmall)
                Button(onClick = schedule, colors = ButtonDefaults.buttonColors(containerColor = Color.White.copy(alpha = .16f), contentColor = Color.White)) { Text("Explore schedule  →") }
            }
        }
        if (live.isNotEmpty()) {
            item { Heading("Happening now") }
            items(live, key = { "live-${it.id}" }) { TalkCard(it, it.id in saved, { open(it) }, { toggle(it) }) }
        }
        if (next.isNotEmpty()) {
            item { Heading(if (live.isEmpty()) "Coming up" else "Up next") }
            items(next, key = { "next-${it.id}" }) { TalkCard(it, it.id in saved, { open(it) }, { toggle(it) }, showDay = true) }
        }
        if (event.activeTalks.isEmpty()) item { EmptyState("Program coming soon", "This edition hasn’t published its talks yet. You can explore its exhibitors in Expo.") }
        if (live.isEmpty() && featured.isNotEmpty()) {
            item { Heading("Discover the program") }
            items(featured, key = { "featured-${it.id}" }) { TalkCard(it, it.id in saved, { open(it) }, { toggle(it) }, showDay = true) }
        }
        item { Text("Built with ♥ from Brussels · Not an official app", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
    }
}

@Composable
fun ScheduleScreen(event: Edition, now: Instant, saved: Set<Int>, open: (Talk) -> Unit, toggle: (Talk) -> Unit) {
    val days = event.days
    var day by rememberSaveable(event.id) { mutableStateOf(days.find { it == now.atZone(event.zone).toLocalDate().toString() } ?: days.firstOrNull().orEmpty()) }
    var query by rememberSaveable(event.id) { mutableStateOf("") }
    var kind by rememberSaveable(event.id) { mutableStateOf<String?>(null) }
    var tag by rememberSaveable(event.id) { mutableStateOf<Int?>(null) }
    var grid by rememberSaveable { mutableStateOf(false) }
    var savedOnly by rememberSaveable { mutableStateOf(false) }
    var tagMenu by remember { mutableStateOf(false) }
    LaunchedEffect(days) { if (day !in days) day = days.firstOrNull().orEmpty() }
    val talks = remember(event, day, query, kind, tag, savedOnly, saved) { event.activeTalks.filter { (it.day == day || days.isEmpty()) && it.matches(query) && (kind == null || it.kind == kind) && (tag == null || it.tags.any { t -> t.id == tag } || it.kind in setOf("break", "social", "opening")) && (!savedOnly || it.id in saved) }.sortedWith(compareBy({ it.start }, { it.location }, { it.name })) }
    Column {
        OxpSearch(query, { query = it }, "Talks, speakers, rooms", Modifier.padding(horizontal = 16.dp))
        Row(Modifier.horizontalScroll(rememberScrollState()).padding(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            days.forEach { date -> OxpChip(selected = day == date, onClick = { day = date }, label = { Text(dayLabel(date)) }) }
        }
        Row(Modifier.horizontalScroll(rememberScrollState()).padding(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Box {
                OxpChip(tag != null, { tagMenu = true }, label = { Text(event.tags.find { it.id == tag }?.name ?: "Topics & audience") })
                DropdownMenu(tagMenu, { tagMenu = false }) {
                    DropdownMenuItem(text = { Text("All topics & audiences") }, onClick = { tag = null; tagMenu = false })
                    event.tags.forEach { t -> DropdownMenuItem(text = { Text(t.name) }, onClick = { tag = t.id; tagMenu = false }) }
                }
            }
            OxpChip(kind == null, { kind = null }, label = { Text("All kinds") })
            event.activeTalks.map { it.kind }.distinct().forEach { k -> OxpChip(kind == k, { kind = k }, label = { Text(if (k == "social") "Concert" else k.replaceFirstChar { it.uppercase() }) }) }
        }
        Row(Modifier.padding(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            OxpChip(!grid, { grid = false }, label = { Text("List") })
            OxpChip(grid, { grid = true }, label = { Text("Agenda") })
            OxpChip(savedOnly, { savedOnly = !savedOnly }, label = { Text("Saved only") })
        }
        Text("${talks.size} talks · ${event.timezone}", Modifier.padding(horizontal = 16.dp, vertical = 4.dp), style = MaterialTheme.typography.labelSmall)
        if (talks.isEmpty()) Column(Modifier.verticalScroll(rememberScrollState())) {
            EmptyState("No matching talks", "Try another day or clear your filters.")
            TextButton(onClick = { query = ""; kind = null; tag = null; savedOnly = false }, modifier = Modifier.align(Alignment.CenterHorizontally)) { Text("Clear filters") }
        } else if (grid) AgendaGrid(talks, event, now, saved, open)
        else LazyColumn(contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            talks.groupBy { it.startTime ?: "Time TBA" }.forEach { (slot, tracks) ->
                item(key = "slot-$slot") { Heading(slot) }
                items(tracks, key = { it.id }) { TalkCard(it, it.id in saved, { open(it) }, { toggle(it) }) }
            }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun TalkDetails(talk: Talk, event: Edition, saved: Boolean, toggle: () -> Unit, map: (String) -> Unit) {
    val context = LocalContext.current
    LazyColumn(contentPadding = PaddingValues(20.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        item { Text(talk.kindLabel, color = MaterialTheme.colorScheme.primary, style = MaterialTheme.typography.labelLarge) }
        item { Text(talk.name, style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold) }
        item { Text("${event.shortName} · ${talk.day?.let(::dayLabel) ?: "Date TBA"}\n${talk.timeLabel} · ${event.timezone}\n${talk.location ?: "Room TBA"}", style = MaterialTheme.typography.bodyLarge) }
        if (talk.unavailable) item { Text("This talk is no longer on the agenda. Its reminder has been cancelled.", color = MaterialTheme.colorScheme.error) }
        item {
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Button(onClick = toggle) { Icon(if (saved) Icons.Default.Favorite else Icons.Default.FavoriteBorder, null); Spacer(Modifier.width(8.dp)); Text(if (saved) "Saved · Remove" else "Save talk") }
                if (event.hasMap && talk.location != null) OutlinedButton(onClick = { map(talk.location) }) { Text("Show on map") }
                if (talk.url != null) {
                    OutlinedButton(onClick = { openUrl(context, talk.url) }) { Text("Official page") }
                    OutlinedButton(onClick = { context.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, "${talk.name}\n${talk.url}"), "Share talk")) }) { Text("Share") }
                }
            }
        }
        if (talk.tags.isNotEmpty()) item { FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) { talk.tags.forEach { SuggestionChip(onClick = {}, label = { Text(it.name) }) } } }
        item { Text(talk.description ?: if (talk.comingSoon) "Details are coming soon." else "No description has been published yet.", style = MaterialTheme.typography.bodyLarge) }
        if (talk.speakers.isNotEmpty()) item { Heading("Speakers") }
        items(talk.speakers) { speaker ->
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    RemotePortrait(speaker.imageUrl, speaker.name)
                    Text(speaker.name, style = MaterialTheme.typography.titleLarge)
                }
                if (speaker.affiliation.isNotEmpty()) Text(speaker.affiliation, color = MaterialTheme.colorScheme.primary)
                speaker.biography?.let { Text(it) }
            }
        }
    }
}

@Composable
fun ExpoScreen(event: Edition, open: (Exhibitor) -> Unit) {
    var query by rememberSaveable(event.id) { mutableStateOf("") }
    var level by rememberSaveable(event.id) { mutableStateOf<String?>(null) }
    val filtered = event.exhibitors.filter { (level == null || it.level == level) && listOfNotNull(it.name, it.slogan, it.country).any { value -> value.contains(query.trim(), true) } }
    Column {
        OxpSearch(query, { query = it }, "Companies, countries, expertise", Modifier.padding(horizontal = 16.dp))
        Row(Modifier.horizontalScroll(rememberScrollState()).padding(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            OxpChip(level == null, { level = null }, label = { Text("All exhibitors") })
            event.exhibitors.map { it.level }.distinct().forEach { l -> OxpChip(level == l, { level = l }, label = { Text(l) }) }
        }
        LazyColumn(contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            if (filtered.isEmpty()) item { EmptyState("No exhibitors found", "Try another search or filter. This edition may not have published its exhibitor list yet.") }
            items(filtered, key = { it.id }) { exhibitor ->
                Card(onClick = { open(exhibitor) }, modifier = Modifier.fillMaxWidth(), shape = RoundedCornerShape(20.dp), colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface), border = BorderStroke(.5.dp, MaterialTheme.colorScheme.outlineVariant)) {
                    Column(Modifier.padding(18.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        Text(exhibitor.level, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.primary)
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                            RemotePortrait(exhibitor.logoUrl, exhibitor.name, logo = true)
                            Text(exhibitor.name, style = MaterialTheme.typography.titleLarge)
                        }
                        exhibitor.slogan?.let { Text(it) }
                        exhibitor.country?.let { Text(it, style = MaterialTheme.typography.bodySmall) }
                    }
                }
            }
        }
    }
}
@Composable
fun ExhibitorDetails(exhibitor: Exhibitor, event: Edition, map: () -> Unit) {
    val context = LocalContext.current
    Column(Modifier.verticalScroll(rememberScrollState()).padding(20.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Text(exhibitor.level, color = MaterialTheme.colorScheme.primary)
        RemotePortrait(exhibitor.logoUrl, exhibitor.name, logo = true)
        Text(exhibitor.name, style = MaterialTheme.typography.headlineLarge)
        exhibitor.country?.let { Text(it) }
        exhibitor.slogan?.let { Text(it, style = MaterialTheme.typography.bodyLarge) }
        if (event.hasMap) {
            Text("Individual exhibitor booth assignments are not published in the catalog.")
            Button(onClick = map) { Text("Show expo halls") }
        }
        exhibitor.website?.let { OutlinedButton(onClick = { openUrl(context, it) }) { Text("Visit website") } }
        exhibitor.url?.let { OutlinedButton(onClick = { openUrl(context, it) }) { Text("Official exhibitor page") } }
    }
}

@Composable
fun SavedScreen(model: OxpModel, open: (Talk) -> Unit, toggle: (Talk) -> Unit, schedule: () -> Unit) {
    val groups = model.catalog?.events.orEmpty().map { it to it.talks.filter { talk -> talk.id in model.savedIds }.sortedBy { talk -> talk.start ?: Instant.MAX } }.filter { it.second.isNotEmpty() }
    LazyColumn(contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        if (groups.isEmpty()) item { EmptyState("Make it your experience", "Build your own lineup by saving talks from the schedule.", schedule) }
        else {
            item { Heading("Your conference, your way"); Text("${model.savedIds.size} saved ${if (model.savedIds.size == 1) "talk" else "talks"} · ${if (model.notificationsEnabled) "Reminders enabled" else "Reminders are off — enable them in Settings"}") }
            groups.forEach { (event, talks) ->
                val conflicts = conflictingIds(talks)
                item(key = "event-${event.id}") { Heading(event.shortName) }
                items(talks, key = { it.id }) { TalkCard(it, true, { open(it) }, { toggle(it) }, showDay = true, conflict = it.id in conflicts) }
            }
        }
    }
}

@Composable
fun SettingsScreen(model: OxpModel) {
    val context = LocalContext.current
    Column(Modifier.verticalScroll(rememberScrollState()).padding(20.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Heading("Agenda updates")
        Text(model.checked?.let { "Last checked: ${it.atZone(java.time.ZoneId.systemDefault()).format(DateTimeFormatter.ofPattern("d MMM yyyy, HH:mm"))}" } ?: "Using the bundled offline agenda")
        model.error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
        Button(onClick = { model.refresh() }, enabled = !model.refreshing) { Text(if (model.refreshing) "Checking…" else "Check for updates") }
        Heading("Talk reminders")
        Text(if (model.notificationsEnabled) "Reminders enabled" else "Reminders are off. Your talks are still saved.")
        OutlinedButton(onClick = { context.startActivity(Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)) }) { Text("Notification settings") }
        Text("Notify ${model.minutes} minutes before")
        Slider(model.minutes.toFloat(), { model.updateReminderMinutes((it.toInt() / 5) * 5) }, valueRange = 5f..60f, steps = 10)
        if (!model.exactReminders && Build.VERSION.SDK_INT >= 31) {
            Text("Android may delay reminders. Allow alarms for precise timing.")
            OutlinedButton(onClick = { context.startActivity(Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM, Uri.parse("package:${context.packageName}"))) }) { Text("Allow precise reminders") }
        }
        Heading("About OXP")
        Text("Unofficial Odoo Experience companion. Not affiliated with Odoo S.A.\nVersion 1.0")
        Text("Conference times use each edition’s local time zone. Saved talks stay on this device.")
        OutlinedButton(onClick = { openUrl(context, "https://oxp-site.jonathanbertholet.workers.dev/privacy/") }) { Text("Privacy policy") }
        OutlinedButton(onClick = { openUrl(context, "https://oxp-site.jonathanbertholet.workers.dev/support/") }) { Text("Support") }
    }
}

@Composable
private fun RemotePortrait(url: String?, name: String, logo: Boolean = false) {
    Box(Modifier.size(64.dp).clip(if (logo) RoundedCornerShape(12.dp) else CircleShape).background(if (logo) Color.White else MaterialTheme.colorScheme.secondaryContainer), contentAlignment = Alignment.Center) {
        Text(name.take(1).uppercase(), color = Color(0xFF714B67), style = MaterialTheme.typography.titleLarge)
        AsyncImage(model = url, contentDescription = name, modifier = Modifier.fillMaxSize(), contentScale = if (logo) ContentScale.Fit else ContentScale.Crop)
    }
}
