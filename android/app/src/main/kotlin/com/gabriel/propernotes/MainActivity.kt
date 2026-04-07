package com.gabriel.propernotes

import android.content.ClipboardManager
import android.net.Uri
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "proper_notes/clipboard_image",
        ).setMethodCallHandler { call, result ->
            if (call.method != "getImage") {
                result.notImplemented()
                return@setMethodCallHandler
            }

            result.success(readClipboardImage())
        }
    }

    private fun readClipboardImage(): Map<String, Any>? {
        val clipboard = getSystemService(CLIPBOARD_SERVICE) as? ClipboardManager ?: return null
        val clip = clipboard.primaryClip ?: return null

        for (index in 0 until clip.itemCount) {
            val item = clip.getItemAt(index)
            val uri = item.uri ?: item.intent?.data ?: continue
            val mimeType = contentResolver.getType(uri) ?: continue
            if (!mimeType.startsWith("image/")) {
                continue
            }

            val bytes = contentResolver.openInputStream(uri)?.use { it.readBytes() } ?: continue
            return mapOf(
                "bytes" to bytes,
                "extension" to imageExtensionFrom(mimeType, uri),
            )
        }

        return null
    }

    private fun imageExtensionFrom(mimeType: String, uri: Uri): String {
        val fromMime = when (mimeType.lowercase()) {
            "image/jpeg" -> "jpg"
            "image/png" -> "png"
            "image/webp" -> "webp"
            "image/gif" -> "gif"
            else -> null
        }
        if (fromMime != null) {
            return fromMime
        }

        val lastSegment = uri.lastPathSegment.orEmpty()
        val dotIndex = lastSegment.lastIndexOf('.')
        if (dotIndex >= 0 && dotIndex < lastSegment.length - 1) {
            return lastSegment.substring(dotIndex + 1).lowercase()
        }

        return "png"
    }
}
