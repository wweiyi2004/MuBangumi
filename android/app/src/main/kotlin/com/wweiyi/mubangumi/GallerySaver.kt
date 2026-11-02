package com.wweiyi.mubangumi

import android.Manifest
import android.app.Activity
import android.content.ContentValues
import android.content.pm.PackageManager
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/** Saves app-generated PNGs, without reading the user's photo library. */
class GallerySaver(private val activity: Activity) {
    private var pending: Triple<ByteArray, String, MethodChannel.Result>? = null
    fun handle(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "savePng") { result.notImplemented(); return }
        val bytes = call.argument<ByteArray>("bytes")
        val name = call.argument<String>("name")?.replace(Regex("[^\\p{L}\\p{N}._-]"), "_")
        if (bytes == null || bytes.isEmpty() || name.isNullOrBlank()) {
            result.error("invalid_image", "图片数据无效", null); return
        }
        if (pending != null) { result.error("busy", "正在保存另一张图片", null); return }
        if (Build.VERSION.SDK_INT < 29 && activity.checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) != PackageManager.PERMISSION_GRANTED) {
            pending = Triple(bytes, name, result)
            activity.requestPermissions(arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE), REQUEST)
        } else save(bytes, name, result)
    }
    fun permissionResult(requestCode: Int, grants: IntArray): Boolean {
        if (requestCode != REQUEST) return false
        val task = pending ?: return true
        pending = null
        if (grants.firstOrNull() == PackageManager.PERMISSION_GRANTED) save(task.first, task.second, task.third)
        else task.third.error("permission_denied", "未获得相册保存权限，可在系统设置中允许后重试", null)
        return true
    }
    private fun save(bytes: ByteArray, name: String, result: MethodChannel.Result) {
        Thread {
            var uri: android.net.Uri? = null
            var legacyFile: File? = null
            try {
                val resolver = activity.contentResolver
                val values = ContentValues().apply {
                    put(MediaStore.Images.Media.DISPLAY_NAME, name)
                    put(MediaStore.Images.Media.MIME_TYPE, "image/png")
                    if (Build.VERSION.SDK_INT >= 29) {
                        put(MediaStore.Images.Media.RELATIVE_PATH, "Pictures/MuBangumi")
                        put(MediaStore.Images.Media.IS_PENDING, 1)
                    } else {
                        @Suppress("DEPRECATION")
                        val directory = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES), "MuBangumi")
                        if (!directory.exists() && !directory.mkdirs()) error("无法创建相册目录")
                        legacyFile = File.createTempFile("MuBangumi_", ".png", directory)
                        @Suppress("DEPRECATION")
                        put(MediaStore.Images.Media.DATA, legacyFile!!.absolutePath)
                    }
                }
                val inserted = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values) ?: error("无法创建相册图片")
                uri = inserted
                (resolver.openOutputStream(inserted) ?: error("无法写入相册图片")).use { it.write(bytes) }
                if (Build.VERSION.SDK_INT >= 29) {
                    val published = resolver.update(inserted, ContentValues().apply { put(MediaStore.Images.Media.IS_PENDING, 0) }, null, null)
                    check(published > 0) { "无法发布相册图片" }
                }
                activity.runOnUiThread { result.success(inserted.toString()) }
            } catch (error: Exception) {
                uri?.let { try { activity.contentResolver.delete(it, null, null) } catch (_: Exception) {} }
                legacyFile?.delete()
                activity.runOnUiThread { result.error("gallery_save", error.message, null) }
            }
        }.start()
    }
    companion object { const val REQUEST = 4210 }
}
