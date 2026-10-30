package com.ionel.journal

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.*
import android.os.Build
import android.service.quicksettings.TileService
import android.widget.RemoteViews

class JournalWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) { refresh(context) }
    companion object {
        fun refresh(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val prefs = context.getSharedPreferences("journal_platform", Context.MODE_PRIVATE)
            val today = java.text.SimpleDateFormat("yyyy-MM-dd", java.util.Locale.US).format(java.util.Date())
            val views = RemoteViews(context.packageName, R.layout.journal_widget)
            val written = prefs.getBoolean("written", false) && prefs.getString("day", "") == today
            views.setTextViewText(R.id.widget_title, if (written) "● Written today" else "○ A page for today")
            val savedDay = prefs.getString("day", "")
            val format = java.text.SimpleDateFormat("yyyy-MM-dd", java.util.Locale.US)
            val age = try { (format.parse(today)!!.time - format.parse(savedDay!!)!!.time) / 86400000 } catch (_: Exception) { 99L }
            val streak = if (age in 0..1) prefs.getInt("streak", 0) else 0
            views.setTextViewText(R.id.widget_streak, "$streak day streak")
            val write = Intent(context, MainActivity::class.java).setAction("com.ionel.journal.WRITE").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            views.setOnClickPendingIntent(R.id.widget_write, PendingIntent.getActivity(context, 43, write, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE))
            for (id in manager.getAppWidgetIds(ComponentName(context, JournalWidget::class.java))) manager.updateAppWidget(id, views)
        }
    }
}

class WriteTile : TileService() {
    override fun onClick() {
        super.onClick()
        val intent = Intent(this, MainActivity::class.java).setAction("com.ionel.journal.WRITE").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        if (Build.VERSION.SDK_INT >= 34) startActivityAndCollapse(PendingIntent.getActivity(this, 44, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE))
        else @Suppress("DEPRECATION") startActivityAndCollapse(intent)
    }
}
