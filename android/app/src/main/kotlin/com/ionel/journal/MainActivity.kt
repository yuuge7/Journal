package com.ionel.journal

import android.content.Intent
import android.net.Uri
import java.io.File
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Exposes a "journal/save_file" channel that copies a prepared file to a
 * user-chosen location via the Storage Access Framework (defaults to
 * Downloads). saveFile(sourcePath, fileName) -> true saved / false cancelled.
 */
class MainActivity : FlutterActivity() {
    private val saveRequestCode = 4911
    private var pendingResult: MethodChannel.Result? = null
    private var pendingSourcePath: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "journal/save_file")
            .setMethodCallHandler { call, result ->
                if (call.method == "saveFile") {
                    val sourcePath = call.argument<String>("sourcePath")
                    val fileName = call.argument<String>("fileName")
                    if (sourcePath == null || fileName == null) {
                        result.error("BAD_ARGS", "sourcePath and fileName required", null)
                        return@setMethodCallHandler
                    }
                    if (pendingResult != null) {
                        result.error("BUSY", "Another save is in progress", null)
                        return@setMethodCallHandler
                    }
                    pendingResult = result
                    pendingSourcePath = sourcePath
                    val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = "application/octet-stream"
                        putExtra(Intent.EXTRA_TITLE, fileName)
                    }
                    startActivityForResult(intent, saveRequestCode)
                } else {
                    result.notImplemented()
                }
            }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != saveRequestCode) {
            super.onActivityResult(requestCode, resultCode, data)
            return
        }
        val result = pendingResult
        val sourcePath = pendingSourcePath
        pendingResult = null
        pendingSourcePath = null

        val uri: Uri? = data?.data
        if (resultCode != RESULT_OK || uri == null || sourcePath == null) {
            result?.success(false)
            return
        }
        try {
            contentResolver.openOutputStream(uri, "wt").use { out ->
                requireNotNull(out) { "Could not open output stream" }
                File(sourcePath).inputStream().use { it.copyTo(out) }
            }
            result?.success(true)
        } catch (e: Exception) {
            result?.error("SAVE_FAILED", e.message, null)
        }
    }
}
