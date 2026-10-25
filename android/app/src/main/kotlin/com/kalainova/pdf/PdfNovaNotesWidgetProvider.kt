package com.kalainova.pdf

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews

/// Home-screen Quick Note widget.
///
/// Stock Android does not allow typing inside a RemoteViews widget, so this
/// shows the saved note and opens [NoteEditActivity] (a lightweight popup)
/// on tap — write → Save → the widget text updates instantly.
class PdfNovaNotesWidgetProvider : AppWidgetProvider() {

    companion object {
        const val PREFS = "notes_widget_prefs"
        const val KEY_NOTE = "quick_note"
        /** Last-write time (ms) — lets the app detect edits made here. */
        const val KEY_UPDATED_AT = "quick_note_updated_at"

        /// Re-renders every placed Notes widget with the current saved text.
        fun updateAll(context: Context) {
            val mgr = AppWidgetManager.getInstance(context)
            val ids = mgr.getAppWidgetIds(
                ComponentName(context, PdfNovaNotesWidgetProvider::class.java)
            )
            if (ids.isEmpty()) return
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val note = prefs.getString(KEY_NOTE, "") ?: ""
            for (id in ids) {
                mgr.updateAppWidget(id, buildViews(context, id, note))
            }
        }

        private fun buildViews(context: Context, widgetId: Int, note: String): RemoteViews {
            val views = RemoteViews(context.packageName, R.layout.pdfnova_widget_notes)
            views.setTextViewText(
                R.id.txt_note_body,
                if (note.isBlank()) "Tap to write a note…" else note
            )
            val editIntent = Intent(context, NoteEditActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            val pending = PendingIntent.getActivity(
                context,
                widgetId,
                editIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.notes_widget_root, pending)
            return views
        }
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        updateAll(context)
    }
}
