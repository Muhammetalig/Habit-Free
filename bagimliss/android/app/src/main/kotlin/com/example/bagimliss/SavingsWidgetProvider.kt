package com.example.bagimliss

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.widget.RemoteViews
import android.app.PendingIntent
import android.content.Intent
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetPlugin

class SavingsWidgetProvider : AppWidgetProvider() {
    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == AppWidgetManager.ACTION_APPWIDGET_UPDATE) {
            val appWidgetManager = AppWidgetManager.getInstance(context)
            val thisComponent = android.content.ComponentName(context, SavingsWidgetProvider::class.java)
            val ids = appWidgetManager.getAppWidgetIds(thisComponent)
            if (ids != null && ids.isNotEmpty()) {
                onUpdate(context, appWidgetManager, ids)
            }
        }
    }
    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        for (widgetId in appWidgetIds) {
            updateWidget(context, appWidgetManager, widgetId)
        }
    }

    private fun updateWidget(context: Context, appWidgetManager: AppWidgetManager, widgetId: Int) {
        val views = RemoteViews(context.packageName, R.layout.widget_layout)
        val prefs = HomeWidgetPlugin.getData(context)
        val text = prefs.getString("savings_text", "₺0,00")
    views.setTextViewText(R.id.txtTitle, "Tasarruf")
    views.setTextViewText(R.id.txtSavings, text)
    views.setTextViewText(R.id.txtSubtitle, "Anlık güncelleniyor")

        // Tap to refresh: send a broadcast to this provider to trigger onUpdate
        val intentUpdate = Intent(context, SavingsWidgetProvider::class.java).apply {
            action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
            putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, intArrayOf(widgetId))
        }
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        val pendingUpdate = PendingIntent.getBroadcast(context, widgetId, intentUpdate, flags)
        views.setOnClickPendingIntent(R.id.widget_root, pendingUpdate)

    // Optional: add another click action if needed

        appWidgetManager.updateAppWidget(widgetId, views)
    }
}
