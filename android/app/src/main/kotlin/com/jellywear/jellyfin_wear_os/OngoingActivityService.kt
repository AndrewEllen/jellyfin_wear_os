package com.jellywear.jellyfin_wear_os

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.wear.ongoing.OngoingActivity
import androidx.wear.ongoing.Status

class OngoingActivityService : Service() {

    companion object {
        private const val NOTIFICATION_ID = 1
        private const val CHANNEL_ID = "jellyfin_remote_channel"

        fun start(context: Context, title: String = "Jellyfin Remote") {
            val intent = Intent(context, OngoingActivityService::class.java).apply {
                putExtra("title", title)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            // Explicitly cancel notification in case onDestroy doesn't run (process kill)
            val notificationManager = context.getSystemService(NotificationManager::class.java)
            notificationManager?.cancel(NOTIFICATION_ID)
            context.stopService(Intent(context, OngoingActivityService::class.java))
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val title = intent?.getStringExtra("title") ?: "Jellyfin Remote"
        startForegroundWithOngoingActivity(title)
        return START_NOT_STICKY
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Jellyfin Remote",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Shows when Jellyfin remote is active"
                setShowBadge(false)
            }
            val notificationManager = getSystemService(NotificationManager::class.java)
            notificationManager.createNotificationChannel(channel)
        }
    }

    private fun startForegroundWithOngoingActivity(title: String) {
        val pendingIntent = PendingIntent.getActivity(
            this,
            NOTIFICATION_ID,
            Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notificationBuilder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText("Tap to return to remote")
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setCategory(NotificationCompat.CATEGORY_TRANSPORT)
            .setContentIntent(pendingIntent)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOngoing(true)

        val ongoingActivityStatus = Status.Builder()
            .addTemplate(title)
            .build()

        val ongoingActivity = OngoingActivity.Builder(applicationContext, NOTIFICATION_ID, notificationBuilder)
            .setStaticIcon(android.R.drawable.ic_media_play)
            .setTouchIntent(pendingIntent)
            .setStatus(ongoingActivityStatus)
            .build()

        ongoingActivity.apply(applicationContext)

        startForeground(NOTIFICATION_ID, notificationBuilder.build())
    }

    override fun onDestroy() {
        stopForeground(STOP_FOREGROUND_REMOVE)
        getSystemService(NotificationManager::class.java)?.cancel(NOTIFICATION_ID)
        super.onDestroy()
    }
}
