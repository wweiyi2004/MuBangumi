package com.wweiyi.mubangumi

import android.app.Activity
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.plugin.common.MethodChannel
import java.io.File

/** Only opens a verified update of this app from its private update cache. */
object UpdateInstaller {
    @Suppress("DEPRECATION")
    fun handle(activity: Activity, call: io.flutter.plugin.common.MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "abis" -> result.success(Build.SUPPORTED_ABIS.toList())
                "buildNumber" -> {
                    val app = activity.packageManager.getApplicationInfo(activity.packageName, PackageManager.GET_META_DATA)
                    result.success(app.metaData?.get("mubangumi.buildNumber")?.toString())
                }
                "install" -> {
                    val root = File(activity.filesDir, "mubangumi-updates").canonicalFile
                    val apk = File(call.argument<String>("path") ?: "").canonicalFile
                    require(apk.parentFile == root && apk.isFile && apk.extension == "apk")
                    val pm = activity.packageManager
                    val flags = if (Build.VERSION.SDK_INT >= 28) PackageManager.GET_SIGNING_CERTIFICATES else PackageManager.GET_SIGNATURES
                    val update = pm.getPackageArchiveInfo(apk.path, flags) ?: error("Invalid APK")
                    val installed = pm.getPackageInfo(activity.packageName, flags)
                    require(update.packageName == activity.packageName)
                    require(update.versionName == call.argument<String>("version"))
                    val newCode = if (Build.VERSION.SDK_INT >= 28) update.longVersionCode else update.versionCode.toLong()
                    val oldCode = if (Build.VERSION.SDK_INT >= 28) installed.longVersionCode else installed.versionCode.toLong()
                    require(newCode > oldCode)
                    require(signatures(update).isNotEmpty() && signatures(update) == signatures(installed))
                    if (Build.VERSION.SDK_INT >= 26 && !pm.canRequestPackageInstalls()) {
                        activity.startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                            Uri.parse("package:${activity.packageName}")))
                        result.success(false)
                        return
                    }
                    val uri = FileProvider.getUriForFile(activity, "${activity.packageName}.updates", apk)
                    activity.startActivity(Intent(Intent.ACTION_VIEW).apply {
                        setDataAndType(uri, "application/vnd.android.package-archive")
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    })
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        } catch (_: Exception) {
            result.error("update_install_failed", "Unable to open a compatible signed update", null)
        }
    }

    @Suppress("DEPRECATION")
    private fun signatures(info: PackageInfo): Set<String> =
        (if (Build.VERSION.SDK_INT >= 28) info.signingInfo?.apkContentsSigners else info.signatures)
            ?.map { it.toCharsString() }?.toSet() ?: emptySet()
}
