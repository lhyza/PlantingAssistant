package cn.zhongzhizhushou.planting

import android.app.Activity
import android.app.DownloadManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.StatFs
import android.content.pm.PackageManager
import androidx.core.content.FileProvider
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest

/**
 * 应用内更新用的原生桥：
 *  - start：交给系统 DownloadManager（通知栏进度、退出 App 继续、断点续传）
 *  - progress：查询下载进度（Dart 侧轮询）
 *  - install：FileProvider + ACTION_VIEW 拉起系统安装器
 *  - apkInfo / selfCert：安装前校验签名与版本
 *  - sha256 / freeSpace：完整性校验与空间检查
 */
class UpdateBridge(private val activity: Activity) : MethodChannel.MethodCallHandler {

    private val ctx: Context get() = activity.applicationContext
    private val dm: DownloadManager
        get() = ctx.getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
    private val prefs by lazy { ctx.getSharedPreferences("planting_update", Context.MODE_PRIVATE) }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "start" -> result.success(start(call))
                "progress" -> result.success(progress(longArg(call, "id")))
                "cancel" -> {
                    val id = longArg(call, "id")
                    if (id > 0) dm.remove(id)
                    result.success(true)
                }
                "install" -> {
                    install(call.argument<String>("path") ?: "")
                    result.success(true)
                }
                "apkInfo" -> result.success(apkInfo(call.argument<String>("path") ?: ""))
                "sha256" -> result.success(sha256(call.argument<String>("path") ?: ""))
                "freeSpace" -> result.success(freeSpace())
                "selfCert" -> result.success(selfCert())
                // 备用下载渠道 / 源码链接：交给系统浏览器或对应 App 打开
                "open" -> result.success(openUrl(call.argument<String>("url") ?: ""))
                "clear" -> {
                    val id = longArg(call, "id")
                    if (id > 0) runCatching { dm.remove(id) }
                    prefs.edit().remove("id").apply()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("update_error", e.message ?: e.toString(), null)
        }
    }

    /**
     * 读 Long 参数。
     *
     * 注意：Dart 侧 StandardMessageCodec 会把能放进 32 位的 int 编码成 INT32，
     * 到 Android 就是 java.lang.Integer。若直接 `call.argument<Long>("id")`
     * 会在运行时抛 ClassCastException: Integer cannot be cast to Long
     * （曾导致「读取下载进度失败」）。所以统一按 Number 转换。
     */
    private fun longArg(call: MethodCall, key: String): Long {
        return when (val v = call.argument<Any>(key)) {
            null -> -1L
            is Number -> v.toLong()
            is String -> v.toLongOrNull() ?: -1L
            else -> -1L
        }
    }

    // ---------------- download ----------------

    private fun start(call: MethodCall): Map<String, Any?> {
        val url = call.argument<String>("url") ?: error("url is null")
        val fileName = call.argument<String>("fileName") ?: "update.apk"
        val title = call.argument<String>("title") ?: "正在下载更新"
        val metered = call.argument<Boolean>("metered") ?: false

        val dir = File(ctx.getExternalFilesDir(null), "updates").apply { mkdirs() }
        val old = File(dir, fileName)
        if (old.exists()) old.delete()

        val req = DownloadManager.Request(Uri.parse(url))
            .setTitle(title)
            .setDescription("退出 App 也会继续下载")
            .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
            .setDestinationInExternalFilesDir(ctx, null, "updates/$fileName")
            .setMimeType("application/vnd.android.package-archive")
            .setAllowedOverMetered(metered)
            .setAllowedOverRoaming(false)
        req.addRequestHeader("User-Agent", "PlantingAssistant-Updater")

        val id = dm.enqueue(req)
        prefs.edit().putLong("id", id).putString("path", old.absolutePath).apply()
        return mapOf("id" to id, "path" to old.absolutePath)
    }

    private fun progress(id: Long): Map<String, Any?> {
        if (id <= 0) return mapOf("status" to "unknown")
        val c = dm.query(DownloadManager.Query().setFilterById(id)) ?: return mapOf("status" to "unknown")
        c.use {
            if (!it.moveToFirst()) return mapOf("status" to "unknown", "id" to id)
            val status = it.getInt(it.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS))
            val sofar = it.getLong(it.getColumnIndexOrThrow(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR))
            var total = it.getLong(it.getColumnIndexOrThrow(DownloadManager.COLUMN_TOTAL_SIZE_BYTES))
            if (total < 0) total = 0
            val reason = it.getInt(it.getColumnIndexOrThrow(DownloadManager.COLUMN_REASON))
            var path = prefs.getString("path", "") ?: ""
            runCatching {
                val local = it.getString(it.getColumnIndexOrThrow(DownloadManager.COLUMN_LOCAL_URI))
                if (!local.isNullOrEmpty()) {
                    val p = Uri.parse(local).path
                    if (!p.isNullOrEmpty()) path = p
                }
            }
            val st = when (status) {
                DownloadManager.STATUS_PENDING -> "pending"
                DownloadManager.STATUS_RUNNING -> "running"
                DownloadManager.STATUS_PAUSED -> "paused"
                DownloadManager.STATUS_SUCCESSFUL -> "successful"
                DownloadManager.STATUS_FAILED -> "failed"
                else -> "unknown"
            }
            return mapOf(
                "id" to id,
                "status" to st,
                "downloaded" to sofar,
                "total" to total,
                "reason" to reason,
                "path" to path
            )
        }
    }

    private fun install(path: String) {
        val f = File(path)
        require(f.exists()) { "安装包不存在" }
        val uri = FileProvider.getUriForFile(ctx, "${ctx.packageName}.fileprovider", f)
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        activity.startActivity(intent)
    }

    /** 用 ACTION_VIEW 打开链接；没有可用应用时返回 false，而不是抛异常。 */
    private fun openUrl(url: String): Boolean {
        if (url.isBlank()) return false
        return runCatching {
            val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url)).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            activity.startActivity(intent)
            true
        }.getOrDefault(false)
    }

    // ---------------- verify ----------------

    private fun apkInfo(path: String): Map<String, Any?>? {
        val f = File(path)
        if (!f.exists()) return null
        val pm = ctx.packageManager
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P)
            PackageManager.GET_SIGNING_CERTIFICATES else @Suppress("DEPRECATION") PackageManager.GET_SIGNATURES
        val info = pm.getPackageArchiveInfo(path, flags) ?: return null
        info.applicationInfo?.sourceDir = path
        info.applicationInfo?.publicSourceDir = path
        return mapOf(
            "packageName" to info.packageName,
            "versionCode" to (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P)
                info.longVersionCode else @Suppress("DEPRECATION") info.versionCode.toLong()),
            "versionName" to (info.versionName ?: ""),
            "certSha256" to certSha256(info)
        )
    }

    private fun selfCert(): String {
        val pm = ctx.packageManager
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P)
            PackageManager.GET_SIGNING_CERTIFICATES else @Suppress("DEPRECATION") PackageManager.GET_SIGNATURES
        val info = pm.getPackageInfo(ctx.packageName, flags)
        return certSha256(info)
    }

    private fun certSha256(info: android.content.pm.PackageInfo): String {
        val sig = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.signingInfo?.apkContentsSigners?.firstOrNull()
        } else {
            @Suppress("DEPRECATION") info.signatures?.firstOrNull()
        } ?: return ""
        return hex(MessageDigest.getInstance("SHA-256").digest(sig.toByteArray()))
    }

    private fun sha256(path: String): String {
        val f = File(path)
        if (!f.exists()) return ""
        val md = MessageDigest.getInstance("SHA-256")
        f.inputStream().use { input ->
            val buf = ByteArray(256 * 1024)
            while (true) {
                val n = input.read(buf)
                if (n <= 0) break
                md.update(buf, 0, n)
            }
        }
        return hex(md.digest())
    }

    private fun hex(bytes: ByteArray): String {
        val sb = StringBuilder(bytes.size * 2)
        for (b in bytes) {
            val v = b.toInt() and 0xFF
            if (v < 16) sb.append('0')
            sb.append(Integer.toHexString(v))
        }
        return sb.toString()
    }

    private fun freeSpace(): Long {
        val dir = ctx.getExternalFilesDir(null) ?: ctx.filesDir
        return try {
            StatFs(dir.absolutePath).availableBytes
        } catch (e: Exception) {
            -1L
        }
    }
}
