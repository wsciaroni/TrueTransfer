package com.example.truetransfer

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.net.Uri
import android.provider.DocumentsContract
import android.provider.Settings
import android.content.Intent
import android.os.Build
import android.os.Environment
import android.content.pm.PackageManager

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.truetransfer/file_ops"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "deleteFileUri" -> {
                    val uriString = call.argument<String>("uri")
                    if (uriString != null) {
                        try {
                            val uri = Uri.parse(uriString)
                            val deleted = deleteUri(uri)
                            result.success(deleted)
                        } catch (e: Exception) {
                            result.error("DELETE_FAILED", e.message, null)
                        }
                    } else {
                        result.error("BAD_ARGUMENT", "URI is null", null)
                    }
                }
                "checkManageStoragePermission" -> {
                    result.success(hasManageStoragePermission())
                }
                "requestManageStoragePermission" -> {
                    requestManageStoragePermission()
                    result.success(true)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun deleteUri(uri: Uri): Boolean {
        // Stage 1: Try DocumentsContract if it is a document URI
        try {
            if (DocumentsContract.isDocumentUri(this, uri)) {
                if (DocumentsContract.deleteDocument(contentResolver, uri)) {
                    return true
                }
            }
        } catch (e: Exception) {
            // Document provider deletion failed or not supported, proceed to Stage 2
        }

        // Stage 2: Try ContentResolver delete
        try {
            val rowsDeleted = contentResolver.delete(uri, null, null)
            if (rowsDeleted > 0) {
                return true
            }
        } catch (e: Exception) {
            // Content resolver query failed or was blocked, proceed to Stage 3
        }

        // Stage 3: Fallback to physical file deletion if permission is granted
        if (hasManageStoragePermission()) {
            val path = getFilePathFromUri(uri)
            if (path != null) {
                val file = java.io.File(path)
                if (file.exists()) {
                    return file.delete()
                }
            }
        }

        return false
    }

    private fun hasManageStoragePermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            Environment.isExternalStorageManager()
        } else {
            // For Android 10 and below, check if WRITE_EXTERNAL_STORAGE is granted
            checkSelfPermission(android.Manifest.permission.WRITE_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED
        }
    }

    private fun requestManageStoragePermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            try {
                val intent = Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION).apply {
                    data = Uri.parse("package:${packageName}")
                }
                startActivity(intent)
            } catch (e: Exception) {
                val intent = Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION)
                startActivity(intent)
            }
        } else {
            // For Android 10 and below, request standard write permission via app details settings page
            try {
                val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                    data = Uri.parse("package:${packageName}")
                }
                startActivity(intent)
            } catch (e: Exception) {
                // Ignore settings intent errors
            }
        }
    }

    private fun getFilePathFromUri(uri: Uri): String? {
        // Query MediaStore projection to get the physical path
        val projection = arrayOf(android.provider.MediaStore.MediaColumns.DATA)
        try {
            contentResolver.query(uri, projection, null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val columnIndex = cursor.getColumnIndex(android.provider.MediaStore.MediaColumns.DATA)
                    if (columnIndex != -1) {
                        return cursor.getString(columnIndex)
                    }
                }
            }
        } catch (e: Exception) {
            // Ignore query failures
        }

        // Fallback parsing for common external storage SAF URIs
        try {
            if (DocumentsContract.isDocumentUri(this, uri)) {
                val docId = DocumentsContract.getDocumentId(uri)
                val split = docId.split(":")
                if (split.size > 1 && "primary".equals(split[0], ignoreCase = true)) {
                    return Environment.getExternalStorageDirectory().toString() + "/" + split[1]
                }
            }
        } catch (e: Exception) {
            // Ignore SAF resolution failures
        }

        return null
    }
}
