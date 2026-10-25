package com.avaca.avaca

import android.annotation.SuppressLint
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Bundle
import android.os.IBinder

class ScrapeForegroundService : Service() {
    override fun onCreate() {
        super.onCreate()
        createNotificationChannels(this)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopForegroundService()
            stopSelfResult(startId)
            return START_NOT_STICKY
        }

        if (intent?.action == ACTION_UPDATE) {
            startOrUpdateForeground(intent.extras ?: Bundle())
        }
        return START_NOT_STICKY
    }

    private fun startOrUpdateForeground(arguments: Bundle) {
        val notification = buildProgressNotification(this, arguments)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                PROGRESS_NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
            )
        } else {
            startForeground(PROGRESS_NOTIFICATION_ID, notification)
        }
    }

    private fun stopForegroundService() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
    }

    override fun onDestroy() {
        stopForegroundService()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    companion object {
        const val ACTION_UPDATE = "com.avaca.avaca.action.UPDATE_SCRAPE"
        const val ACTION_STOP = "com.avaca.avaca.action.STOP_SCRAPE"
        const val EXTRA_JOB_ID = "scrape_job_id"

        private const val PROGRESS_CHANNEL_ID = "scrape_progress"
        private const val ATTENTION_CHANNEL_ID = "scrape_attention"
        private const val PROGRESS_NOTIFICATION_ID = 2060
        private const val ATTENTION_NOTIFICATION_ID = 2062

        @SuppressLint("MissingPermission")
        fun showVerificationNotification(
            context: Context,
            arguments: Bundle,
        ) {
            createNotificationChannels(context)
            val manager =
                context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.notify(
                ATTENTION_NOTIFICATION_ID,
                buildVerificationNotification(context, arguments),
            )
        }

        private fun createNotificationChannels(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            val manager =
                context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(
                NotificationChannel(
                    PROGRESS_CHANNEL_ID,
                    "Scrape progress",
                    NotificationManager.IMPORTANCE_LOW,
                ).apply {
                    description = "Background scrape progress"
                    setShowBadge(false)
                },
            )
            manager.createNotificationChannel(
                NotificationChannel(
                    ATTENTION_CHANNEL_ID,
                    "Scrape attention",
                    NotificationManager.IMPORTANCE_DEFAULT,
                ).apply {
                    description = "Scrape actions that need attention"
                },
            )
        }

        private fun buildProgressNotification(
            context: Context,
            arguments: Bundle,
        ): Notification {
            val builder = notificationBuilder(context, PROGRESS_CHANNEL_ID)
                .setSmallIcon(R.drawable.ic_stat_scrape)
                .setContentTitle(arguments.getString("title").orEmpty())
                .setContentText(arguments.getString("body").orEmpty())
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setCategory(Notification.CATEGORY_PROGRESS)
                .setContentIntent(contentIntent(context, arguments))
            builder.setProgress(
                100,
                arguments.getInt("progress", 0).coerceIn(0, 100),
                arguments.getBoolean("indeterminate", false),
            )
            return builder.build()
        }

        private fun buildVerificationNotification(
            context: Context,
            arguments: Bundle,
        ): Notification {
            return notificationBuilder(context, ATTENTION_CHANNEL_ID)
                .setSmallIcon(R.drawable.ic_stat_scrape)
                .setContentTitle(arguments.getString("title").orEmpty())
                .setContentText(arguments.getString("body").orEmpty())
                .setAutoCancel(true)
                .setCategory(Notification.CATEGORY_MESSAGE)
                .setContentIntent(contentIntent(context, arguments))
                .build()
        }

        @Suppress("DEPRECATION")
        private fun notificationBuilder(
            context: Context,
            channelId: String,
        ): Notification.Builder {
            return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(context, channelId)
            } else {
                Notification.Builder(context)
            }
        }

        private fun contentIntent(
            context: Context,
            arguments: Bundle,
        ): PendingIntent {
            val intent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
                putExtra(EXTRA_JOB_ID, arguments.getString("job_id").orEmpty())
            }
            var flags = PendingIntent.FLAG_UPDATE_CURRENT
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                flags = flags or PendingIntent.FLAG_IMMUTABLE
            }
            return PendingIntent.getActivity(
                context,
                arguments.getString("job_id").orEmpty().hashCode(),
                intent,
                flags,
            )
        }
    }
}
