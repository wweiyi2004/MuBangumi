package com.wweiyi.mubangumi

import android.webkit.CookieManager
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** Preserve the wire value, including percent escapes and base64 padding. */
object WebsiteCookies {
    const val CHANNEL = "mubangumi/website_cookies"
    private const val ORIGIN = "https://bgm.tv"

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        try {
            val manager = CookieManager.getInstance()
            when (call.method) {
                "readBgmCookies" -> result.success(manager.getCookie(ORIGIN) ?: "")
                "setBgmCookie" -> {
                    val header = call.argument<String>("header")
                    if (header.isNullOrBlank() || header.contains('\r') || header.contains('\n')) {
                        result.error("invalid_cookie", "Invalid cookie header", null)
                        return
                    }
                    manager.setCookie(ORIGIN, header) { accepted ->
                        if (accepted) result.success(null)
                        else result.error("cookie_rejected", "WebView rejected the cookie", null)
                    }
                }
                else -> result.notImplemented()
            }
        } catch (_: Exception) {
            // Never put cookie values in diagnostics or platform exceptions.
            result.error("website_cookies", "Unable to access WebView cookies", null)
        }
    }
}
