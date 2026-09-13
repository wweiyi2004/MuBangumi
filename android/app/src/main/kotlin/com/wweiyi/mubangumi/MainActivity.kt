package com.wweiyi.mubangumi

import io.flutter.embedding.android.FlutterActivity
import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val pendingShares = ArrayDeque<String>()
    private var sharedLinks: MethodChannel? = null

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
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mubangumi/updates")
            .setMethodCallHandler { call, result -> UpdateInstaller.handle(this, call, result) }
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
