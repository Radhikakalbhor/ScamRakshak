package com.scamrakshak.scam_rakshak

import android.app.NotificationManager
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Share target. ACTION_SEND text/plain -> {"type": "text", "text": ...};
 * ACTION_SEND audio (any audio type) -> the audio is copied into cache/shared_audio (the sending app's permission is only
 * temporary) -> {"type": "audio", "path": ..., "name": ...}.
 * Cold start: Dart asks "getInitialShare" once. App already open: onNewIntent -> "onShare" to Dart.
 */
class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var pending: Map<String, String>? = null
    private var pendingReady = false
    private val waiting = mutableListOf<MethodChannel.Result>()
    private val main = Handler(Looper.getMainLooper())

    override fun onCreate(savedInstanceState: Bundle?) {
        showOverLockIfWarning(intent) // before the first frame, so a full-screen warning is visible when locked
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ALERT_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "canUseFullScreenIntent" -> result.success(canUseFullScreenIntent())
                "openFullScreenIntentSettings" -> {
                    openFullScreenIntentSettings()
                    result.success(null)
                }
                "setShowWhenLocked" -> {
                    setOverLock(call.arguments == true)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).also {
            it.setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInitialShare" -> if (pendingReady) {
                        result.success(pending)
                        pending = null
                    } else {
                        waiting.add(result)
                    }
                    else -> result.notImplemented()
                }
            }
        }
        readShare(intent) { item ->
            pending = item
            pendingReady = true
            if (waiting.isNotEmpty()) {
                waiting.forEach { it.success(item) }
                waiting.clear()
                pending = null
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        showOverLockIfWarning(intent)
        super.onNewIntent(intent)
        setIntent(intent)
        readShare(intent) { item -> if (item != null) channel?.invokeMethod("onShare", item) }
    }

    /** Parses a share intent off the main thread (audio copy) and calls [done] on the main thread. */
    private fun readShare(intent: Intent?, done: (Map<String, String>?) -> Unit) {
        // Reopened from Recents re-delivers the old share intent: ignore it.
        val fromHistory = intent != null && (intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY) != 0
        if (intent?.action != Intent.ACTION_SEND || fromHistory) {
            done(null)
            return
        }
        intent.action = ACTION_CONSUMED // handled once, even if the activity is recreated
        val type = intent.type ?: ""
        if (type.startsWith("text/")) {
            val text = intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString()?.trim()
            done(if (text.isNullOrEmpty()) null else mapOf("type" to "text", "text" to text))
            return
        }
        if (type.startsWith("audio/")) {
            val uri = streamUri(intent)
            if (uri == null) {
                done(null)
                return
            }
            Thread {
                val item = try {
                    copyAudio(uri, type)
                } catch (e: Exception) {
                    mapOf("type" to "audio_error", "error" to (e.message ?: "copy failed"))
                }
                main.post { done(item) }
            }.start()
            return
        }
        done(null)
    }

    @Suppress("DEPRECATION")
    private fun streamUri(intent: Intent): Uri? =
        if (Build.VERSION.SDK_INT >= 33) intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        else intent.getParcelableExtra(Intent.EXTRA_STREAM)

    private fun copyAudio(uri: Uri, mime: String): Map<String, String> {
        var name: String? = null
        contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
            if (c.moveToFirst()) name = c.getString(0)
        }
        val ext = name?.substringAfterLast('.', "")?.lowercase()?.takeIf { it.isNotEmpty() } ?: extFor(mime)
        val dir = File(cacheDir, "shared_audio")
        dir.mkdirs()
        dir.listFiles()?.forEach { it.delete() } // keep only the newest shared recording
        val out = File(dir, "shared_${System.currentTimeMillis()}.$ext")
        val input = contentResolver.openInputStream(uri) ?: throw IllegalStateException("cannot open")
        input.use { i -> out.outputStream().use { o -> i.copyTo(o) } }
        return mapOf("type" to "audio", "path" to out.absolutePath, "name" to (name ?: out.name))
    }

    private fun extFor(mime: String) = when (mime.lowercase()) {
        "audio/mpeg", "audio/mp3" -> "mp3"
        "audio/mp4", "audio/m4a", "audio/x-m4a", "audio/aac-adts" -> "m4a"
        "audio/aac" -> "aac"
        "audio/amr", "audio/amr-wb", "audio/3gpp" -> if (mime.contains("3gpp")) "3gp" else "amr"
        "audio/ogg", "audio/opus" -> "ogg"
        "audio/wav", "audio/x-wav", "audio/wave" -> "wav"
        else -> "m4a"
    }

    /** Opened by a scam-warning notification (flutter_local_notifications: action SELECT_NOTIFICATION, payload has "warn"). */
    private fun showOverLockIfWarning(intent: Intent?) {
        if (intent?.action != "SELECT_NOTIFICATION") return
        if ((intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY) != 0) return
        val payload = intent.getStringExtra("payload") ?: return
        if (payload.contains("\"warn\":true")) setOverLock(true)
    }

    /** Show over the lock screen and turn the screen on; only while a warning is open (Dart turns it off). */
    @Suppress("DEPRECATION")
    private fun setOverLock(on: Boolean) {
        if (Build.VERSION.SDK_INT >= 27) {
            setShowWhenLocked(on)
            setTurnScreenOn(on)
        } else {
            val flags = WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            if (on) window.addFlags(flags) else window.clearFlags(flags)
        }
    }

    private fun canUseFullScreenIntent(): Boolean =
        if (Build.VERSION.SDK_INT >= 34) getSystemService(NotificationManager::class.java).canUseFullScreenIntent() else true

    private fun openFullScreenIntentSettings() {
        val intent = if (Build.VERSION.SDK_INT >= 34) {
            Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT, Uri.parse("package:$packageName"))
        } else {
            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
        }
        try {
            startActivity(intent)
        } catch (e: Exception) {
            startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName")))
        }
    }

    companion object {
        const val CHANNEL = "scamrakshak/share"
        const val ALERT_CHANNEL = "scamrakshak/alert"
        const val ACTION_CONSUMED = "com.scamrakshak.SHARE_CONSUMED"
    }
}
