package be.oxp.app

import android.Manifest
import android.content.Intent
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.viewModels
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.animation.*
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.draw.clip
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.Alignment
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.saveable.rememberSaveableStateHolder
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import kotlinx.coroutines.delay

class MainActivity : ComponentActivity() {
    private val model: OxpModel by viewModels()
    private var requestedTalk by mutableStateOf<Int?>(null)
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        requestedTalk = intent.getIntExtra("trackId", -1).takeIf { it >= 0 }
        setContent {
            OxpTheme {
                OxpApp(model, requestedTalk) { requestedTalk = null }
            }
        }
    }
    override fun onNewIntent(intent: Intent) { super.onNewIntent(intent); setIntent(intent); requestedTalk = intent.getIntExtra("trackId", -1).takeIf { it >= 0 } }
    override fun onResume() { super.onResume(); model.resumed() }
}

private data class AppDestination(val name: String, val eventId: Int? = null, val itemId: Int? = null) {
    val isDetail get() = name in setOf("Talk", "Exhibitor", "Settings")
    val tabIndex get() = listOf("Today", "Schedule", "Map", "Expo", "Saved").indexOf(name)
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun OxpApp(model: OxpModel, requestedTalk: Int?, consumed: () -> Unit) {
    val tabState = rememberSaveableStateHolder()
    var tab by rememberSaveable { mutableStateOf("Today") }
    var talkId by rememberSaveable { mutableStateOf<Int?>(null) }
    var exhibitorId by rememberSaveable { mutableStateOf<Int?>(null) }
    var detailEventId by rememberSaveable { mutableStateOf<Int?>(null) }
    var eventMenu by remember { mutableStateOf(false) }
    var settings by rememberSaveable { mutableStateOf(false) }
    var previewMenu by remember { mutableStateOf(false) }
    var previewDay by rememberSaveable(model.selectedId) { mutableStateOf<String?>(null) }
    var previewMinutes by rememberSaveable { mutableIntStateOf(700) }
    var mapRoom by rememberSaveable { mutableStateOf<String?>(null) }
    var now by remember { mutableStateOf(Instant.now()) }
    val context = LocalContext.current
    val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { model.resumed() }
    val toggle: (Talk) -> Unit = { talk ->
        val saving = talk.id !in model.savedIds
        model.toggle(talk)
        if (saving && Build.VERSION.SDK_INT >= 33 && !model.notificationsEnabled) permission.launch(Manifest.permission.POST_NOTIFICATIONS)
    }
    val openTalk: (Talk) -> Unit = { talkId = it.id; detailEventId = model.catalog?.editionFor(it.id)?.id }
    LaunchedEffect(Unit) { while (true) { now = Instant.now(); delay(20_000) } }
    LaunchedEffect(requestedTalk, model.catalog) { if (requestedTalk != null && model.catalog != null) { talkId = requestedTalk; detailEventId = model.catalog?.editionFor(requestedTalk)?.id; consumed() } }
    val edition = model.edition
    LaunchedEffect(model.selectedId) { if (tab == "Map" && edition?.hasMap != true) tab = "Today" }
    val clock = edition?.let { event -> previewDay?.let { LocalDate.parse(it).atTime(LocalTime.ofSecondOfDay(previewMinutes * 60L)).atZone(event.zone).toInstant() } } ?: now
    val detailEvent = model.catalog?.events?.find { it.id == detailEventId } ?: edition
    val hasDetail = talkId != null || exhibitorId != null || settings
    val destination = when {
        settings -> AppDestination("Settings")
        talkId != null -> AppDestination("Talk", detailEvent?.id, talkId)
        exhibitorId != null -> AppDestination("Exhibitor", detailEvent?.id, exhibitorId)
        else -> AppDestination(tab, edition?.id)
    }
    BackHandler(hasDetail || tab != "Today") {
        when { settings -> settings = false; talkId != null -> talkId = null; exhibitorId != null -> exhibitorId = null; else -> tab = "Today" }
    }
    Scaffold(
        topBar = {
            TopAppBar(colors = TopAppBarDefaults.topAppBarColors(containerColor = MaterialTheme.colorScheme.background), title = { Crossfade(destination.name, animationSpec = tween(180), label = "Screen title") { Text(it) } }, navigationIcon = {
                if (hasDetail) IconButton(onClick = { talkId = null; exhibitorId = null; settings = false }) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back") }
                else Box {
                    IconButton(onClick = { eventMenu = true }) { Icon(Icons.Default.Public, "Choose edition", Modifier.size(22.dp), tint = MaterialTheme.colorScheme.primary) }
                    DropdownMenu(eventMenu, { eventMenu = false }) {
                        model.catalog?.events?.sortedWith(compareBy<Edition> { it.id != 9099 }.thenBy { it.startsOn ?: "9999" })?.forEach { event ->
                            DropdownMenuItem(text = { Text("${if (event.id == model.selectedId) "✓ " else ""}${event.shortName}\n${event.startsOn ?: "Dates TBA"}") }, onClick = { model.select(event.id); eventMenu = false })
                        }
                    }
                }
            }, actions = {
                if (!hasDetail) {
                    if (tab == "Today") IconButton(onClick = { previewMenu = true }) { Icon(Icons.Default.Schedule, "Preview conference day") }
                    IconButton(onClick = { settings = true }) { Icon(Icons.Default.Settings, "Settings") }
                }
            })
        },
        bottomBar = {
            AnimatedVisibility(visible = !hasDetail,
                enter = fadeIn(tween(180)) + expandVertically(tween(260, easing = FastOutSlowInEasing), expandFrom = Alignment.Bottom),
                exit = fadeOut(tween(140)) + shrinkVertically(tween(240, easing = FastOutSlowInEasing), shrinkTowards = Alignment.Bottom)
            ) {
                Surface(
                    modifier = Modifier.navigationBarsPadding().padding(horizontal = 16.dp, vertical = 8.dp),
                    shape = RoundedCornerShape(28.dp), color = MaterialTheme.colorScheme.surface,
                    border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant), shadowElevation = 2.dp
                ) {
                    Row(Modifier.fillMaxWidth().selectableGroup().padding(5.dp), horizontalArrangement = Arrangement.spacedBy(3.dp)) {
                        val tabs = listOf("Today" to Icons.Default.WbSunny, "Schedule" to Icons.Default.CalendarMonth) + (if (edition?.hasMap == true) listOf("Map" to Icons.Default.Map) else emptyList()) + listOf("Expo" to Icons.Default.Apartment, "Saved" to Icons.Default.Favorite)
                        tabs.forEach { (name, icon) ->
                            val selected = tab == name
                            val iconScale by animateFloatAsState(if (selected) 1.08f else 1f, tween(220, easing = FastOutSlowInEasing), label = "Tab icon emphasis")
                            val background by animateColorAsState(if (selected) MaterialTheme.colorScheme.primaryContainer else Color.Transparent, label = "Tab background")
                            val tint by animateColorAsState(if (selected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant, label = "Tab tint")
                            Column(
                                Modifier.weight(1f).clip(RoundedCornerShape(23.dp)).background(background)
                                    .selectable(selected = selected, role = Role.Tab, onClick = { tab = name })
                                    .heightIn(min = 60.dp).padding(horizontal = 2.dp, vertical = 8.dp),
                                horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp, Alignment.CenterVertically)
                            ) {
                                Icon(icon, null, Modifier.size(22.dp).graphicsLayer { scaleX = iconScale; scaleY = iconScale }, tint = tint)
                                Text(name, style = MaterialTheme.typography.labelSmall, color = tint, maxLines = 1)
                            }
                        }
                    }
                }
            }
        }
    ) { padding ->
        Column(Modifier.padding(padding).fillMaxSize()) {
            if (model.refreshing) LinearProgressIndicator(Modifier.fillMaxWidth())
            if (previewDay != null && !hasDetail) Surface(color = MaterialTheme.colorScheme.secondaryContainer) {
                Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp), horizontalArrangement = Arrangement.SpaceBetween) {
                    Text("Preview · $previewDay · ${LocalTime.ofSecondOfDay(previewMinutes * 60L)}", Modifier.weight(1f).padding(vertical = 12.dp), style = MaterialTheme.typography.labelMedium)
                    TextButton(onClick = { previewDay = null }) { Text("End") }
                }
            }
            if (edition == null) {
                if (model.error == null) Box(Modifier.fillMaxSize(), contentAlignment = androidx.compose.ui.Alignment.Center) { CircularProgressIndicator() }
                else Column { EmptyState(model.error!!, ""); Button(onClick = { model.load() }) { Text("Try again") } }
            }
            else AnimatedContent(
                targetState = destination,
                modifier = Modifier.fillMaxSize().clipToBounds(),
                contentAlignment = Alignment.TopStart,
                transitionSpec = {
                    val direction = when {
                        targetState.isDetail -> 1
                        initialState.isDetail -> -1
                        targetState.tabIndex >= initialState.tabIndex -> 1
                        else -> -1
                    }
                    val detailTransition = initialState.isDetail || targetState.isDetail
                    (fadeIn(tween(220)) + slideInHorizontally(tween(280, easing = FastOutSlowInEasing)) { direction * it / if (detailTransition) 5 else 12 })
                        .togetherWith(fadeOut(tween(140)) + slideOutHorizontally(tween(240, easing = FastOutSlowInEasing)) { -direction * it / if (detailTransition) 8 else 16 })
                }, label = "Screen navigation"
            ) { screen ->
                val screenEvent = model.catalog?.events?.find { it.id == screen.eventId } ?: edition
                when (screen.name) {
                    "Settings" -> SettingsScreen(model)
                    "Talk" -> {
                        val screenTalk = screen.itemId?.let { model.catalog?.talk(it) }
                        if (screenTalk != null) TalkDetails(screenTalk, screenEvent, screenTalk.id in model.savedIds, { toggle(screenTalk) }, { location ->
                            model.select(screenEvent.id); mapRoom = location; talkId = null; tab = "Map"
                        }) else EmptyState("Talk unavailable", "This talk is no longer in the catalog.")
                    }
                    "Exhibitor" -> {
                        val screenExhibitor = screenEvent.exhibitors.find { it.id == screen.itemId }
                        if (screenExhibitor != null) ExhibitorDetails(screenExhibitor, screenEvent, {
                            model.select(screenEvent.id); mapRoom = if (screenExhibitor.level.contains("startup", true)) "startup-area" else null; exhibitorId = null; tab = "Map"
                        }) else EmptyState("Exhibitor unavailable", "This exhibitor is no longer in the catalog.")
                    }
                    else -> tabState.SaveableStateProvider("${screen.name}-${screenEvent.id}") {
                        when (screen.name) {
                            "Today" -> TodayScreen(screenEvent, clock, model.savedIds, openTalk, toggle, { tab = "Schedule" })
                            "Schedule" -> ScheduleScreen(screenEvent, clock, model.savedIds, openTalk, toggle)
                            "Map" -> MapScreen(screenEvent, clock, mapRoom, { mapRoom = null }, model.savedIds, openTalk, toggle)
                            "Expo" -> ExpoScreen(screenEvent) { exhibitorId = it.id; detailEventId = screenEvent.id }
                            else -> SavedScreen(model, openTalk, toggle) { tab = "Schedule" }
                        }
                    }
                }
            }
        }
    }
    if (previewMenu && edition != null) AlertDialog(onDismissRequest = { previewMenu = false }, title = { Text("Preview a conference day") }, text = {
        Column(Modifier.verticalScroll(rememberScrollState())) {
            edition.days.forEach { day -> TextButton(onClick = { previewDay = day; previewMenu = false }) { Text(dayLabel(day)) } }
            Text("Preview time: ${LocalTime.ofSecondOfDay(previewMinutes * 60L)}")
            Slider(previewMinutes.toFloat(), { previewMinutes = (it.toInt() / 5) * 5 }, valueRange = 0f..1435f)
            Text("Reminders always follow the real clock.", style = MaterialTheme.typography.bodySmall)
        }
    }, confirmButton = { TextButton(onClick = { previewDay = null; previewMenu = false }) { Text("Use real time") } })
}
