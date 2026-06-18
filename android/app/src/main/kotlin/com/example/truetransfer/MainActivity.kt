package com.example.truetransfer

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.net.Uri

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.truetransfer/file_ops"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "deleteFileUri") {
                val uriString = call.argument<String>("uri")
                if (uriString != null) {
                    try {
                        val uri = Uri.parse(uriString)
                        val deleted = contentResolver.delete(uri, null, null)
                        if (deleted > 0) {
                            result.success(true)
                        } else {
                            result.success(false)
                        }
                    } catch (e: Exception) {
                        result.error("DELETE_FAILED", e.message, null)
                    }
                } else {
                    result.error("BAD_ARGUMENT", "URI is null", null)
                }
            } else {
                result.notImplemented()
            }
        }
    }
}
