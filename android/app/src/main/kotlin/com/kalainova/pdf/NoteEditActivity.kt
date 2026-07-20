package com.kalainova.pdf

import android.app.Activity
import android.content.Context
import android.os.Bundle
import android.view.View
import android.widget.EditText

/// Lightweight popup editor for the Quick Note home-screen widget.
/// Opens over the launcher (dialog-themed, not the full app), saves the text
/// to SharedPreferences and refreshes all placed Notes widgets immediately.
class NoteEditActivity : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.note_editor_dialog)
        setFinishOnTouchOutside(true)

        val prefs = getSharedPreferences(PdfNovaNotesWidgetProvider.PREFS, Context.MODE_PRIVATE)
        val editor = findViewById<EditText>(R.id.edit_note)
        editor.setText(prefs.getString(PdfNovaNotesWidgetProvider.KEY_NOTE, ""))
        editor.setSelection(editor.text.length)

        findViewById<View>(R.id.btn_note_cancel).setOnClickListener { finish() }

        findViewById<View>(R.id.btn_note_save).setOnClickListener {
            prefs.edit()
                .putString(PdfNovaNotesWidgetProvider.KEY_NOTE, editor.text.toString())
                .apply()
            PdfNovaNotesWidgetProvider.updateAll(this)
            finish()
        }
    }
}
