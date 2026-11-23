package cn.zhongzhizhushou.planting

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // 应用内更新：下载交给系统 DownloadManager，安装走 FileProvider
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "planting/update")
            .setMethodCallHandler(UpdateBridge(this))
    }
}
