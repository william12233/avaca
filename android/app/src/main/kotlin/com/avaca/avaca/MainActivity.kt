package com.avaca.avaca

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import com.github.dart_lang.jni.JniPlugin
import com.github.dart_lang.jni_flutter.JniFlutterPlugin
import com.mr.flutter.plugin.filepicker.FilePickerPlugin
import com.tekartik.sqflite.SqflitePlugin
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.flutter_plugin_android_lifecycle.FlutterAndroidLifecyclePlugin
import io.flutter.plugins.sharedpreferences.SharedPreferencesPlugin
import java.io.File

class MainActivity : FlutterActivity() {
    private val updateChannelName = "com.avaca.avaca/software_update"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val plugins = flutterEngine.plugins

        if (!plugins.has(JniPlugin::class.java)) {
            plugins.add(JniPlugin())
        }
        if (!plugins.has(JniFlutterPlugin::class.java)) {
            plugins.add(JniFlutterPlugin())
        }
        if (!plugins.has(SharedPreferencesPlugin::class.java)) {
            plugins.add(SharedPreferencesPlugin())
        }
        if (!plugins.has(SqflitePlugin::class.java)) {
            plugins.add(SqflitePlugin())
        }
        if (!plugins.has(FilePickerPlugin::class.java)) {
            plugins.add(FilePickerPlugin())
        }
        if (!plugins.has(FlutterAndroidLifecyclePlugin::class.java)) {
            plugins.add(FlutterAndroidLifecyclePlugin())
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, updateChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "canInstallPackages" -> result.success(
                        Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
                            packageManager.canRequestPackageInstalls()
                    )

                    "openInstallPermissionSettings" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            val intent = Intent(
                                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                Uri.parse("package:$packageName")
                            )
                            startActivity(intent)
                        }
                        result.success(null)
                    }

                    "installApk" -> {
                        val apkPath = call.argument<String>("path")
                        if (apkPath.isNullOrBlank()) {
                            result.error("INVALID_PATH", "APK path is missing.", null)
                            return@setMethodCallHandler
                        }
                        val apk = File(apkPath)
                        if (!apk.isFile) {
                            result.error("MISSING_APK", "APK file does not exist.", null)
                            return@setMethodCallHandler
                        }

                        val uri = FileProvider.getUriForFile(
                            this,
                            "$packageName.fileprovider",
                            apk
                        )
                        val intent = Intent(Intent.ACTION_VIEW).apply {
                            setDataAndType(uri, "application/vnd.android.package-archive")
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        startActivity(intent)
                        result.success(true)
                    }

                    else -> result.notImplemented()
                }
            }
    }
}
