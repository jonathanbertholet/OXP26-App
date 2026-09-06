package be.oxp.app

import android.app.Application
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.time.Instant

class OxpModel(application: Application) : AndroidViewModel(application) {
    private val context get() = getApplication<Application>()
    private val prefs = context.getSharedPreferences("oxp", 0)
    private val repository = CatalogRepository(context)
    var catalog by mutableStateOf<Catalog?>(null); private set
    var selectedId by mutableStateOf(prefs.getInt("edition", 9099)); private set
    var savedIds by mutableStateOf(SavedTalks.ids(context)); private set
    var minutes by mutableStateOf(SavedTalks.minutes(context)); private set
    var refreshing by mutableStateOf(false); private set
    var error by mutableStateOf<String?>(null); private set
    var checked by mutableStateOf<Instant?>(null); private set
    var notificationsEnabled by mutableStateOf(Reminders.enabled(context)); private set
    var exactReminders by mutableStateOf(Reminders.exact(context)); private set
    val edition get() = catalog?.events?.find { it.id == selectedId } ?: catalog?.events?.firstOrNull()
    init { load() }
    fun load() = viewModelScope.launch {
        try {
            catalog = withContext(Dispatchers.IO) { repository.load() }
            if (catalog!!.events.none { it.id == selectedId }) select(catalog!!.defaultEventId)
            checked = repository.lastChecked
            reschedule()
            refresh(false)
        } catch (_: Exception) { error = "The offline agenda could not be opened. Please try again." }
    }
    fun select(id: Int) { selectedId = id; prefs.edit().putInt("edition", id).apply() }
    fun refresh(force: Boolean = true) {
        val baseline = catalog ?: return
        if (refreshing) return
        val last = prefs.getLong("lastAttempt", 0).takeIf { it > 0 }?.let(Instant::ofEpochMilli)
        if (!force && !automaticRefreshDue(Instant.now(), last)) return
        refreshing = true
        prefs.edit().putLong("lastAttempt", System.currentTimeMillis()).apply()
        viewModelScope.launch {
            try {
                catalog = withContext(Dispatchers.IO) { repository.refresh(baseline) }
                checked = repository.lastChecked
                error = null
                reschedule()
            } catch (_: Exception) { error = "Couldn’t check for updates. Your offline agenda is still available." }
            finally { refreshing = false }
        }
    }
    fun toggle(talk: Talk) { SavedTalks.toggle(context, talk.id); savedIds = SavedTalks.ids(context); if (talk.id !in savedIds) Reminders.cancel(context, talk.id); reschedule() }
    fun updateReminderMinutes(value: Int) { SavedTalks.setMinutes(context, value); minutes = SavedTalks.minutes(context); reschedule() }
    fun resumed() { savedIds = SavedTalks.ids(context); notificationsEnabled = Reminders.enabled(context); exactReminders = Reminders.exact(context); reschedule(); refresh(false) }
    private fun reschedule() { catalog?.let { Reminders.reconcile(context, it) } }
}
