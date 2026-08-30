package com.luntan.luntan

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    companion object {
        private const val APP_UPDATE_CHANNEL = "luntan/app_update"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            APP_UPDATE_CHANNEL,
        ).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "canInstallPackages" -> result.success(canInstallPackages())
                    "openInstallPermissionSettings" -> {
                        result.success(openInstallPermissionSettings())
                    }
                    "installApk" -> {
                        val path = call.argument<String>("path")
                        val apk = validatedUpdateApk(path)
                        if (apk == null) {
                            result.error("INVALID_APK_PATH", "APK 路径不合法或文件不存在", null)
                            return@setMethodCallHandler
                        }
                        if (!canInstallPackages()) {
                            result.error(
                                "UNKNOWN_SOURCE_NOT_ALLOWED",
                                "请允许本应用安装未知来源应用",
                                null,
                            )
                            return@setMethodCallHandler
                        }
                        val uri = FileProvider.getUriForFile(
                            this,
                            "$packageName.update.fileprovider",
                            apk,
                        )
                        startActivity(
                            Intent(Intent.ACTION_VIEW).apply {
                                setDataAndType(uri, "application/vnd.android.package-archive")
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            },
                        )
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("APP_UPDATE_INSTALLER_FAILED", e.message, null)
            }
        }
    }

    private fun canInstallPackages(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
            packageManager.canRequestPackageInstalls()

    private fun openInstallPermissionSettings(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        startActivity(
            Intent(
                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                Uri.parse("package:$packageName"),
            ),
        )
        return true
    }

    /** 仅允许安装 cache/app_updates 下的 .apk，防止任意路径被传给安装 Intent。 */
    private fun validatedUpdateApk(rawPath: String?): File? {
        if (rawPath.isNullOrBlank()) return null
        val root = File(cacheDir, "app_updates").canonicalFile
        val apk = File(rawPath).canonicalFile
        if (!apk.path.startsWith(root.path + File.separator)) return null
        if (!apk.isFile || !apk.name.endsWith(".apk", ignoreCase = true)) return null
        return apk
    }
}
