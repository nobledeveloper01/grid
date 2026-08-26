package com.gridapp.grid

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Observes mains power by watching the device's charging state.
 *
 * This is an inference, not a measurement, and the class is careful not to
 * overstate it. What it reports is "this phone is on charge", which is a
 * proxy for "the grid is up" that holds for a user who keeps their phone
 * plugged in at home and fails for one on an inverter — which is why the app
 * lets that user turn it off entirely.
 *
 * The capability reported here is [PlatformCapability.periodic]: a registered
 * receiver keeps working while the app is alive, but Android will kill the
 * process, and the OEMs that dominate this market are especially quick about
 * it. Claiming `continuous` would put a number in a dispute pack that the
 * platform never promised. See ADR-0006.
 */
class SupplyMonitorPlugin(
    private val context: Context,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    companion object {
        const val METHOD_CHANNEL = "grid/supply_monitor"
        const val EVENT_CHANNEL = "grid/supply_monitor/samples"
    }

    private var events: EventChannel.EventSink? = null
    private var receiver: BroadcastReceiver? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            // Honest about what a registered receiver can promise. Upgrading
            // this to "continuous" would require a foreground service the
            // user has actually accepted.
            "capability" -> result.success("periodic")
            "current" -> result.success(sample())
            "start" -> { register(); result.success(null) }
            "stop" -> { unregister(); result.success(null) }
            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
        events = sink
        register()
        // Emit immediately, so the first frame after a cold start has a
        // reading rather than a gap.
        sample()?.let { sink?.success(it) }
    }

    override fun onCancel(arguments: Any?) {
        unregister()
        events = null
    }

    private fun register() {
        if (receiver != null) return
        receiver = object : BroadcastReceiver() {
            override fun onReceive(ctx: Context?, intent: Intent?) {
                sample()?.let { events?.success(it) }
            }
        }
        // ACTION_POWER_CONNECTED / DISCONNECTED fire on the transition itself,
        // which is what the debounce in Dart is timing.
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_POWER_CONNECTED)
            addAction(Intent.ACTION_POWER_DISCONNECTED)
        }
        context.registerReceiver(receiver, filter)
    }

    private fun unregister() {
        receiver?.let {
            try {
                context.unregisterReceiver(it)
            } catch (_: IllegalArgumentException) {
                // Already gone. Not worth reporting.
            }
        }
        receiver = null
    }

    /** A snapshot of the current charging state, or null if unreadable. */
    private fun sample(): Map<String, Any>? {
        val status = context.registerReceiver(
            null,
            IntentFilter(Intent.ACTION_BATTERY_CHANGED),
        ) ?: return null

        val plugged = status.getIntExtra(BatteryManager.EXTRA_PLUGGED, -1)
        val level = status.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
        val scale = status.getIntExtra(BatteryManager.EXTRA_SCALE, -1)

        // Wireless charging counts; a phone charging wirelessly is still a
        // phone with mains behind it.
        val charging = plugged == BatteryManager.BATTERY_PLUGGED_AC ||
            plugged == BatteryManager.BATTERY_PLUGGED_USB ||
            plugged == BatteryManager.BATTERY_PLUGGED_WIRELESS

        val percent = if (level >= 0 && scale > 0) level * 100 / scale else -1

        return mapOf(
            "charging" to charging,
            "at" to System.currentTimeMillis(),
            "battery" to percent,
        )
    }
}
