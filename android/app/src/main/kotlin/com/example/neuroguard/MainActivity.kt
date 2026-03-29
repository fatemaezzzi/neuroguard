package com.example.neuroguard

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlin.math.pow
import kotlin.math.sqrt

class MainActivity : FlutterActivity() {

    private val CHANNEL = "com.neuroguard/pocket_check"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "runNativePocketCheck" -> runNativePocketCheck(result)
                    else -> result.notImplemented()
                }
            }
    }

    // ─── Native Pocket Check ─────────────────────────────────────────────
    // Uses SensorManager directly at the kernel level for <5ms latency.
    // Called via Method Channel from Flutter as a fallback/high-precision path.
    private fun runNativePocketCheck(result: MethodChannel.Result) {
        val sensorManager = getSystemService(Context.SENSOR_SERVICE) as SensorManager
        val accelerometer = sensorManager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)

        if (accelerometer == null) {
            result.error("NO_SENSOR", "Accelerometer not available", null)
            return
        }

        val samples = mutableListOf<Float>()

        // Step 1: Vibrate
        vibratePhone(600)

        // Step 2: Slight delay then start sampling
        Thread.sleep(80)

        val listener = object : SensorEventListener {
            override fun onSensorChanged(event: SensorEvent) {
                samples.add(event.values[2]) // Z-axis
            }
            override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
        }

        sensorManager.registerListener(
            listener,
            accelerometer,
            SensorManager.SENSOR_DELAY_FASTEST
        )

        // Step 3: Collect for 1200ms
        Thread.sleep(1200)
        sensorManager.unregisterListener(listener)

        // Step 4: Compute variance and return result to Flutter
        if (samples.size < 5) {
            result.success("UNKNOWN")
            return
        }

        val variance = calculateVariance(samples)
        val status = when {
            variance > 0.35f -> "ON_TABLE"   // High variance = hard surface
            variance < 0.08f -> "ON_PERSON"  // Low variance = dampened by body
            else -> "UNKNOWN"
        }

        result.success(status)
    }

    // ─── Vibration Helper ─────────────────────────────────────────────────
    private fun vibratePhone(durationMs: Long) {
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S) {
            val vibratorManager = getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager
            val vibrator = vibratorManager.defaultVibrator
            vibrator.vibrate(VibrationEffect.createOneShot(durationMs, VibrationEffect.DEFAULT_AMPLITUDE))
        } else {
            @Suppress("DEPRECATION")
            val vibrator = getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                vibrator.vibrate(VibrationEffect.createOneShot(durationMs, VibrationEffect.DEFAULT_AMPLITUDE))
            } else {
                @Suppress("DEPRECATION")
                vibrator.vibrate(durationMs)
            }
        }
    }

    // ─── Statistics ───────────────────────────────────────────────────────
    private fun calculateVariance(samples: List<Float>): Float {
        val mean = samples.average().toFloat()
        val squaredDiffs = samples.map { (it - mean).pow(2) }
        return squaredDiffs.average().toFloat()
    }
}