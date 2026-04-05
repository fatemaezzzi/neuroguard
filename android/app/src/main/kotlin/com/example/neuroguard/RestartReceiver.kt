package com.example.neuroguard

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.util.Log
import androidx.core.content.ContextCompat
import com.pravera.flutter_foreground_task.service.ForegroundService

class RestartReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {

        val hasFine = ContextCompat.checkSelfPermission(
            context, android.Manifest.permission.ACCESS_FINE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED

        val hasBackground = ContextCompat.checkSelfPermission(
            context, android.Manifest.permission.ACCESS_BACKGROUND_LOCATION
        ) == PackageManager.PERMISSION_GRANTED

        if (!hasFine || !hasBackground) {
            Log.w("RestartReceiver",
                "Skipping restart — permissions not granted. " +
                        "hasFine=$hasFine hasBackground=$hasBackground"
            )
            return // breaks the 5-second crash loop
        }

        Log.d("RestartReceiver", "Permissions OK — restarting ForegroundService")
        ContextCompat.startForegroundService(
            context,
            Intent(context, ForegroundService::class.java)
        )
    }
}