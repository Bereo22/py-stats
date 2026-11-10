package com.berkant.tag_stats

import android.app.Activity
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.Bitmap
import android.graphics.PixelFormat
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.IBinder
import androidx.core.app.ServiceCompat
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import org.json.JSONArray
import org.json.JSONObject

/**
 * Fallback for screens whose text is not exposed to accessibility:
 * captures the screen every few seconds while Martı is in front and runs on-device OCR.
 */
class ScreenCaptureService : Service() {
    private var projection: MediaProjection? = null
    private var display: VirtualDisplay? = null
    private var reader: ImageReader? = null
    private var thread: HandlerThread? = null
    private var handler: Handler? = null
    private val recognizer by lazy { TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS) }
    @Volatile private var busy = false
    private var lastHash = 0
    private var width = 0
    private var height = 0

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopSelf()
            return START_NOT_STICKY
        }
        val resultCode = intent?.getIntExtra(EXTRA_RESULT_CODE, Activity.RESULT_CANCELED) ?: Activity.RESULT_CANCELED
        val data: Intent? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent?.getParcelableExtra(EXTRA_DATA, Intent::class.java)
        } else {
            @Suppress("DEPRECATION") intent?.getParcelableExtra(EXTRA_DATA)
        }
        if (resultCode != Activity.RESULT_OK || data == null || projection != null) return START_NOT_STICKY

        ServiceCompat.startForeground(
            this,
            Notifications.CAPTURE_ID,
            Notifications.build(this, "PY Stats", "Martı ekranı okunuyor (OCR)"),
            ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION,
        )

        val mpm = getSystemService(MediaProjectionManager::class.java)
        val mp = mpm.getMediaProjection(resultCode, data) ?: run {
            stopSelf()
            return START_NOT_STICKY
        }
        projection = mp

        thread = HandlerThread("ocr").also { it.start() }
        handler = Handler(thread!!.looper)

        mp.registerCallback(object : MediaProjection.Callback() {
            override fun onStop() {
                stopSelf()
            }
        }, handler)

        val metrics = resources.displayMetrics
        width = (metrics.widthPixels * SCALE).toInt()
        height = (metrics.heightPixels * SCALE).toInt()
        reader = ImageReader.newInstance(width, height, PixelFormat.RGBA_8888, 2)
        display = mp.createVirtualDisplay(
            "tag_stats_ocr",
            width,
            height,
            metrics.densityDpi,
            DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
            reader!!.surface,
            null,
            handler,
        )

        SharedState.capturing = true
        handler?.postDelayed(tick, INTERVAL_MS)
        return START_NOT_STICKY
    }

    private val tick: Runnable = object : Runnable {
        override fun run() {
            try {
                captureOnce()
            } finally {
                handler?.postDelayed(this, INTERVAL_MS)
            }
        }
    }

    private fun captureOnce() {
        if (busy || SharedState.ownAppVisible) return
        val target = Prefs.target(this)
        val front = SharedState.foregroundPkg
        // Without a known foreground app (accessibility off) every screen is read, and
        // MartiScreen keeps only Martı's own screens.
        if (SharedState.a11yConnected && target != null && front != null && front != target) return

        val image = reader?.acquireLatestImage() ?: return
        val bitmap: Bitmap
        try {
            val plane = image.planes[0]
            val rowPadding = plane.rowStride - plane.pixelStride * width
            val padded = Bitmap.createBitmap(width + rowPadding / plane.pixelStride, height, Bitmap.Config.ARGB_8888)
            padded.copyPixelsFromBuffer(plane.buffer)
            bitmap = if (rowPadding == 0) padded else Bitmap.createBitmap(padded, 0, 0, width, height)
        } finally {
            image.close()
        }

        busy = true
        recognizer.process(InputImage.fromBitmap(bitmap, 0))
            .addOnSuccessListener { result ->
                val texts = mutableListOf<String>()
                val nodes = JSONArray()
                for (block in result.textBlocks) {
                    for (line in block.lines) {
                        val text = MartiScreen.redact(line.text.trim())
                        if (text.isEmpty()) continue
                        texts.add(text)
                        val b = line.boundingBox
                        val json = JSONObject().put("t", text).put("c", "ocr")
                        if (b != null) {
                            json.put(
                                "b",
                                JSONArray(
                                    listOf(
                                        (b.left / SCALE).toInt(),
                                        (b.top / SCALE).toInt(),
                                        (b.right / SCALE).toInt(),
                                        (b.bottom / SCALE).toInt(),
                                    )
                                ),
                            )
                        }
                        nodes.put(json)
                    }
                }
                SharedState.lastOcrAt = System.currentTimeMillis()
                val hash = texts.joinToString("|").hashCode()
                if (MartiScreen.matches(texts) && hash != lastHash) {
                    lastHash = hash
                    LogStore.writeScreen(this, "ocr", target ?: front, "ocr", texts, nodes)
                }
            }
            .addOnCompleteListener {
                busy = false
                bitmap.recycle()
            }
    }

    override fun onDestroy() {
        handler?.removeCallbacksAndMessages(null)
        display?.release()
        reader?.close()
        projection?.stop()
        projection = null
        thread?.quitSafely()
        SharedState.capturing = false
        super.onDestroy()
    }

    companion object {
        const val EXTRA_RESULT_CODE = "result_code"
        const val EXTRA_DATA = "data"
        private const val ACTION_STOP = "stop"
        private const val SCALE = 0.6f
        private const val INTERVAL_MS = 3000L

        fun start(ctx: Context, resultCode: Int, data: Intent) {
            ctx.startForegroundService(
                Intent(ctx, ScreenCaptureService::class.java)
                    .putExtra(EXTRA_RESULT_CODE, resultCode)
                    .putExtra(EXTRA_DATA, data)
            )
        }

        fun stop(ctx: Context) {
            ctx.startService(Intent(ctx, ScreenCaptureService::class.java).setAction(ACTION_STOP))
        }
    }
}

/** Recognizes Martı TAG driver screens from OCR text, so other apps are never logged. */
object MartiScreen {
    private val markers = listOf(
        "kabul et", "iptal et", "adresteyim", "adrese geldim", "yolcuyu ara",
        "yolculuk dogrulamasi", "yolculugu baslat", "yolculugunu degerlendir",
        "yolculuk tercihleri", "odeme yontemi", "selfie dogrulamasi",
    )
    private val lineMarkers = setOf("musait", "bitir", "yolculugu bitir")

    fun fold(s: String): String {
        val sb = StringBuilder(s.length)
        for (ch in s) {
            sb.append(
                when (ch) {
                    'İ', 'I', 'ı', 'Î', 'î' -> 'i'
                    'Ş', 'ş' -> 's'
                    'Ğ', 'ğ' -> 'g'
                    'Ü', 'ü', 'Û', 'û' -> 'u'
                    'Ö', 'ö' -> 'o'
                    'Ç', 'ç' -> 'c'
                    'Â', 'â' -> 'a'
                    '\u0307' -> continue
                    else -> ch.lowercaseChar()
                }
            )
        }
        return sb.toString()
    }

    /** "7 Kas, Cts": the date header of the pulled-down notification shade. */
    private val shadeDate = Regex("""^\d{1,2} (oca|sub|mar|nis|may|haz|tem|agu|eyl|eki|kas|ara)\S*,? (pzt|sal|car|per|cum|cts|cmt|paz)""")
    private val phone = Regex("""\+?\d[\d\s\-()]{8,}\d""")

    /** Replaces phone numbers (10+ digits) that can show up on call and contact screens. */
    fun redact(s: String): String = phone.replace(s) { m ->
        if (m.value.count { it.isDigit() } >= 10) "[tel]" else m.value
    }

    fun matches(texts: List<String>): Boolean {
        if (texts.isEmpty()) return false
        val lines = texts.map { fold(it).trim() }
        val all = lines.joinToString("\n")
        if (all.contains("py stats") || all.contains("tag stats")) return false
        if (lines.any { shadeDate.containsMatchIn(it) || it.startsWith("tag surucu, diger uygulama") }) return false
        return markers.any { all.contains(it) } ||
            lines.any { l -> lineMarkers.any { l.trim(' ', '(', ')', '.', '!').equals(it) } }
    }
}
