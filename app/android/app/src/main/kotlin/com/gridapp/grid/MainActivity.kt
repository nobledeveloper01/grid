package com.gridapp.grid

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            TextRecogniserPlugin.CHANNEL,
        ).setMethodCallHandler(TextRecogniserPlugin(applicationContext))

        val supply = SupplyMonitorPlugin(applicationContext)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SupplyMonitorPlugin.METHOD_CHANNEL,
        ).setMethodCallHandler(supply)
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SupplyMonitorPlugin.EVENT_CHANNEL,
        ).setStreamHandler(supply)
    }
}
