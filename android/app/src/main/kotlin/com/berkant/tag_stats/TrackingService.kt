package com.berkant.tag_stats

import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import androidx.core.app.ServiceCompat
import org.json.JSONObject

/** Foreground GPS logger; its last fix is attached to every screen record. */
class TrackingService : Service(), LocationListener {
    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopSelf()
            return START_NOT_STICKY
        }
        if (SharedState.tracking) return START_STICKY

        ServiceCompat.startForeground(
            this,
            Notifications.TRACKING_ID,
            Notifications.build(this, "PY Stats", "Konum kaydediliyor"),
            ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION,
        )

        val lm = getSystemService(LocationManager::class.java)
        try {
            lm.requestLocationUpdates(LocationManager.GPS_PROVIDER, 3000L, 5f, this, Looper.getMainLooper())
            if (lm.isProviderEnabled(LocationManager.NETWORK_PROVIDER)) {
                lm.requestLocationUpdates(LocationManager.NETWORK_PROVIDER, 10000L, 20f, this, Looper.getMainLooper())
            }
        } catch (e: SecurityException) {
            stopSelf()
            return START_NOT_STICKY
        }

        wakeLock = getSystemService(PowerManager::class.java)
            .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "tag_stats:tracking")
            .apply { acquire() }
        SharedState.tracking = true
        SharedState.trackingStartedAt = System.currentTimeMillis()
        LogStore.append(this, "sessions", JSONObject().put("t", SharedState.trackingStartedAt).put("ev", "start"))
        return START_STICKY
    }

    override fun onLocationChanged(location: Location) {
        val prev = SharedState.lastLocation
        // Keep the precise GPS fix unless the network fix is clearly newer.
        if (location.provider == LocationManager.NETWORK_PROVIDER && prev != null &&
            prev.provider == LocationManager.GPS_PROVIDER && location.time - prev.time < 15000
        ) return

        SharedState.lastLocation = location
        LogStore.append(
            this,
            "gps",
            JSONObject()
                .put("t", location.time)
                .put("lat", location.latitude)
                .put("lng", location.longitude)
                .put("acc", location.accuracy.toDouble())
                .put("spd", location.speed.toDouble())
                .put("brg", location.bearing.toDouble())
                .put("alt", location.altitude)
                .put("p", location.provider ?: ""),
        )
    }

    override fun onDestroy() {
        getSystemService(LocationManager::class.java).removeUpdates(this)
        wakeLock?.takeIf { it.isHeld }?.release()
        if (SharedState.tracking) {
            LogStore.append(this, "sessions", JSONObject().put("t", System.currentTimeMillis()).put("ev", "stop"))
        }
        SharedState.tracking = false
        SharedState.trackingStartedAt = 0L
        super.onDestroy()
    }

    companion object {
        private const val ACTION_STOP = "stop"

        fun start(ctx: Context) {
            ctx.startForegroundService(Intent(ctx, TrackingService::class.java))
        }

        fun stop(ctx: Context) {
            ctx.startService(Intent(ctx, TrackingService::class.java).setAction(ACTION_STOP))
        }
    }
}
