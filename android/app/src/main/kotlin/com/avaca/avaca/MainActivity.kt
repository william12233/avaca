package com.avaca.avaca

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
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
    private val scrapeBackgroundChannelName = "com.avaca.avaca/scrape_background"
    private val notificationPermissionRequestCode = 2061
    private var scrapeBackgroundChannel: MethodChannel? = null
    private var pendingScrapeJobId: String? = null

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

        scrapeBackgroundChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            scrapeBackgroundChannelName,
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestNotificationPermission" -> {
                        if (
                            Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
                                PackageManager.PERMISSION_GRANTED
                        ) {
                            requestPermissions(
                                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                                notificationPermissionRequestCode,
                            )
                        }
                        result.success(null)
                    }

                    "startForeground", "updateForeground" -> {
                        startScrapeForegroundService(
                            call.arguments,
                            updateOnly = call.method == "updateForeground",
                        )
                        result.success(null)
                    }

                    "stopForeground" -> {
                        stopService(
                            Intent(this, ScrapeForegroundService::class.java),
                        )
                        result.success(null)
                    }

                    "showVerificationNotification" -> {
                        ScrapeForegroundService.showVerificationNotification(
                            this,
                            scrapePayload(call.arguments),
                        )
                        result.success(null)
                    }

                    "consumePendingJobId" -> {
                        val jobId = pendingScrapeJobId
                        pendingScrapeJobId = null
                        result.success(jobId)
                    }

                    else -> result.notImplemented()
                }
            }
        }

        // The initial notification intent can arrive before Dart has installed
        // its MethodChannel handler. Keep it until the Dart side consumes it.
        captureScrapeNotificationIntent(intent, notifyDart = false)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        captureScrapeNotificationIntent(intent, notifyDart = true)
    }

    private fun startScrapeForegroundService(
        arguments: Any?,
        updateOnly: Boolean,
    ) {
        val intent = Intent(this, ScrapeForegroundService::class.java).apply {
            action = ScrapeForegroundService.ACTION_UPDATE
            putExtras(scrapePayload(arguments))
        }
        if (!updateOnly && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    private fun scrapePayload(arguments: Any?): android.os.Bundle {
        val values = arguments as? Map<*, *> ?: emptyMap<Any?, Any?>()
        return android.os.Bundle().apply {
            putString("job_id", values["jobId"]?.toString().orEmpty())
            putString("title", values["title"]?.toString().orEmpty())
            putString("body", values["body"]?.toString().orEmpty())
            putInt("progress", (values["progress"] as? Number)?.toInt() ?: 0)
            putBoolean(
                "indeterminate",
                values["indeterminate"] as? Boolean ?: false,
            )
        }
    }

    private fun captureScrapeNotificationIntent(
        intent: Intent?,
        notifyDart: Boolean,
    ) {
        val jobId = intent?.getStringExtra(ScrapeForegroundService.EXTRA_JOB_ID)
            ?.trim()
            ?.takeIf { it.isNotEmpty() }
            ?: return
        pendingScrapeJobId = jobId
        if (notifyDart) {
            scrapeBackgroundChannel?.invokeMethod("notificationTap", jobId)
        }
    }
}
