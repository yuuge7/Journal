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

    private lateinit var platform: JournalPlatform

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (::platform.isInitialized && intent.action == "com.ionel.journal.WRITE") platform.openWriter()
    }
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (::platform.isInitialized) platform.onPermissionResult(requestCode, grantResults)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        platform = JournalPlatform(this, flutterEngine.dartExecutor.binaryMessenger)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "journal/save_file")
            .setMethodCallHandler { call, result ->
                if (call.method == "openFile") {
                    if (pendingResult != null) { result.error("BUSY", "Another file operation is in progress", null); return@setMethodCallHandler }
                    pendingResult = result
                    startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply { addCategory(Intent.CATEGORY_OPENABLE); type = "*/*" }, 4912)
                } else if (call.method == "saveFile") {
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
                        type = when { fileName.endsWith(".pdf") -> "application/pdf"; fileName.endsWith(".md") -> "text/markdown"; fileName.endsWith(".zip") -> "application/zip"; else -> "application/octet-stream" }
                        putExtra(Intent.EXTRA_TITLE, fileName)
                    }
                    startActivityForResult(intent, saveRequestCode)
                } else {
                    result.notImplemented()
                }
            }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (::platform.isInitialized && platform.onActivityResult(requestCode, resultCode)) return
        if (requestCode == 4912) {
            val result = pendingResult; pendingResult = null
            if (resultCode != RESULT_OK || data?.data == null) { result?.success(null); return }
            Thread { try {
                val file = File(cacheDir, "import-${System.currentTimeMillis()}.mjbackup")
                contentResolver.openInputStream(data.data!!).use { input -> requireNotNull(input); file.outputStream().use { input.copyTo(it) } }
                runOnUiThread { result?.success(file.absolutePath) }
            } catch (e: Exception) { runOnUiThread { result?.error("OPEN_FAILED", e.message, null) } } }.start()
            return
        }
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
        Thread { try {
            contentResolver.openOutputStream(uri, "wt").use { out ->
                requireNotNull(out) { "Could not open output stream" }
                File(sourcePath).inputStream().use { it.copyTo(out) }
            }
            val sourceDigest = java.security.MessageDigest.getInstance("SHA-256")
            File(sourcePath).inputStream().use { input ->
                val buffer = ByteArray(65536)
                while (true) { val length = input.read(buffer); if (length < 0) break; sourceDigest.update(buffer, 0, length) }
            }
            val expected = sourceDigest.digest()
            val digest = java.security.MessageDigest.getInstance("SHA-256")
            contentResolver.openInputStream(uri).use { input ->
                requireNotNull(input)
                val buffer = ByteArray(65536)
                while (true) { val length = input.read(buffer); if (length < 0) break; digest.update(buffer, 0, length) }
            }
            require(expected.contentEquals(digest.digest())) { "Saved file verification failed" }
            runOnUiThread { result?.success(true) }
        } catch (e: Exception) {
            runOnUiThread { result?.error("SAVE_FAILED", e.message, null) }
        } }.start()
    }
}
