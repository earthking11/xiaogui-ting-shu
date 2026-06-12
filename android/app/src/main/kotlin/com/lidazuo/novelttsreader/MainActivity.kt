package com.lidazuo.novelttsreader

import android.app.Activity
import android.content.ContentResolver
import android.content.Intent
import android.database.Cursor
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileInputStream
import java.nio.charset.Charset
import java.nio.charset.CharacterCodingException
import java.nio.charset.CodingErrorAction

class MainActivity : FlutterActivity() {
    private val channelName = "novel_tts_reader/native_file"
    private val pickTxtRequestCode = 4107
    private var pendingPickResult: MethodChannel.Result? = null
    private var channel: MethodChannel? = null
    private var pendingSharedTxtFile: Map<String, Any?>? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        cacheSharedTxtIntent(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        channel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "pickTxtFile" -> launchTxtPicker(result)
                "consumeSharedTxtFile" -> {
                    result.success(pendingSharedTxtFile)
                    pendingSharedTxtFile = null
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (cacheSharedTxtIntent(intent)) {
            channel?.invokeMethod("sharedTxtAvailable", null)
        }
    }

    private fun launchTxtPicker(result: MethodChannel.Result) {
        if (pendingPickResult != null) {
            result.error("PICK_IN_PROGRESS", "已有一个文件选择窗口正在打开。", null)
            return
        }

        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "text/*"
            putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("text/plain", "application/octet-stream"))
        }

        pendingPickResult = result
        try {
            startActivityForResult(intent, pickTxtRequestCode)
        } catch (error: Exception) {
            pendingPickResult = null
            result.error("PICK_FAILED", error.localizedMessage ?: "无法打开文件选择器。", null)
        }
    }

    @Deprecated("Deprecated in Android embedding, still supported for ACTION_OPEN_DOCUMENT result.")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != pickTxtRequestCode) return

        val result = pendingPickResult ?: return
        pendingPickResult = null

        if (resultCode != Activity.RESULT_OK) {
            result.success(null)
            return
        }

        val uri = data?.data
        if (uri == null) {
            result.error("NO_FILE", "没有选中文件。", null)
            return
        }

        try {
            result.success(readUriAsTxtFile(uri))
        } catch (error: Exception) {
            result.error("READ_FAILED", error.localizedMessage ?: "读取 TXT 失败。", null)
        }
    }

    private fun cacheSharedTxtIntent(intent: Intent?): Boolean {
        val sharedFile = try {
            sharedTxtFileFromIntent(intent)
        } catch (error: Exception) {
            mapOf(
                "fileName" to "分享的TXT",
                "text" to "",
                "encoding" to "error",
                "sizeBytes" to 0,
                "error" to (error.localizedMessage ?: "读取分享文件失败。")
            )
        }

        if (sharedFile == null) return false
        pendingSharedTxtFile = sharedFile
        return true
    }

    private fun sharedTxtFileFromIntent(intent: Intent?): Map<String, Any?>? {
        if (intent == null) return null

        return when (intent.action) {
            Intent.ACTION_SEND -> {
                val streamUri = streamUriFromIntent(intent)
                if (streamUri != null) {
                    readUriAsTxtFile(streamUri)
                } else {
                    val text = intent.getStringExtra(Intent.EXTRA_TEXT)?.takeIf { it.isNotBlank() }
                    text?.let {
                        mapOf(
                            "fileName" to "分享文本.txt",
                            "text" to it,
                            "encoding" to "utf-8",
                            "sizeBytes" to it.toByteArray(Charsets.UTF_8).size
                        )
                    }
                }
            }
            Intent.ACTION_VIEW -> intent.data?.let { readUriAsTxtFile(it) }
            else -> null
        }
    }

    @Suppress("DEPRECATION")
    private fun streamUriFromIntent(intent: Intent): Uri? {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            intent.getParcelableExtra(Intent.EXTRA_STREAM)
        }
    }

    private fun readUriAsTxtFile(uri: Uri): Map<String, Any?> {
        val bytes = readAllBytes(uri)
        val decoded = decodeTxt(bytes)
        return mapOf(
            "fileName" to displayName(uri),
            "text" to decoded.first,
            "encoding" to decoded.second,
            "sizeBytes" to (fileSize(uri) ?: bytes.size)
        )
    }

    private fun readAllBytes(uri: Uri): ByteArray {
        if (uri.scheme == ContentResolver.SCHEME_FILE || uri.scheme.isNullOrBlank()) {
            val path = uri.path ?: error("无法解析文件路径。")
            return FileInputStream(File(path)).use { input ->
                val output = ByteArrayOutputStream()
                val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
                while (true) {
                    val read = input.read(buffer)
                    if (read <= 0) break
                    output.write(buffer, 0, read)
                }
                output.toByteArray()
            }
        }

        contentResolver.openInputStream(uri).use { input ->
            if (input == null) error("无法打开文件流。")
            val output = ByteArrayOutputStream()
            val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
            while (true) {
                val read = input.read(buffer)
                if (read <= 0) break
                output.write(buffer, 0, read)
            }
            return output.toByteArray()
        }
    }

    private fun decodeTxt(bytes: ByteArray): Pair<String, String> {
        val utf8 = Charset.forName("UTF-8")
        return try {
            val decoder = utf8.newDecoder()
                .onMalformedInput(CodingErrorAction.REPORT)
                .onUnmappableCharacter(CodingErrorAction.REPORT)
            Pair(decoder.decode(java.nio.ByteBuffer.wrap(bytes)).toString(), "utf-8")
        } catch (_: CharacterCodingException) {
            Pair(Charset.forName("GB18030").decode(java.nio.ByteBuffer.wrap(bytes)).toString(), "gb18030")
        }
    }

    private fun displayName(uri: Uri): String {
        if (uri.scheme == ContentResolver.SCHEME_FILE || uri.scheme.isNullOrBlank()) {
            return uri.path?.let { File(it).name }?.takeIf { it.isNotBlank() } ?: "未命名.txt"
        }

        try {
            queryOpenable(uri)?.use { cursor ->
                val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (nameIndex >= 0 && cursor.moveToFirst()) {
                    return cursor.getString(nameIndex)
                }
            }
        } catch (_: Exception) {
            // Some file managers grant stream access but fail metadata queries.
        }
        return uri.lastPathSegment?.substringAfterLast('/')?.takeIf { it.isNotBlank() } ?: "未命名.txt"
    }

    private fun fileSize(uri: Uri): Int? {
        if (uri.scheme == ContentResolver.SCHEME_FILE || uri.scheme.isNullOrBlank()) {
            val path = uri.path ?: return null
            val file = File(path)
            if (!file.exists()) return null
            return file.length().coerceAtMost(Int.MAX_VALUE.toLong()).toInt()
        }

        try {
            queryOpenable(uri)?.use { cursor ->
                val sizeIndex = cursor.getColumnIndex(OpenableColumns.SIZE)
                if (sizeIndex >= 0 && cursor.moveToFirst() && !cursor.isNull(sizeIndex)) {
                    return cursor.getLong(sizeIndex).coerceAtMost(Int.MAX_VALUE.toLong()).toInt()
                }
            }
        } catch (_: Exception) {
            return null
        }
        return null
    }

    private fun queryOpenable(uri: Uri): Cursor? {
        if (uri.scheme != ContentResolver.SCHEME_CONTENT) return null
        return contentResolver.query(uri, null, null, null, null)
    }
}
