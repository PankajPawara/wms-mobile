package com.example.wms_mobile

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.net.Uri
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity(), SensorEventListener {
    private val CHANNEL = "com.example.wms_mobile/light_sensor"
    private val SOUND_CHANNEL = "com.example.wms_mobile/sound"
    private val FILE_PICKER_CHANNEL = "com.example.wms_mobile/file_picker"
    private val FILE_PICK_REQUEST = 1001

    private var sensorManager: SensorManager? = null
    private var lightSensor: Sensor? = null
    private var eventSink: EventChannel.EventSink? = null
    private var filePickerResult: MethodChannel.Result? = null

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

        // Native file picker — opens Android's document picker for Excel/CSV files
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, FILE_PICKER_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "pickExcelFile") {
                filePickerResult = result
                val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = "*/*"
                    putExtra(Intent.EXTRA_MIME_TYPES, arrayOf(
                        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", // .xlsx
                        "application/vnd.ms-excel",  // .xls
                        "text/csv",                   // .csv
                        "text/comma-separated-values"
                    ))
                }
                startActivityForResult(intent, FILE_PICK_REQUEST)
            } else {
                result.notImplemented()
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == FILE_PICK_REQUEST) {
            if (resultCode == Activity.RESULT_OK && data?.data != null) {
                val uri: Uri = data.data!!
                // Get the real file path from the URI
                val filePath = getRealPathFromUri(uri)
                filePickerResult?.success(filePath ?: uri.toString())
            } else {
                filePickerResult?.success(null) // user cancelled
            }
            filePickerResult = null
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }

    private fun getRealPathFromUri(uri: Uri): String? {
        return try {
            // For content:// URIs, copy to a temp file and return that path
            if (uri.scheme == "content") {
                val inputStream = contentResolver.openInputStream(uri) ?: return null
                val fileName = getFileNameFromUri(uri) ?: "upload_${System.currentTimeMillis()}.xlsx"
                val tempFile = java.io.File(cacheDir, fileName)
                tempFile.outputStream().use { output -> inputStream.copyTo(output) }
                inputStream.close()
                tempFile.absolutePath
            } else {
                uri.path
            }
        } catch (e: Exception) {
            null
        }
    }

    private fun getFileNameFromUri(uri: Uri): String? {
        var name: String? = null
        contentResolver.query(uri, null, null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) {
                val idx = cursor.getColumnIndex(android.provider.OpenableColumns.DISPLAY_NAME)
                if (idx >= 0) name = cursor.getString(idx)
            }
        }
        return name
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
