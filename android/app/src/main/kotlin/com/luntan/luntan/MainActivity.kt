package com.luntan.luntan

import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest

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
                        if (!isTrustedUpdateApk(apk)) {
                            result.error(
                                "UNTRUSTED_UPDATE_APK",
                                "安装包校验失败：包名、版本或签名与本应用不一致",
                                null,
                            )
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

    /**
     * 安装前的独立信任根校验：不信任更新 API 自述的 sha256/URL，直接比对本机当前
     * 安装包的签名。包名必须一致、versionCode 不得低于当前、签名证书集合必须与
     * 当前安装包完全一致，任一不满足即拒绝调起安装器。
     */
    private fun isTrustedUpdateApk(apk: File): Boolean {
        val flags = PackageManager.GET_SIGNING_CERTIFICATES or PackageManager.GET_SIGNATURES
        val archiveInfo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            packageManager.getPackageArchiveInfo(
                apk.absolutePath,
                PackageManager.PackageInfoFlags.of(flags.toLong()),
            )
        } else {
            @Suppress("DEPRECATION")
            packageManager.getPackageArchiveInfo(apk.absolutePath, flags)
        } ?: return false
        if (archiveInfo.packageName != packageName) return false
        if (versionCodeOf(archiveInfo) < installedVersionCode()) return false

        val selfInfo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            packageManager.getPackageInfo(
                packageName,
                PackageManager.PackageInfoFlags.of(flags.toLong()),
            )
        } else {
            @Suppress("DEPRECATION")
            packageManager.getPackageInfo(packageName, flags)
        }
        val selfCerts = signingCertSha256(selfInfo) ?: return false
        val apkCerts = signingCertSha256(archiveInfo) ?: return false
        return selfCerts == apkCerts
    }

    private fun installedVersionCode(): Long {
        val info = packageManager.getPackageInfo(packageName, 0)
        return versionCodeOf(info)
    }

    private fun versionCodeOf(info: PackageInfo): Long =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.longVersionCode
        } else {
            @Suppress("DEPRECATION")
            info.versionCode.toLong()
        }

    private fun signingCertSha256(info: PackageInfo): Set<String>? {
        val signatures = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.signingInfo?.apkContentsSigners
        } else {
            @Suppress("DEPRECATION")
            info.signatures
        }
        if (signatures.isNullOrEmpty()) return null
        val digest = MessageDigest.getInstance("SHA-256")
        return signatures.map { sig ->
            digest.digest(sig.toByteArray()).joinToString("") { "%02x".format(it) }
        }.toSet()
    }
}
