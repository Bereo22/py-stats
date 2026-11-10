package com.berkant.tag_stats

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.location.Location
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.text.SimpleDateFormat
import java.util.Collections
import java.util.Date
import java.util.Locale

/** In-process state shared between the services and the Flutter bridge. */
object SharedState {
    @Volatile var a11yConnected = false
    @Volatile var foregroundPkg: String? = null
    @Volatile var lastTargetEventAt = 0L
    @Volatile var lastScreenWrittenAt = 0L
    @Volatile var screensWritten = 0
    @Volatile var lastLocation: Location? = null
    @Volatile var tracking = false
    @Volatile var trackingStartedAt = 0L
    @Volatile var capturing = false
    @Volatile var lastOcrAt = 0L
    @Volatile var ownAppVisible = false
}

object Prefs {
    private const val FILE = "tag_stats_prefs"
    private const val KEY_TARGET = "target_pkg"
    private const val KEY_SEEN = "seen_pkgs"
    private const val KEY_OCR_ON_START = "ocr_on_start"

    @Volatile private var targetCache: String? = null
    @Volatile private var targetLoaded = false
    private val seenCache: MutableSet<String> = Collections.synchronizedSet(LinkedHashSet())
    @Volatile private var seenLoaded = false

    private fun prefs(ctx: Context) = ctx.getSharedPreferences(FILE, Context.MODE_PRIVATE)

    fun target(ctx: Context): String? {
        if (!targetLoaded) {
            targetCache = prefs(ctx).getString(KEY_TARGET, null)
            targetLoaded = true
        }
        return targetCache
    }

    fun setTarget(ctx: Context, pkg: String?) {
        prefs(ctx).edit().putString(KEY_TARGET, pkg).apply()
        targetCache = pkg
        targetLoaded = true
    }

    /** Uses the saved package, otherwise auto-selects the first package whose name contains "marti". */
    fun isTarget(ctx: Context, pkg: String): Boolean {
        val t = target(ctx)
        if (t != null) return t == pkg
        if (pkg.contains("marti", ignoreCase = true)) {
            setTarget(ctx, pkg)
            return true
        }
        return false
    }

    fun ocrOnStart(ctx: Context): Boolean = prefs(ctx).getBoolean(KEY_OCR_ON_START, false)

    fun setOcrOnStart(ctx: Context, value: Boolean) {
        prefs(ctx).edit().putBoolean(KEY_OCR_ON_START, value).apply()
    }

    fun seen(ctx: Context): List<String> {
        loadSeen(ctx)
        return synchronized(seenCache) { seenCache.toList() }
    }

    fun addSeen(ctx: Context, pkg: String) {
        loadSeen(ctx)
        if (seenCache.add(pkg)) {
            val copy = synchronized(seenCache) { seenCache.toSet() }
            prefs(ctx).edit().putStringSet(KEY_SEEN, copy).apply()
        }
    }

    private fun loadSeen(ctx: Context) {
        if (seenLoaded) return
        seenCache.addAll(prefs(ctx).getStringSet(KEY_SEEN, emptySet()) ?: emptySet())
        seenLoaded = true
    }
}

/** Append-only JSONL files under Android/data/<app>/files/logs, one file per kind per day. */
object LogStore {
    private val lock = Any()
    private val dayFormat = SimpleDateFormat("yyyy-MM-dd", Locale.US)

    fun logDir(ctx: Context): File =
        File(ctx.getExternalFilesDir(null) ?: ctx.filesDir, "logs").apply { mkdirs() }

    fun append(ctx: Context, kind: String, json: JSONObject) {
        val day = synchronized(dayFormat) { dayFormat.format(Date()) }
        val file = File(logDir(ctx), "${kind}_$day.jsonl")
        synchronized(lock) { file.appendText(json.toString() + "\n") }
    }

    fun locationJson(): JSONObject? {
        val loc = SharedState.lastLocation ?: return null
        return JSONObject()
            .put("lat", loc.latitude)
            .put("lng", loc.longitude)
            .put("acc", loc.accuracy.toDouble())
            .put("spd", loc.speed.toDouble())
            .put("age", System.currentTimeMillis() - loc.time)
    }

    /** Writes one screen snapshot; texts are the visible strings in reading order. */
    fun writeScreen(
        ctx: Context,
        src: String,
        pkg: String?,
        event: String,
        texts: List<String>,
        nodes: JSONArray,
    ) {
        val now = System.currentTimeMillis()
        val json = JSONObject()
            .put("t", now)
            .put("src", src)
            .put("pkg", pkg ?: JSONObject.NULL)
            .put("ev", event)
            .put("loc", locationJson() ?: JSONObject.NULL)
            .put("texts", JSONArray(texts))
            .put("nodes", nodes)
        append(ctx, "screens", json)
        SharedState.lastScreenWrittenAt = now
        SharedState.screensWritten++
    }
}

object Notifications {
    const val CHANNEL_ID = "tag_stats_services"
    const val TRACKING_ID = 1001
    const val CAPTURE_ID = 1002

    fun build(ctx: Context, title: String, text: String): Notification {
        val manager = ctx.getSystemService(NotificationManager::class.java)
        if (manager.getNotificationChannel(CHANNEL_ID) == null) {
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "Kayıt servisleri", NotificationManager.IMPORTANCE_LOW)
            )
        }
        val open = PendingIntent.getActivity(
            ctx,
            0,
            Intent(ctx, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE,
        )
        return Notification.Builder(ctx, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(text)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setOngoing(true)
            .setContentIntent(open)
            .build()
    }
}
