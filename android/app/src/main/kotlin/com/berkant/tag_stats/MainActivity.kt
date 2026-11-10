package com.berkant.tag_stats

import android.annotation.SuppressLint
import android.app.Activity
import android.content.ComponentName
import android.content.Intent
import android.media.projection.MediaProjectionManager
import android.net.Uri
import android.os.PowerManager
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

class MainActivity : FlutterActivity() {
    private var pendingCaptureResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getStatus" -> result.success(status())
                "openAccessibilitySettings" -> {
                    startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                    result.success(null)
                }
                "openAppDetails" -> {
                    openAppDetails()
                    result.success(null)
                }
                "openAutostartSettings" -> {
                    openXiaomiAutostart()
                    result.success(null)
                }
                "requestIgnoreBatteryOptimizations" -> {
                    requestIgnoreBatteryOptimizations()
                    result.success(null)
                }
                "startTracking" -> {
                    TrackingService.start(this)
                    result.success(null)
                }
                "stopTracking" -> {
                    TrackingService.stop(this)
                    result.success(null)
                }
                "startCapture" -> {
                    if (pendingCaptureResult != null) {
                        result.success(false)
                    } else {
                        pendingCaptureResult = result
                        val mpm = getSystemService(MediaProjectionManager::class.java)
                        @Suppress("DEPRECATION")
                        startActivityForResult(mpm.createScreenCaptureIntent(), REQUEST_CAPTURE)
                    }
                }
                "stopCapture" -> {
                    ScreenCaptureService.stop(this)
                    result.success(null)
                }
                "setTargetPackage" -> {
                    Prefs.setTarget(this, call.argument<String>("pkg"))
                    result.success(null)
                }
                "setOcrOnStart" -> {
                    Prefs.setOcrOnStart(this, call.argument<Boolean>("value") == true)
                    result.success(null)
                }
                "exportLogs" -> result.success(exportLogs())
                else -> result.notImplemented()
            }
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onResume() {
        super.onResume()
        SharedState.ownAppVisible = true
    }

    override fun onPause() {
        SharedState.ownAppVisible = false
        super.onPause()
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQUEST_CAPTURE) return
        val ok = resultCode == Activity.RESULT_OK && data != null
        if (ok) ScreenCaptureService.start(this, resultCode, data!!)
        pendingCaptureResult?.success(ok)
        pendingCaptureResult = null
    }

    private fun status(): Map<String, Any?> {
        val loc = SharedState.lastLocation
        return mapOf(
            "a11yEnabled" to isAccessibilityEnabled(),
            "a11yConnected" to SharedState.a11yConnected,
            "foregroundPkg" to SharedState.foregroundPkg,
            "targetPkg" to Prefs.target(this),
            "seenPkgs" to Prefs.seen(this),
            "lastTargetEventAt" to SharedState.lastTargetEventAt,
            "lastScreenWrittenAt" to SharedState.lastScreenWrittenAt,
            "screensWritten" to SharedState.screensWritten,
            "tracking" to SharedState.tracking,
            "trackingStartedAt" to SharedState.trackingStartedAt,
            "ocrOnStart" to Prefs.ocrOnStart(this),
            "capturing" to SharedState.capturing,
            "lastOcrAt" to SharedState.lastOcrAt,
            "lastLocation" to loc?.let {
                mapOf(
                    "lat" to it.latitude,
                    "lng" to it.longitude,
                    "acc" to it.accuracy.toDouble(),
                    "t" to it.time,
                )
            },
            "ignoringBatteryOptimizations" to
                getSystemService(PowerManager::class.java).isIgnoringBatteryOptimizations(packageName),
            "logDir" to LogStore.logDir(this).absolutePath,
        )
    }

    private fun isAccessibilityEnabled(): Boolean {
        val enabled = Settings.Secure.getString(contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES)
            ?: return false
        val component = ComponentName(this, MartiAccessibilityService::class.java)
        val names = setOf(component.flattenToString(), component.flattenToShortString())
        return enabled.split(':').any { entry -> names.any { it.equals(entry, ignoreCase = true) } }
    }

    private fun openAppDetails() {
        startActivity(
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName"))
        )
    }

    private fun openXiaomiAutostart() {
        val candidates = listOf(
            ComponentName("com.miui.securitycenter", "com.miui.permcenter.autostart.AutoStartManagementActivity"),
            ComponentName("com.miui.securitycenter", "com.miui.powercenter.PowerSettings"),
        )
        for (c in candidates) {
            try {
                startActivity(Intent().setComponent(c))
                return
            } catch (_: Exception) {
            }
        }
        openAppDetails()
    }

    @SuppressLint("BatteryLife")
    private fun requestIgnoreBatteryOptimizations() {
        try {
            startActivity(
                Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, Uri.parse("package:$packageName"))
            )
        } catch (_: Exception) {
            openAppDetails()
        }
    }

    /** Zips all log files and opens the share sheet; returns the file count. */
    private fun exportLogs(): Int {
        val files = LogStore.logDir(this).listFiles()?.filter { it.isFile } ?: emptyList()
        if (files.isEmpty()) return 0
        val stamp = SimpleDateFormat("yyyyMMdd_HHmm", Locale.US).format(Date())
        val zip = File(cacheDir, "tag_stats_kayitlar_$stamp.zip")
        ZipOutputStream(FileOutputStream(zip)).use { zos ->
            for (f in files) {
                zos.putNextEntry(ZipEntry(f.name))
                f.inputStream().use { it.copyTo(zos) }
                zos.closeEntry()
            }
        }
        val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", zip)
        val send = Intent(Intent.ACTION_SEND)
            .setType("application/zip")
            .putExtra(Intent.EXTRA_STREAM, uri)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        startActivity(Intent.createChooser(send, "Kayıtları paylaş"))
        return files.size
    }

    companion object {
        private const val CHANNEL = "tag_stats/native"
        private const val REQUEST_CAPTURE = 4242
    }
}
