package com.ruler.ruler_client

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/** 系统另存为，仅复制应用私有暂存文件，不申请全盘权限。 */
class DeviceFilesChannel(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "ruler/device_files")
    private val executor = Executors.newSingleThreadExecutor()
    private val root = File(activity.cacheDir, "ruler-transfers")
    private var pending: SaveRequest? = null
    private val requestCode = 19472

    private class SaveRequest(val file: File, val result: MethodChannel.Result) {
        val cancelled = AtomicBoolean(false)
    }

    init { channel.setMethodCallHandler(::handle) }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "temporaryRoot" -> {
                    check(root.isDirectory || root.mkdirs())
                    result.success(root.path)
                }
                "releaseSelection" -> {
                    releaseSelection(call.argument<String>("path") ?: "")
                    result.success(null)
                }
                "save" -> save(call, result)
                "cancel" -> { pending?.cancelled?.set(true); result.success(null) }
                else -> result.notImplemented()
            }
        } catch (_: Exception) {
            result.error("FILE_OPERATION_FAILED", "文件操作未完成。", null)
        }
    }

    private fun save(call: MethodCall, result: MethodChannel.Result) {
        check(pending == null)
        val file = File(call.argument<String>("path") ?: "").canonicalFile
        check(file.parentFile?.parentFile == root.canonicalFile)
        check(file.parentFile?.name?.startsWith("ruler-transfer-") == true)
        check(file.name == "content" && file.isFile && file.length() in 1..209715200L)
        val name = call.argument<String>("name") ?: "案件文件.bin"
        check(name.length in 1..180 && !name.contains('/') && !name.contains('\\'))
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = call.argument<String>("mime") ?: "application/octet-stream"
            putExtra(Intent.EXTRA_TITLE, name)
        }
        pending = SaveRequest(file, result)
        try {
            activity.startActivityForResult(intent, requestCode)
        } catch (_: Exception) {
            pending = null
            result.error("SAVE_UNAVAILABLE", "无法打开系统保存窗口。", null)
        }
    }

    /** 只处理本桥接创建的文档；取消不复制，失败清理本次新建文档。 */
    fun onActivityResult(code: Int, resultCode: Int, data: Intent?): Boolean {
        if (code != requestCode) return false
        val request = pending ?: return true
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null || uri.scheme != "content") {
            finish(request, false)
            return true
        }
        executor.execute { copy(request, uri) }
        return true
    }

    private fun copy(request: SaveRequest, uri: Uri) {
        var success = false
        try {
            check(!request.cancelled.get())
            activity.contentResolver.openOutputStream(uri, "w").use { output ->
                checkNotNull(output)
                request.file.inputStream().use { input ->
                    val buffer = ByteArray(64 * 1024)
                    var count = input.read(buffer)
                    while (count >= 0) {
                        check(!request.cancelled.get())
                        output.write(buffer, 0, count)
                        count = input.read(buffer)
                    }
                }
                check(!request.cancelled.get())
                output.flush()
            }
            success = !request.cancelled.get()
        } catch (_: Exception) {
            // 不将 URI、私有路径、文件正文或平台异常写入日志。
        }
        if (!success) {
            try { DocumentsContract.deleteDocument(activity.contentResolver, uri) }
            catch (_: Exception) { /* 文档提供方可能拒绝清理部分文件。 */ }
        }
        activity.runOnUiThread {
            if (success) finish(request, true)
            else fail(request)
        }
    }

    private fun finish(request: SaveRequest, success: Boolean) {
        if (pending !== request) return
        pending = null
        request.result.success(success)
    }

    private fun fail(request: SaveRequest) {
        if (pending !== request) return
        pending = null
        request.result.error("SAVE_FAILED", "保存未完成，请检查目标位置。", null)
    }

    private fun releaseSelection(path: String) {
        val file = File(path).canonicalFile
        val parent = file.parentFile ?: return
        // 官方 file_selector 的临时副本为 cacheDir/UUID/name，原文件不在此处。
        if (parent.parentFile != activity.cacheDir.canonicalFile) return
        if (!Regex("[a-fA-F0-9-]{36}").matches(parent.name)) return
        if (file.delete()) parent.delete() // 非递归，只删已知文件及空目录。
    }

    /** Activity 销毁后禁止保存；线程完成时自行释放输出流。 */
    fun close() {
        pending?.cancelled?.set(true)
        channel.setMethodCallHandler(null)
        executor.shutdown()
    }
}
