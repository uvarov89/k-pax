package space.kpax.app

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
    private val channelName = "kpax/android"
    private val installPermissionRequest = 4811
    private var pendingInstallPath: String? = null
    private var pendingInstallResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "cacheDir" -> result.success(cacheDir.absolutePath)
                    "openVpnSettings" -> {
                        try {
                            startActivity(Intent(Settings.ACTION_VPN_SETTINGS))
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("vpn_settings_failed", e.message, null)
                        }
                    }
                    "installApk" -> {
                        val path = call.arguments as? String
                        if (path.isNullOrBlank()) {
                            result.error("bad_path", "Missing APK path", null)
                            return@setMethodCallHandler
                        }
                        try {
                            beginInstall(path, result)
                        } catch (e: Exception) {
                            pendingInstallPath = null
                            pendingInstallResult = null
                            result.error("install_failed", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun beginInstall(path: String, result: MethodChannel.Result) {
        val staged = stageApk(path)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            !packageManager.canRequestPackageInstalls()
        ) {
            pendingInstallPath = staged.absolutePath
            pendingInstallResult = result
            @Suppress("DEPRECATION")
            startActivityForResult(
                Intent(
                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                    Uri.parse("package:$packageName"),
                ),
                installPermissionRequest,
            )
            return
        }
        launchInstaller(staged)
        result.success("started")
    }

    private fun stageApk(path: String): File {
        val source = File(path)
        if (!source.exists() || !source.name.endsWith(".apk", ignoreCase = true)) {
            throw IllegalArgumentException("APK not found")
        }
        // Reuse flutter_singbox FileProvider (${applicationId}.cache + cache_paths).
        val updateName =
            if (packageName.contains("xplm")) "X-Plm-update.apk" else "K-Pax-update.apk"
        val staged = File(cacheDir, updateName)
        if (source.absolutePath != staged.absolutePath) {
            source.copyTo(staged, overwrite = true)
        }
        return staged
    }

    private fun launchInstaller(staged: File) {
        val uri = FileProvider.getUriForFile(
            this,
            "$packageName.cache",
            staged,
        )
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(intent)
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != installPermissionRequest) return
        val result = pendingInstallResult
        val path = pendingInstallPath
        pendingInstallResult = null
        pendingInstallPath = null
        if (result == null || path.isNullOrBlank()) return
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                !packageManager.canRequestPackageInstalls()
            ) {
                result.success("need_permission")
                return
            }
            launchInstaller(File(path))
            result.success("started")
        } catch (e: Exception) {
            result.error("install_failed", e.message, null)
        }
    }
}
