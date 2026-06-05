package com.video.rd.editor

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

class ExportForegroundService : Service() {

    companion object {
        const val CHANNEL_ID      = "video_export_channel"
        const val NOTIFICATION_ID = 1001
        const val ACTION_START    = "com.video.rd.editor.START_EXPORT"
        const val ACTION_STOP     = "com.video.rd.editor.STOP_EXPORT"
        const val ACTION_UPDATE   = "com.video.rd.editor.UPDATE_EXPORT"
        const val EXTRA_PROGRESS  = "progress"   // int 0-100
    }

    private var notificationManager: NotificationManager? = null

    override fun onCreate() {
        super.onCreate()
        notificationManager = getSystemService(NotificationManager::class.java)
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                startForeground(NOTIFICATION_ID, buildNotification(indeterminate = true, progress = 0))
            }
            ACTION_UPDATE -> {
                val progress = intent.getIntExtra(EXTRA_PROGRESS, 0).coerceIn(0, 100)
                val notification = buildNotification(indeterminate = false, progress = progress)
                notificationManager?.notify(NOTIFICATION_ID, notification)
            }
            ACTION_STOP -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                    stopForeground(STOP_FOREGROUND_REMOVE)
                } else {
                    @Suppress("DEPRECATION")
                    stopForeground(true)
                }
                stopSelf()
            }
        }
        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Video Export",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Shows progress while exporting video"
                setSound(null, null)
                enableVibration(false)
            }
            notificationManager?.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(indeterminate: Boolean, progress: Int): Notification {
        val text = if (indeterminate) "Exporting…" else "Exporting… $progress%"
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Video Editor")
            .setContentText(text)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setOngoing(true)
            .setProgress(100, progress, indeterminate)
            .setSilent(true)
            .build()
    }
}
