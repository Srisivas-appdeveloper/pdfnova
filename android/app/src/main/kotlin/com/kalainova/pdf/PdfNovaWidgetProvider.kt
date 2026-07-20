package com.kalainova.pdf

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews

/// 4x2 Master Studio Widget Provider
class PdfNovaStudioWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        for (appWidgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.pdfnova_widget_4x2)
            views.setOnClickPendingIntent(R.id.btn_w4_merge, getPendingIntent(context, "merge"))
            views.setOnClickPendingIntent(R.id.btn_w4_split, getPendingIntent(context, "split"))
            views.setOnClickPendingIntent(R.id.btn_w4_compress, getPendingIntent(context, "compress"))
            views.setOnClickPendingIntent(R.id.btn_w4_scan, getPendingIntent(context, "scan"))
            views.setOnClickPendingIntent(R.id.btn_w4_notes, getPendingIntent(context, "notes"))
            views.setOnClickPendingIntent(R.id.btn_w4_word, getPendingIntent(context, "pdfToWord"))
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }

    private fun getPendingIntent(context: Context, toolId: String): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            action = Intent.ACTION_VIEW
            putExtra("toolId", toolId)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val requestCode = ("studio_$toolId").hashCode()
        return PendingIntent.getActivity(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }
}

/// 2x2 Compact Quad Widget Provider
class PdfNovaQuickWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        for (appWidgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.pdfnova_widget_2x2)
            views.setOnClickPendingIntent(R.id.btn_w2_scan, getPendingIntent(context, "scan"))
            views.setOnClickPendingIntent(R.id.btn_w2_notes, getPendingIntent(context, "notes"))
            views.setOnClickPendingIntent(R.id.btn_w2_merge, getPendingIntent(context, "merge"))
            views.setOnClickPendingIntent(R.id.btn_w2_word, getPendingIntent(context, "pdfToWord"))
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }

    private fun getPendingIntent(context: Context, toolId: String): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            action = Intent.ACTION_VIEW
            putExtra("toolId", toolId)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val requestCode = ("quick_$toolId").hashCode()
        return PendingIntent.getActivity(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }
}
