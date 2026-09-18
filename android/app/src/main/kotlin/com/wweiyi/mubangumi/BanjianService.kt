package com.wweiyi.mubangumi

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel

/** User-started LAN activity hosting. The Dart service isolate owns networking
 * and SQLite; this service keeps the shared engine process in the foreground. */
class BanjianService : Service() {
    private var wakeLock: PowerManager.WakeLock? = null
    override fun onBind(intent: Intent?): IBinder? = null
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == STOP) {
            val engine = FlutterEngineCache.getInstance().get(ENGINE)
            if (engine != null) {
                MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
                    .invokeMethod("stopRequested", null)
            }
            stopSelf()
            return START_NOT_STICKY
        }
        val manager = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= 26) {
            manager.createNotificationChannel(NotificationChannel(CHANNEL_ID, "番键会服务", NotificationManager.IMPORTANCE_LOW))
        }
        val open = PendingIntent.getActivity(this, 4201, Intent(this, MainActivity::class.java), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val stop = PendingIntent.getService(this, 4202, Intent(this, BanjianService::class.java).setAction(STOP), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, CHANNEL_ID) else Notification.Builder(this)
        val notification = builder.setSmallIcon(R.drawable.quick_action_qr)
            .setContentTitle("番键会服务运行中")
            .setContentText("同网设备可参与评分。停止服务会断开连接，已确认数据保留。")
            .setContentIntent(open).setOngoing(true)
            .addAction(Notification.Action.Builder(null, "停止服务", stop).build())
            .build()
        if (Build.VERSION.SDK_INT >= 29) {
            startForeground(4200, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE)
        } else startForeground(4200, notification)
        if (wakeLock == null) {
            wakeLock = (getSystemService(POWER_SERVICE) as PowerManager)
                .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "MuBangumi:Banjian")
                .apply { acquire() }
        }
        return START_NOT_STICKY
    }
    override fun onDestroy() {
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
        super.onDestroy()
    }
    companion object {
        const val CHANNEL = "mubangumi/banjian"
        const val CHANNEL_ID = "banjian_host"
        const val ENGINE = "mubangumi_host_engine"
        const val STOP = "com.wweiyi.mubangumi.STOP_BANJIAN"
    }
}
