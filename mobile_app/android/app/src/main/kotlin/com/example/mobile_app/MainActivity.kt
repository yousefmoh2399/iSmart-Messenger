package com.example.mobile_app

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
    private val installerChannel = "app.installer"
    private val shareChannel = "app.share_receiver"
    private var shareMethodChannel: MethodChannel? = null
    private var pendingShare: Map<String, Any?>? = null

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        captureShareIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        captureShareIntent(intent)
    }

    private fun captureShareIntent(intent: Intent?) {
        if (intent?.action != Intent.ACTION_SEND && intent?.action != Intent.ACTION_SEND_MULTIPLE) return
        val paths = mutableListOf<String>()
        val streams: List<Uri> = if (intent.action == Intent.ACTION_SEND_MULTIPLE) {
            intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM) ?: emptyList()
        } else {
            listOfNotNull(intent.getParcelableExtra(Intent.EXTRA_STREAM))
        }
        streams.forEachIndexed { index, uri ->
            try {
                val extension = contentResolver.getType(uri)?.substringAfterLast('/') ?: "jpg"
                val target = File(cacheDir, "shared_${System.currentTimeMillis()}_${index}.$extension")
                contentResolver.openInputStream(uri)?.use { input -> target.outputStream().use { output -> input.copyTo(output) } }
                if (target.exists()) paths.add(target.absolutePath)
            } catch (_: Exception) { }
        }
        val text = intent.getStringExtra(Intent.EXTRA_TEXT) ?: ""
        if (paths.isEmpty() && text.isBlank()) return
        pendingShare = mapOf("text" to text, "paths" to paths)
        shareMethodChannel?.invokeMethod("sharedContent", pendingShare)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, installerChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "canInstallUnknownApps" -> {
                        val allowed = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            packageManager.canRequestPackageInstalls()
                        } else {
                            true
                        }
                        result.success(allowed)
                    }
                    "openUnknownAppsSettings" -> {
                        try {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                val intent = Intent(
                                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                    Uri.parse("package:$packageName"),
                                )
                                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                startActivity(intent)
                            } else {
                                val intent = Intent(Settings.ACTION_SECURITY_SETTINGS)
                                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                startActivity(intent)
                            }
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("OPEN_SETTINGS_FAILED", e.message, null)
                        }
                    }
                    "installApk" -> {
                        val apkPath = call.argument<String>("apkPath")
                        if (apkPath.isNullOrBlank()) {
                            result.error("INVALID_PATH", "apkPath is required", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val apkFile = File(apkPath)
                            if (!apkFile.exists()) {
                                result.error("FILE_NOT_FOUND", "APK file not found", null)
                                return@setMethodCallHandler
                            }
                            val apkUri = FileProvider.getUriForFile(
                                this,
                                "$packageName.fileprovider",
                                apkFile,
                            )
                            val installIntent = Intent(Intent.ACTION_VIEW).apply {
                                setDataAndType(
                                    apkUri,
                                    "application/vnd.android.package-archive",
                                )
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            }
                            startActivity(installIntent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("INSTALL_INTENT_FAILED", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        shareMethodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, shareChannel)
        shareMethodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialSharedContent" -> { result.success(pendingShare); pendingShare = null }
                else -> result.notImplemented()
            }
        }
    }
}
