package be.oxp.app

import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.content.res.Configuration
import androidx.compose.ui.graphics.toArgb
import android.graphics.RectF
import android.view.GestureDetector
import android.view.MotionEvent
import android.view.ScaleGestureDetector
import android.view.View
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import java.time.Instant

fun mapRef(location: String) = when {
    location.startsWith("Auditorium 4000") -> "Main stage"
    location.startsWith("Auditorium 2000") -> "Auditorium 2000"
    location == "Auditorium 500" -> "odoo-village"
    else -> location
}
fun mapLocations(ref: String) = when (ref) {
    "Main stage" -> listOf("Auditorium 4000 A", "Auditorium 4000 B", "Auditorium 4000 C", "Auditorium 4000 D")
    "Auditorium 2000" -> listOf("Auditorium 2000 A", "Auditorium 2000 B", "Auditorium 2000 C")
    "odoo-village" -> listOf("Auditorium 500")
    else -> listOf(ref)
}
@Composable
fun MapScreen(event: Edition, now: Instant, requestedRoom: String?, consumed: () -> Unit, saved: Set<Int>, open: (Talk) -> Unit, toggle: (Talk) -> Unit) {
    val focusManager = LocalFocusManager.current
    var hall by rememberSaveable { mutableStateOf("overview") }
    var selectedRef by rememberSaveable { mutableStateOf<String?>(null) }
    var query by rememberSaveable { mutableStateOf("") }
    var showPlace by rememberSaveable { mutableStateOf(false) }
    var reset by remember { mutableIntStateOf(0) }
    val halls = listOf("hall6" to "Hall 6", "hall7" to "Hall 7", "hall11" to "Hall 11", "hall10" to "Hall 10")
    LaunchedEffect(requestedRoom) {
        if (requestedRoom != null) { val feature = venueFeatures.find { it.ref == mapRef(requestedRoom) }; hall = feature?.hall ?: "overview"; selectedRef = feature?.ref; consumed() }
    }
    val selected = allMapPlaces.find { it.ref == selectedRef && it.hall == hall }
    val choose: (MapFeature) -> Unit = { if (it.kind == "hall") { hall = it.destination; selectedRef = null; showPlace = false } else { hall = it.hall; selectedRef = it.ref; showPlace = true }; query = ""; focusManager.clearFocus() }
    LazyColumn(contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        item { Text("Brussels Expo", style = MaterialTheme.typography.headlineMedium); Text("Find stages, booth rows, and places to meet.", style = MaterialTheme.typography.bodyMedium) }
        item { OxpSearch(query, { query = it }, "Find a hall, room, or booth") }
        if (query.isNotBlank()) {
            val matches = allMapPlaces.filter { it.kind != "hall" && (it.title.contains(query.trim(), true) || mapLocations(it.ref).any { location -> location.contains(query.trim(), true) }) }
            if (matches.isEmpty()) item { Text("No matching places.") }
            items(matches.distinctBy { it.hall to it.ref }, key = { "${it.hall}-${it.ref}" }) { feature -> OutlinedButton(onClick = { choose(feature) }, modifier = Modifier.fillMaxWidth()) { Text("${feature.title} · ${halls.find { it.first == feature.hall }?.second}") } }
        }
        item {
            Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OxpChip(hall == "overview", { hall = "overview"; selectedRef = null }, label = { Text("All halls") })
                halls.forEach { (key, title) -> OxpChip(hall == key, { hall = key; selectedRef = null }, label = { Text(title) }) }
            }
        }
        if (hall == "overview") {
            items(halls) { (key, title) ->
                ElevatedCard(onClick = { hall = key }, modifier = Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text(title, style = MaterialTheme.typography.titleLarge)
                        Text(when(key) { "hall6" -> "Stages 6.A–E · Booths A–G"; "hall7" -> "Stages 7.A–B · Booths H–Q · Education Village"; "hall11" -> "Main stage · Auditorium 4000"; else -> "Odoo village · Auditorium 2000" })
                    }
                }
            }
        } else {
            item {
                AndroidView(factory = { HallMapView(it) }, update = { view -> view.show(hall, selectedRef, reset, choose) }, modifier = Modifier.fillMaxWidth().height(460.dp).clipToBounds())
                Text("Pinch to zoom · Drag to pan · Tap a place", style = MaterialTheme.typography.labelSmall)
                TextButton(onClick = { reset++ }) { Text("Reset map") }
            }
            item { Heading("Places in this hall") }
            items(venueFeatures.filter { it.hall == hall }.distinctBy { it.ref }, key = { "place-${it.hall}-${it.ref}" }) { feature ->
                OutlinedButton(onClick = { choose(feature) }, modifier = Modifier.fillMaxWidth()) { Text(if (feature.kind == "hall") "Go to ${feature.title}" else feature.title) }
            }
        }
    }
    if (showPlace && selected != null) {
        key(selected.hall, selected.ref) {
            MapPlaceSheet(event, selected, now, saved,
                open = { showPlace = false; open(it) }, toggle = toggle, choose = choose,
                dismiss = { showPlace = false })
        }
    }

}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun MapPlaceSheet(event: Edition, place: MapFeature, now: Instant, saved: Set<Int>, open: (Talk) -> Unit, toggle: (Talk) -> Unit, choose: (MapFeature) -> Unit, dismiss: () -> Unit) {
    val talks = remember(event, place.ref) { event.activeTalks.filter { it.location in mapLocations(place.ref) }.sortedBy { it.start } }
    val days = talks.mapNotNull { it.day }.distinct().sorted()
    val today = now.atZone(event.zone).toLocalDate().toString()
    var day by rememberSaveable(place.ref) { mutableStateOf<String?>(today.takeIf { it in days }) }
    val here = talks.filter { day == null || it.day == day }
    val live = talks.filter { it.happening(now) }
    val next = talks.firstOrNull { it.start?.isAfter(now) == true }
    val hallName = "Hall ${place.hall.removePrefix("hall")}"
    ModalBottomSheet(onDismissRequest = dismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true), containerColor = MaterialTheme.colorScheme.background) {
        LazyColumn(Modifier.fillMaxWidth().heightIn(max = androidx.compose.ui.platform.LocalConfiguration.current.screenHeightDp.dp * .8f), contentPadding = PaddingValues(start = 20.dp, end = 20.dp, bottom = 24.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            item {
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text(if (place.kind == "boothRow") "Booth row ${place.title}" else place.title, style = MaterialTheme.typography.headlineSmall)
                        Text(hallName, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    IconButton(onClick = dismiss) { Icon(Icons.Default.Close, "Close place details") }
                }
            }
            if (place.detail.isNotBlank()) item { Text(place.detail, style = MaterialTheme.typography.bodyLarge) }
            if (place.kind == "boothRow" || place.kind == "booth") {
                item { Text("Exhibitor names for each stall have not been published.", color = MaterialTheme.colorScheme.onSurfaceVariant) }
                if (place.kind == "boothRow") {
                    val booths = venueBooths.filter { it.hall == place.hall && it.ref.startsWith(place.ref) }
                    item { Heading("${booths.size} booths") }
                    items(booths.chunked(4)) { row ->
                        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            row.forEach { booth -> OutlinedButton(onClick = { choose(booth) }, modifier = Modifier.weight(1f), contentPadding = PaddingValues(8.dp)) { Text(booth.ref) } }
                            repeat(4 - row.size) { Spacer(Modifier.weight(1f)) }
                        }
                    }
                }
            }
            if (place.kind == "room" || talks.isNotEmpty()) {
                if (mapLocations(place.ref).size > 1) item {
                    Text(mapLocations(place.ref).joinToString(" · "), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                item { Heading("Now") }
                if (live.isEmpty()) item { Text("Nothing on stage here right now.", color = MaterialTheme.colorScheme.onSurfaceVariant) }
                items(live, key = { "live-${it.id}" }) { TalkCard(it, it.id in saved, { open(it) }, { toggle(it) }) }
                if (next != null) {
                    item { Heading("Next") }
                    item { Text(next.day?.let(::dayLabel).orEmpty(), style = MaterialTheme.typography.labelMedium); TalkCard(next, next.id in saved, { open(next) }, { toggle(next) }) }
                }
                item { Heading("In this room") }
                if (days.isNotEmpty()) item {
                    Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        OxpChip(day == null, { day = null }, label = { Text("All days") })
                        days.forEach { date -> OxpChip(day == date, { day = date }, label = { Text(dayLabel(date)) }) }
                    }
                }
                if (here.isEmpty()) item { Text("No sessions listed here on this day.") }
                here.groupBy { it.day }.forEach { (date, sessions) ->
                    if (date != null) item { Text(dayLabel(date), style = MaterialTheme.typography.titleSmall) }
                    items(sessions, key = { "session-${it.id}" }) { TalkCard(it, it.id in saved, { open(it) }, { toggle(it) }) }
                }
            }
        }
    }
}

/** Vector artwork and hit targets use the same geometry as the current SwiftUI map. */
class HallMapView(context: Context) : View(context) {
    private var hall = ""
    private var selected: String? = null
    private var resetToken = 0
    private var zoom = 1f
    private var panX = 0f
    private var panY = 0f
    private var onPlace: (MapFeature) -> Unit = {}
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val aspect get() = when (hall) { "hall6" -> 1024f / 468f; "hall7" -> 1024f / 528f; "hall11" -> 480f / 938f; else -> 574f / 878f }
    private val rotated get() = aspect > 1f && height > width
    private val dark get() = resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK == Configuration.UI_MODE_NIGHT_YES
    private fun featureFrame(feature: MapFeature, bounds: RectF): RectF {
        val x = if (rotated) 1 - feature.y - feature.height else feature.x
        val y = if (rotated) feature.x else feature.y
        val w = if (rotated) feature.height else feature.width
        val h = if (rotated) feature.width else feature.height
        return RectF(bounds.left + x * bounds.width(), bounds.top + y * bounds.height(), bounds.left + (x + w) * bounds.width(), bounds.top + (y + h) * bounds.height())
    }
    private fun frame(): RectF {
        val sourceWidth = if (rotated) 1f else aspect
        val sourceHeight = if (rotated) aspect else 1f
        val base = minOf(width.toFloat() / sourceWidth, height.toFloat() / sourceHeight)
        val w = sourceWidth * base * zoom; val h = sourceHeight * base * zoom
        panX = panX.coerceIn(-maxOf((w - width) / 2, 0f), maxOf((w - width) / 2, 0f))
        panY = panY.coerceIn(-maxOf((h - height) / 2, 0f), maxOf((h - height) / 2, 0f))
        return RectF((width - w) / 2 + panX, (height - h) / 2 + panY, (width + w) / 2 + panX, (height + h) / 2 + panY)
    }
    private val scale = ScaleGestureDetector(context, object : ScaleGestureDetector.SimpleOnScaleGestureListener() {
        override fun onScale(detector: ScaleGestureDetector): Boolean { zoom = (zoom * detector.scaleFactor).coerceIn(1f, 5f); invalidate(); return true }
    })
    private val gestures = GestureDetector(context, object : GestureDetector.SimpleOnGestureListener() {
        override fun onDown(e: MotionEvent) = true
        override fun onScroll(e1: MotionEvent?, e2: MotionEvent, distanceX: Float, distanceY: Float): Boolean { if (!scale.isInProgress) { panX -= distanceX; panY -= distanceY; invalidate() }; return true }
        override fun onDoubleTap(e: MotionEvent): Boolean { zoom = if (zoom > 1f) 1f else 2.5f; panX = 0f; panY = 0f; invalidate(); return true }
        override fun onSingleTapConfirmed(e: MotionEvent): Boolean {
            performClick()
            val bounds = frame()
            val px = (e.x - bounds.left) / bounds.width(); val py = (e.y - bounds.top) / bounds.height()
            val x = if (rotated) py else px; val y = if (rotated) 1 - px else py
            allMapPlaces.filter { it.hall == hall && x >= it.x && x <= it.x + it.width && y >= it.y && y <= it.y + it.height }.minByOrNull { it.width * it.height }?.let(onPlace)
            return true
        }
    })
    init { contentDescription = "Interactive venue map. Places are also listed below."; isClickable = true }
    fun show(newHall: String, newSelected: String?, reset: Int, action: (MapFeature) -> Unit) {
        onPlace = action
        if (hall != newHall) {
            hall = newHall
            zoom = 1f; panX = 0f; panY = 0f
        }
        if (reset != resetToken) { resetToken = reset; zoom = 1f; panX = 0f; panY = 0f }
        selected = newSelected
        invalidate()
    }
    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        canvas.save()
        canvas.clipRect(0, 0, width, height)
        val density = resources.displayMetrics.density
        val ink = if (dark) 0xFFEFEAEE.toInt() else 0xFF302831.toInt()
        val border = if (dark) 0xFF514851.toInt() else 0xFFD8CFD6.toInt()
        paint.style = Paint.Style.FILL
        paint.color = if (dark) 0xFF19171A.toInt() else 0xFFF4F2F4.toInt()
        canvas.drawRect(0f, 0f, width.toFloat(), height.toFloat(), paint)
        val bounds = frame()
        val footprint = Path()
        venueFootprints[hall]?.forEachIndexed { index, (px, py) ->
            val x = bounds.left + (if (rotated) 1 - py else px) * bounds.width()
            val y = bounds.top + (if (rotated) px else py) * bounds.height()
            if (index == 0) footprint.moveTo(x, y) else footprint.lineTo(x, y)
        }
        footprint.close()
        paint.color = if (dark) 0xFF2B272C.toInt() else 0xFFFEFDFE.toInt()
        canvas.drawPath(footprint, paint)
        paint.style = Paint.Style.STROKE; paint.strokeWidth = 1.2f * density; paint.color = border
        canvas.drawPath(footprint, paint)
        paint.style = Paint.Style.FILL
        allMapPlaces.filter { it.hall == hall }.forEach { feature ->
            val rect = featureFrame(feature, bounds)
            val tint = if (feature.kind == "room") roomColor(feature.ref).toArgb() else if (feature.kind == "amenity") 0xFF33877D.toInt() else 0xFF714B67.toInt()
            val boothFill = when {
                feature.detail.contains("48 m") -> 0xFF1F7A80.toInt()
                feature.detail.contains("24 m") -> 0xFF6BC7C7.toInt()
                feature.detail.startsWith("Bare") -> if (dark) 0xFFDDD4DC.toInt() else 0xFFFFFFFF.toInt()
                feature.detail.startsWith("Double premium") -> 0xFF8C387A.toInt()
                feature.detail.startsWith("Double") -> 0xFFDB5285.toInt()
                else -> 0xFFEB9EB8.toInt()
            }
            val radius = (if (feature.kind == "booth") 1.5f else 6f) * density
            paint.color = if (feature.kind == "booth") boothFill else (tint and 0xFFFFFF) or ((if (dark) 55 else 28) shl 24)
            canvas.drawRoundRect(rect, radius, radius, paint)
            if (feature.kind != "boothRow") {
                paint.style = Paint.Style.STROKE; paint.strokeWidth = (if (feature.kind == "booth") .4f else .8f) * density
                paint.color = if (feature.kind == "booth") border else (tint and 0xFFFFFF) or (95 shl 24)
                canvas.drawRoundRect(rect, radius, radius, paint)
                paint.style = Paint.Style.FILL
            }
        }
        (venueFeatures.filter { it.hall == hall } + if (zoom >= 2f) venueBooths.filter { it.hall == hall } else emptyList()).forEach { feature ->
            val rect = featureFrame(feature, bounds)
            if (rect.right < 0 || rect.left > width || rect.bottom < 0 || rect.top > height) return@forEach
            paint.color = if (feature.kind == "booth" && (feature.detail.contains("48 m") || feature.detail.startsWith("Double premium"))) android.graphics.Color.WHITE else ink
            paint.textAlign = Paint.Align.CENTER
            paint.typeface = android.graphics.Typeface.create("sans-serif-medium", android.graphics.Typeface.NORMAL)
            paint.textSize = minOf(android.util.TypedValue.applyDimension(android.util.TypedValue.COMPLEX_UNIT_SP, 11f, resources.displayMetrics) * zoom, 20 * density, rect.height() * .65f)
            val text = when {
                feature.kind == "booth" -> feature.ref.drop(1)
                feature.kind == "hall" -> "→ ${feature.title}"
                feature.ref.startsWith("bar-") -> "Food & drink"
                feature.ref.startsWith("welcome-") -> "Welcome"
                feature.ref == "meeting-rooms-7" -> "Meetings"
                feature.ref == "startup-area" -> "Startups"
                feature.ref == "Education Village" -> "Education"
                else -> feature.title.replace("Hall 6.", "6.").replace("Hall 7.", "7.")
            }
            val lines = if (paint.measureText(text) > rect.width() - 4 * density && text.contains(" ")) {
                val parts = text.split(" "); listOf(parts.dropLast(1).joinToString(" "), parts.last())
            } else listOf(text)
            val widest = lines.maxOf { paint.measureText(it) }
            if (widest > rect.width() - 2 * density) paint.textSize *= ((rect.width() - 2 * density) / widest).coerceAtLeast(.1f)
            paint.textSize = minOf(paint.textSize, rect.height() / (lines.size * 1.3f))
            val lineHeight = paint.textSize * 1.2f
            lines.forEachIndexed { index, line ->
                canvas.drawText(line, rect.centerX(), rect.centerY() + (index - (lines.size - 1) / 2f) * lineHeight - (paint.ascent() + paint.descent()) / 2, paint)
            }
        }
        allMapPlaces.filter { it.hall == hall && it.ref == selected }.forEach {
            paint.color = if (dark) 0xFFD4AAC7.toInt() else 0xFF714B67.toInt(); paint.style = Paint.Style.STROKE; paint.strokeWidth = 3 * density
            canvas.drawRect(featureFrame(it, bounds), paint)
            paint.style = Paint.Style.FILL
        }
        canvas.restore()
    }
    override fun onTouchEvent(event: MotionEvent): Boolean {
        parent.requestDisallowInterceptTouchEvent(event.actionMasked != MotionEvent.ACTION_UP && event.actionMasked != MotionEvent.ACTION_CANCEL)
        scale.onTouchEvent(event); gestures.onTouchEvent(event)
        return true
    }
    override fun performClick(): Boolean { super.performClick(); return true }
}
