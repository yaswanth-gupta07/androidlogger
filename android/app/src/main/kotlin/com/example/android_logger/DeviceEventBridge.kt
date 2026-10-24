package com.example.android_logger

import android.annotation.SuppressLint
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.database.ContentObserver
import android.media.AudioManager
import android.os.BatteryManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.util.TimeZone

/**
 * Forwards public Android broadcasts and volume setting changes to Flutter.
 * Receivers are registered only while Dart is listening and are removed after.
 */
class DeviceEventBridge(private val context: Context) : EventChannel.StreamHandler {
    private var events: EventChannel.EventSink? = null
    private var receiver: BroadcastReceiver? = null
    private var volumeObserver: ContentObserver? = null
    private var lastVolumes: Map<String, Int> = emptyMap()
    private var lastBatteryKey: String? = null

    fun attach(messenger: BinaryMessenger) {
        EventChannel(messenger, EVENTS).setStreamHandler(this)
        MethodChannel(messenger, METHODS).setMethodCallHandler { call, result ->
            when (call.method) {
                "snapshot" -> result.success(snapshot())
                else -> result.notImplemented()
            }
        }
    }

    fun detach() {
        onCancel(null)
    }

    override fun onListen(arguments: Any?, eventSink: EventChannel.EventSink?) {
        if (events != null) {
            onCancel(null)
        }
        events = eventSink
        registerBroadcasts()
        registerVolumes()
    }

    override fun onCancel(arguments: Any?) {
        receiver?.let { current ->
            try {
                context.unregisterReceiver(current)
            } catch (_: IllegalArgumentException) {
                // Already unregistered.
            }
        }
        receiver = null
        volumeObserver?.let { observer ->
            context.contentResolver.unregisterContentObserver(observer)
        }
        volumeObserver = null
        events = null
    }

    fun snapshot(): Map<String, Any?> {
        val power = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        val battery = readStickyBattery()
        ensureVolumeBaseline()
        return mapOf(
            "screenInteractive" to power.isInteractive,
            "volumes" to lastVolumes,
            "maxVolumes" to readMaxVolumes(),
            "timeZone" to TimeZone.getDefault().id,
            "battery" to battery,
        )
    }

    @SuppressLint("UnspecifiedRegisterReceiverFlag")
    private fun registerBroadcasts() {
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_SCREEN_ON)
            addAction(Intent.ACTION_SCREEN_OFF)
            addAction(Intent.ACTION_USER_PRESENT)
            addAction(Intent.ACTION_TIME_CHANGED)
            addAction(Intent.ACTION_TIMEZONE_CHANGED)
            addAction(Intent.ACTION_DATE_CHANGED)
            addAction(Intent.ACTION_BATTERY_CHANGED)
        }
        val current = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (intent != null) {
                    handle(intent)
                }
            }
        }
        receiver = current
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.registerReceiver(current, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            context.registerReceiver(current, filter)
        }
    }

    private fun registerVolumes() {
        ensureVolumeBaseline()
        val observer = object : ContentObserver(Handler(Looper.getMainLooper())) {
            override fun onChange(selfChange: Boolean) {
                emitVolumeChanges()
            }
        }
        volumeObserver = observer
        try {
            context.contentResolver.registerContentObserver(
                Settings.System.CONTENT_URI,
                true,
                observer,
            )
        } catch (_: SecurityException) {
            // Volume observation is unavailable on this device. Logging continues.
        }
    }

    private fun handle(intent: Intent) {
        when (intent.action) {
            Intent.ACTION_SCREEN_ON -> emit(mapOf("kind" to "screen", "state" to "on"))
            Intent.ACTION_SCREEN_OFF -> emit(mapOf("kind" to "screen", "state" to "off"))
            Intent.ACTION_USER_PRESENT ->
                emit(mapOf("kind" to "screen", "state" to "user_present"))
            Intent.ACTION_TIME_CHANGED ->
                emit(mapOf("kind" to "time", "change" to "time"))
            Intent.ACTION_TIMEZONE_CHANGED ->
                emit(mapOf("kind" to "time", "change" to "timezone"))
            Intent.ACTION_DATE_CHANGED ->
                emit(mapOf("kind" to "time", "change" to "date"))
            Intent.ACTION_BATTERY_CHANGED -> {
                val battery = batteryPayload(intent) ?: return
                val key = batteryKey(battery)
                if (key == lastBatteryKey) {
                    return
                }
                lastBatteryKey = key
                emit(battery)
            }
        }
    }

    private fun emit(payload: Map<String, Any?>) {
        val sink = events ?: return
        try {
            sink.success(payload)
        } catch (_: IllegalStateException) {
            events = null
        }
    }

    private fun emitVolumeChanges() {
        val current = readVolumes()
        if (lastVolumes.isEmpty()) {
            lastVolumes = current
            return
        }
        val maxVolumes = readMaxVolumes()
        for ((stream, value) in current) {
            val previous = lastVolumes[stream] ?: continue
            if (previous != value) {
                emit(
                    mapOf(
                        "kind" to "audio",
                        "stream" to stream,
                        "volume" to value,
                        "previous" to previous,
                        "max" to (maxVolumes[stream] ?: -1),
                    ),
                )
            }
        }
        lastVolumes = current
    }

    private fun ensureVolumeBaseline() {
        if (lastVolumes.isEmpty()) {
            lastVolumes = readVolumes()
        }
    }

    private fun readVolumes(): Map<String, Int> {
        val manager = audioManager() ?: return emptyMap()
        return mapOf(
            "media" to manager.getStreamVolume(AudioManager.STREAM_MUSIC),
            "notification" to manager.getStreamVolume(AudioManager.STREAM_NOTIFICATION),
            "ring" to manager.getStreamVolume(AudioManager.STREAM_RING),
            "alarm" to manager.getStreamVolume(AudioManager.STREAM_ALARM),
        )
    }

    private fun readMaxVolumes(): Map<String, Int> {
        val manager = audioManager() ?: return emptyMap()
        return mapOf(
            "media" to manager.getStreamMaxVolume(AudioManager.STREAM_MUSIC),
            "notification" to manager.getStreamMaxVolume(AudioManager.STREAM_NOTIFICATION),
            "ring" to manager.getStreamMaxVolume(AudioManager.STREAM_RING),
            "alarm" to manager.getStreamMaxVolume(AudioManager.STREAM_ALARM),
        )
    }

    private fun audioManager(): AudioManager? {
        return context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
    }

    @SuppressLint("UnspecifiedRegisterReceiverFlag")
    private fun readStickyBattery(): Map<String, Any?>? {
        val sticky = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.registerReceiver(
                null,
                IntentFilter(Intent.ACTION_BATTERY_CHANGED),
                Context.RECEIVER_NOT_EXPORTED,
            )
        } else {
            context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        }
        val payload = sticky?.let { batteryPayload(it) } ?: return null
        lastBatteryKey = batteryKey(payload)
        return payload
    }

    private fun batteryPayload(intent: Intent): Map<String, Any?>? {
        val level = intent.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
        val scale = intent.getIntExtra(BatteryManager.EXTRA_SCALE, -1)
        if (level < 0 || scale <= 0) {
            return null
        }
        val percent = (level * 100) / scale
        val status = when (intent.getIntExtra(BatteryManager.EXTRA_STATUS, -1)) {
            BatteryManager.BATTERY_STATUS_CHARGING -> "charging"
            BatteryManager.BATTERY_STATUS_DISCHARGING -> "discharging"
            BatteryManager.BATTERY_STATUS_FULL -> "full"
            BatteryManager.BATTERY_STATUS_NOT_CHARGING -> "not_charging"
            else -> "unknown"
        }
        val plugged = intent.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0)
        return mapOf(
            "kind" to "battery",
            "level" to percent,
            "status" to status,
            "plug" to plugName(plugged),
        )
    }

    private fun plugName(plugged: Int): String {
        return when (plugged) {
            BatteryManager.BATTERY_PLUGGED_AC -> "ac"
            BatteryManager.BATTERY_PLUGGED_USB -> "usb"
            BatteryManager.BATTERY_PLUGGED_WIRELESS -> "wireless"
            0 -> "none"
            else -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                    plugged == BatteryManager.BATTERY_PLUGGED_DOCK
                ) {
                    "dock"
                } else {
                    "other"
                }
            }
        }
    }

    private fun batteryKey(payload: Map<String, Any?>): String {
        return "${payload["level"]}|${payload["status"]}|${payload["plug"]}"
    }

    companion object {
        const val METHODS = "com.example.android_logger/device_snapshot"
        const val EVENTS = "com.example.android_logger/device_events"
    }
}
