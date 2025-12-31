package com.jellywear.jellyfin_wear_os

import android.os.Bundle
import android.view.KeyEvent
import android.view.MotionEvent
import androidx.wear.ambient.AmbientLifecycleObserver
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.samsung.wearable_rotary.WearableRotaryPlugin

class MainActivity: FlutterFragmentActivity() {
    private val CHANNEL = "com.jellywear.jellyfin_wear_os/ongoing_activity"
    private val BUTTON_CHANNEL = "com.jellywear.jellyfin_wear_os/hardware_buttons"

    private var buttonMethodChannel: MethodChannel? = null
    private lateinit var ambientObserver: AmbientLifecycleObserver

    private val ambientCallback = object : AmbientLifecycleObserver.AmbientLifecycleCallback {
        override fun onEnterAmbient(ambientDetails: AmbientLifecycleObserver.AmbientDetails) {
            // App enters ambient mode - screen dims but app stays active
        }

        override fun onExitAmbient() {
            // App exits ambient mode - screen returns to normal
        }

        override fun onUpdateAmbient() {
            // Called periodically in ambient mode for updates
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        ambientObserver = AmbientLifecycleObserver(this, ambientCallback)
        lifecycle.addObserver(ambientObserver)
    }

    override fun onDestroy() {
        lifecycle.removeObserver(ambientObserver)
        super.onDestroy()
    }

    override fun onGenericMotionEvent(event: MotionEvent?): Boolean {
        return when {
            WearableRotaryPlugin.onGenericMotionEvent(event) -> true
            else -> super.onGenericMotionEvent(event)
        }
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        // DEBUG - remove after testing works
        android.util.Log.d("HWButton", "keyCode=${event.keyCode}, action=${event.action}, stem1=${KeyEvent.KEYCODE_STEM_1}")

        // Only handle key down events, ignore repeats
        if (event.action == KeyEvent.ACTION_DOWN && event.repeatCount == 0) {
            val stemNumber = when (event.keyCode) {
                KeyEvent.KEYCODE_STEM_1 -> 1
                KeyEvent.KEYCODE_STEM_2 -> 2
                KeyEvent.KEYCODE_STEM_3 -> 3
                else -> null
            }

            if (stemNumber != null) {
                buttonMethodChannel?.invokeMethod("onStemButton", mapOf("button" to stemNumber))
                return true // Consume the event, prevent system handling
            }
        }
        return super.dispatchKeyEvent(event)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Ongoing activity channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startOngoingActivity" -> {
                    val title = call.argument<String>("title") ?: "Jellyfin Remote"
                    OngoingActivityService.start(this, title)
                    result.success(null)
                }
                "stopOngoingActivity" -> {
                    OngoingActivityService.stop(this)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        // Hardware buttons channel
        buttonMethodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BUTTON_CHANNEL)
    }

}
