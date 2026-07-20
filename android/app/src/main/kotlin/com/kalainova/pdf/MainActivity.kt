package com.kalainova.pdf

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.ContentValues
import android.content.Intent
import android.content.pm.ShortcutInfo
import android.content.pm.ShortcutManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.Typeface
import android.graphics.drawable.Icon
import android.media.MediaScannerConnection
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterFragmentActivity() {
    private val CHANNEL = "pdfnova/widget_shortcut"
    private var initialToolId: String? = null
    private var methodChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)

        intent?.let {
            if (it.hasExtra("toolId")) {
                initialToolId = it.getStringExtra("toolId")
            }
        }

        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "pinShortcut" -> {
                    val toolId = call.argument<String>("toolId") ?: ""
                    val title = call.argument<String>("title") ?: "PDF Nova"
                    val pinned = pinWidgetShortcut(toolId, title)
                    result.success(pinned)
                }
                "getInitialShortcut" -> {
                    val toolId = initialToolId
                    initialToolId = null // Consume once
                    result.success(toolId)
                }
                else -> result.notImplemented()
            }
        }

        // Saves output files into the public Downloads/PDFNova folder via
        // MediaStore — the only way that works on Android 10+ scoped storage.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "pdfnova/downloads")
            .setMethodCallHandler { call, result ->
                if (call.method == "saveToDownloads") {
                    val srcPath = call.argument<String>("srcPath")
                    val fileName = call.argument<String>("fileName")
                    val mime = call.argument<String>("mime") ?: "application/octet-stream"
                    if (srcPath == null || fileName == null) {
                        result.success(null)
                    } else {
                        result.success(saveToDownloads(srcPath, fileName, mime))
                    }
                } else {
                    result.notImplemented()
                }
            }
    }

    /// Copies [srcPath] into Download/PDFNova and returns a friendly label
    /// ("Download/PDFNova/<name>") on success, null on failure.
    private fun saveToDownloads(srcPath: String, fileName: String, mime: String): String? {
        val src = File(srcPath)
        if (!src.exists()) return null
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val resolver = applicationContext.contentResolver
                val values = ContentValues().apply {
                    put(MediaStore.Downloads.DISPLAY_NAME, fileName)
                    put(MediaStore.Downloads.MIME_TYPE, mime)
                    put(MediaStore.Downloads.RELATIVE_PATH, "${Environment.DIRECTORY_DOWNLOADS}/PDFNova")
                    put(MediaStore.Downloads.IS_PENDING, 1)
                }
                val collection = MediaStore.Downloads.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
                val uri = resolver.insert(collection, values) ?: return null
                try {
                    resolver.openOutputStream(uri, "w")?.use { out ->
                        src.inputStream().use { it.copyTo(out) }
                    } ?: throw Exception("no output stream")
                    values.clear()
                    values.put(MediaStore.Downloads.IS_PENDING, 0)
                    resolver.update(uri, values, null, null)
                    "Download/PDFNova/$fileName"
                } catch (e: Exception) {
                    // Never leave a 0-byte ghost entry behind in Downloads.
                    resolver.delete(uri, null, null)
                    throw e
                }
            } else {
                // API <= 28: direct write (WRITE_EXTERNAL_STORAGE is declared,
                // and granted at install time on these old versions).
                val dir = File(
                    Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS),
                    "PDFNova"
                )
                dir.mkdirs()
                val dest = File(dir, fileName)
                src.inputStream().use { input -> dest.outputStream().use { input.copyTo(it) } }
                MediaScannerConnection.scanFile(
                    applicationContext, arrayOf(dest.absolutePath), null, null
                )
                "Download/PDFNova/$fileName"
            }
        } catch (e: Exception) {
            e.printStackTrace()
            null
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val toolId = intent.getStringExtra("toolId")
        if (!toolId.isNullOrEmpty()) {
            initialToolId = toolId
            methodChannel?.invokeMethod("onShortcutLaunched", toolId)
        }
    }

    private fun createToolIconBitmap(title: String): Bitmap {
        val size = 192
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)

        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        val shader = LinearGradient(0f, 0f, size.toFloat(), size.toFloat(),
            Color.parseColor("#7C5CFF"), Color.parseColor("#37D3E8"), Shader.TileMode.CLAMP)
        paint.shader = shader
        val rect = RectF(0f, 0f, size.toFloat(), size.toFloat())
        canvas.drawRoundRect(rect, 40f, 40f, paint)

        val textPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.WHITE
            textSize = 72f
            typeface = Typeface.DEFAULT_BOLD
            textAlign = Paint.Align.CENTER
        }
        val letter = if (title.contains(" ")) {
            title.split(" ").take(2).map { it.first() }.joinToString("")
        } else {
            title.take(2).uppercase()
        }
        val yPos = (canvas.height / 2 - (textPaint.descent() + textPaint.ascent()) / 2)
        canvas.drawText(letter, (canvas.width / 2).toFloat(), yPos, textPaint)

        return bitmap
    }

    private fun pinWidgetShortcut(toolId: String, title: String): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            // Notes gets the real resizable Quick Note widget (shows the note,
            // tap-to-edit popup) instead of a 1x1 launcher shortcut.
            if (toolId == "notes") {
                return pinNotesWidget()
            }
            val shortcutManager = getSystemService(ShortcutManager::class.java)
            if (shortcutManager != null && shortcutManager.isRequestPinShortcutSupported) {
                val intent = Intent(applicationContext, MainActivity::class.java).apply {
                    action = Intent.ACTION_VIEW
                    putExtra("toolId", toolId)
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                }

                val toolIconBitmap = createToolIconBitmap(title)
                val shortcut = ShortcutInfo.Builder(applicationContext, "tool_$toolId")
                    .setShortLabel(title)
                    .setLongLabel("PDF Nova $title")
                    .setIcon(Icon.createWithBitmap(toolIconBitmap))
                    .setIntent(intent)
                    .build()

                val callbackIntent = shortcutManager.createShortcutResultIntent(shortcut)
                val successCallback = PendingIntent.getBroadcast(
                    applicationContext,
                    0,
                    callbackIntent,
                    PendingIntent.FLAG_IMMUTABLE
                )

                shortcutManager.requestPinShortcut(shortcut, successCallback.intentSender)
                return true
            }
        }
        return false
    }

    /// Pins the actual Quick Note App Widget (resizable, shows note text on the
    /// Home Screen) using AppWidgetManager — unlike requestPinShortcut which
    /// only drops a 1x1 icon.
    private fun pinNotesWidget(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val widgetManager = getSystemService(AppWidgetManager::class.java)
            val provider = ComponentName(this, PdfNovaNotesWidgetProvider::class.java)
            if (widgetManager != null && widgetManager.isRequestPinAppWidgetSupported) {
                widgetManager.requestPinAppWidget(provider, null, null)
                return true
            }
        }
        return false
    }
}
