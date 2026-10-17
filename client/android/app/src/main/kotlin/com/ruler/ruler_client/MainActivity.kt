package com.ruler.ruler_client

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import android.content.Intent

class MainActivity : FlutterActivity() {
    private var deviceFiles: DeviceFilesChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        deviceFiles = DeviceFilesChannel(this, flutterEngine.dartExecutor.binaryMessenger)
    }

    @Deprecated("系统文档选择使用独立 requestCode，保留 Flutter 插件分发")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (deviceFiles?.onActivityResult(requestCode, resultCode, data) != true) {
            super.onActivityResult(requestCode, resultCode, data)
        }
    }

    override fun onDestroy() {
        deviceFiles?.close()
        super.onDestroy()
    }
}
