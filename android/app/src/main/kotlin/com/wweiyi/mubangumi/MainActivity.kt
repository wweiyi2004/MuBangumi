package com.wweiyi.mubangumi

import io.flutter.embedding.android.FlutterActivity
import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.Context
import android.os.Build
import io.flutter.embedding.engine.FlutterEngineCache

class MainActivity : FlutterActivity() {
    private val pendingShares = ArrayDeque<String>()
    private var sharedLinks: MethodChannel? = null

    override fun provideFlutterEngine(context: Context): FlutterEngine? =
        FlutterEngineCache.getInstance().get(BanjianService.ENGINE)

    override fun shouldDestroyEngineWithHost(): Boolean = false

    override fun onCreate(savedInstanceState: Bundle?) {
        if (savedInstanceState == null) {
            receiveShare(intent)
        } else {
            savedInstanceState.getStringArrayList("pending_shared_links")?.let { pendingShares.addAll(it) }
        }
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        FlutterEngineCache.getInstance().put(BanjianService.ENGINE, flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BanjianService.CHANNEL)
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "start" -> {
                            if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) != android.content.pm.PackageManager.PERMISSION_GRANTED) {
                                requestPermissions(arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), 4200)
                            }
                            val intent = Intent(this, BanjianService::class.java)
                            if (Build.VERSION.SDK_INT >= 26) startForegroundService(intent) else startService(intent)
                            result.success(null)
                        }
                        "stop" -> { stopService(Intent(this, BanjianService::class.java)); result.success(null) }
                        else -> result.notImplemented()
                    }
                } catch (error: Exception) {
                    result.error("banjian_service", error.message, null)
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mubangumi/updates")
            .setMethodCallHandler { call, result -> UpdateInstaller.handle(this, call, result) }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WebsiteCookies.CHANNEL)
            .setMethodCallHandler(WebsiteCookies::handle)
        sharedLinks = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mubangumi/shared_links").also { channel ->
            channel.setMethodCallHandler { call, result ->
                if (call.method == "takePendingText") {
                    result.success(if (pendingShares.isEmpty()) null else pendingShares.removeFirst())
                } else result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        receiveShare(intent)
        sharedLinks?.invokeMethod("available", null)
    }

    private fun receiveShare(source: Intent?) {
        if (source?.action != Intent.ACTION_SEND || source.type != "text/plain") return
        val text = source.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString() ?: return
        if (pendingShares.size >= 8) pendingShares.removeFirst()
        // Oversized input becomes an invalid-link request, never a partial URL.
        pendingShares.addLast(if (text.length <= 16384) text else "")
        source.removeExtra(Intent.EXTRA_TEXT)
    }

    override fun onSaveInstanceState(outState: Bundle) {
        outState.putStringArrayList("pending_shared_links", ArrayList(pendingShares))
        super.onSaveInstanceState(outState)
    }
}
