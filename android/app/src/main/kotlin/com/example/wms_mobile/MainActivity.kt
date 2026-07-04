package com.example.wms_mobile

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity(), SensorEventListener {
    private val CHANNEL = "com.example.wms_mobile/light_sensor"
    private val SOUND_CHANNEL = "com.example.wms_mobile/sound"
    private var sensorManager: SensorManager? = null
    private var lightSensor: Sensor? = null
    private var eventSink: EventChannel.EventSink? = null

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        sensorManager = getSystemService(Context.SENSOR_SERVICE) as SensorManager
        lightSensor = sensorManager?.getDefaultSensor(Sensor.TYPE_LIGHT)

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                    sensorManager?.registerListener(this@MainActivity, lightSensor, SensorManager.SENSOR_DELAY_NORMAL)
                }

                override fun onCancel(arguments: Any?) {
                    sensorManager?.unregisterListener(this@MainActivity)
                    eventSink = null
                }
            }
        )

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SOUND_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "playBeep") {
                val type = call.argument<String>("type") ?: "success"
                playScanBeep(type)
                result.success(true)
            } else {
                result.notImplemented()
            }
        }
    }

    private fun playScanBeep(type: String) {
        try {
            val toneType = if (type == "error") {
                android.media.ToneGenerator.TONE_CDMA_PIP
            } else {
                android.media.ToneGenerator.TONE_PROP_BEEP
            }
            val toneGen = android.media.ToneGenerator(android.media.AudioManager.STREAM_MUSIC, 85)
            toneGen.startTone(toneType, 150)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    override fun onSensorChanged(event: SensorEvent?) {
        if (event != null && event.sensor.type == Sensor.TYPE_LIGHT) {
            val lux = event.values[0]
            runOnUiThread {
                eventSink?.success(lux.toDouble())
            }
        }
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
}
