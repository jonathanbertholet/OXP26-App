package be.oxp.app

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import java.time.Instant

object SavedTalks {
    private fun prefs(context: Context) = context.getSharedPreferences("oxp", Context.MODE_PRIVATE)
    fun ids(context: Context): Set<Int> = prefs(context).getStringSet("saved", emptySet())!!.mapNotNull { it.toIntOrNull() }.toSet()
    @Synchronized fun toggle(context: Context, id: Int) {
        val saved = ids(context).toMutableSet()
        if (!saved.add(id)) saved.remove(id)
        prefs(context).edit().putStringSet("saved", saved.map { it.toString() }.toSet()).apply()
    }
    @Synchronized fun remove(context: Context, id: Int) {
        prefs(context).edit().putStringSet("saved", (ids(context) - id).map { it.toString() }.toSet()).apply()
        Reminders.cancel(context, id)
    }
    fun minutes(context: Context) = prefs(context).getInt("reminderMinutes", 15).coerceIn(5, 60)
    fun setMinutes(context: Context, value: Int) { prefs(context).edit().putInt("reminderMinutes", value.coerceIn(5, 60)).apply() }
}

object Reminders {
    private const val CHANNEL = "talk-reminders"
    fun enabled(context: Context): Boolean {
        val permission = Build.VERSION.SDK_INT < 33 || ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
        val channel = context.getSystemService(NotificationManager::class.java).getNotificationChannel(CHANNEL)
        return permission && NotificationManagerCompat.from(context).areNotificationsEnabled() && channel?.importance != NotificationManager.IMPORTANCE_NONE
    }
    fun exact(context: Context): Boolean = Build.VERSION.SDK_INT < 31 || context.getSystemService(AlarmManager::class.java).canScheduleExactAlarms()
    fun channel(context: Context) {
        context.getSystemService(NotificationManager::class.java).createNotificationChannel(NotificationChannel(CHANNEL, "Saved talk reminders", NotificationManager.IMPORTANCE_HIGH))
    }
    private fun pending(context: Context, id: Int, intent: Intent = Intent(context, ReminderReceiver::class.java)) = PendingIntent.getBroadcast(context, id, intent.setAction("be.oxp.REMIND").putExtra("trackId", id), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    fun cancel(context: Context, id: Int) {
        context.getSystemService(AlarmManager::class.java).cancel(pending(context, id))
        NotificationManagerCompat.from(context).cancel(id)
    }
    @Synchronized fun reconcile(context: Context, catalog: Catalog) {
        channel(context)
        val prefs = context.getSharedPreferences("oxp", Context.MODE_PRIVATE)
        val previous = prefs.getStringSet("scheduled", emptySet())!!.mapNotNull { it.toIntOrNull() }
        previous.forEach { cancel(context, it) }
        val minutes = SavedTalks.minutes(context)
        val wanted = SavedTalks.ids(context).mapNotNull(catalog::talk).filter { !it.unavailable && it.start?.minusSeconds(minutes * 60L)?.isAfter(Instant.now()) == true }
        if (enabled(context)) wanted.forEach { talk ->
            val intent = Intent(context, ReminderReceiver::class.java).putExtra("title", talk.name).putExtra("body", "Starts in $minutes min · ${talk.timeLabel} · ${talk.location ?: "Room TBA"}").putExtra("start", talk.start!!.toEpochMilli())
            val fire = talk.start.minusSeconds(minutes * 60L).toEpochMilli()
            val alarm = context.getSystemService(AlarmManager::class.java)
            val operation = pending(context, talk.id, intent)
            if (exact(context)) {
                try { alarm.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, fire, operation) }
                catch (_: SecurityException) { alarm.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, fire, operation) }
            } else alarm.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, fire, operation)
        }
        prefs.edit().putStringSet("scheduled", wanted.map { it.id.toString() }.toSet()).apply()
    }
    fun deliver(context: Context, intent: Intent) {
        val id = intent.getIntExtra("trackId", -1)
        if (id !in SavedTalks.ids(context) || !enabled(context) || intent.getLongExtra("start", 0) <= System.currentTimeMillis()) return
        channel(context)
        val open = PendingIntent.getActivity(context, id, Intent(context, MainActivity::class.java).putExtra("trackId", id), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val skip = PendingIntent.getBroadcast(context, id, Intent(context, ReminderReceiver::class.java).setAction("be.oxp.SKIP").putExtra("trackId", id), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val notification = NotificationCompat.Builder(context, CHANNEL).setSmallIcon(R.drawable.ic_notification).setContentTitle(intent.getStringExtra("title")).setContentText(intent.getStringExtra("body")).setStyle(NotificationCompat.BigTextStyle().bigText(intent.getStringExtra("body"))).setContentIntent(open).setAutoCancel(true).addAction(0, "Can't make it", skip).build()
        try { NotificationManagerCompat.from(context).notify(id, notification) } catch (_: SecurityException) { /* Permission may change between the check and delivery. */ }
    }
}
class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == "be.oxp.SKIP") SavedTalks.remove(context, intent.getIntExtra("trackId", -1)) else Reminders.deliver(context, intent)
    }
}
class RestoreRemindersReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action !in setOf(Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED, AlarmManager.ACTION_SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED)) return
        val pending = goAsync()
        Thread {
            try { runCatching { Reminders.reconcile(context, CatalogRepository(context).load()) } }
            finally { pending.finish() }
        }.start()
    }
}
