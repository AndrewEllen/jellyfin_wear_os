package com.jellywear.jellyfin_wear_os

import android.os.Bundle
import android.view.KeyEvent
import android.view.MotionEvent
import androidx.wear.ambient.AmbientModeSupport
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.samsung.wearable_rotary.WearableRotaryPlugin

class MainActivity: FlutterFragmentActivity(), AmbientModeSupport.AmbientCallbackProvider {
    private val CHANNEL = "com.jellywear.jellyfin_wear_os/ongoing_activity"
    private val BUTTON_CHANNEL = "com.jellywear.jellyfin_wear_os/hardware_buttons"

    private var buttonMethodChannel: MethodChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        AmbientModeSupport.attach(this)
    }

    override fun onGenericMotionEvent(event: MotionEvent?): Boolean {
        return when {
            WearableRotaryPlugin.onGenericMotionEvent(event) -> true
            else -> super.onGenericMotionEvent(event)
        }
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        return when (keyCode) {
            KeyEvent.KEYCODE_STEM_1 -> {
                buttonMethodChannel?.invokeMethod("onStemButton", mapOf("button" to 1))
                true
            }
            KeyEvent.KEYCODE_STEM_2 -> {
                buttonMethodChannel?.invokeMethod("onStemButton", mapOf("button" to 2))
                true
            }
            KeyEvent.KEYCODE_STEM_3 -> {
                buttonMethodChannel?.invokeMethod("onStemButton", mapOf("button" to 3))
                true
            }
            else -> super.onKeyDown(keyCode, event)
        }
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

    override fun getAmbientCallback(): AmbientModeSupport.AmbientCallback {
        return object : AmbientModeSupport.AmbientCallback() {
            override fun onEnterAmbient(ambientDetails: Bundle?) {
                // App enters ambient mode - screen dims but app stays active
            }

            override fun onExitAmbient() {
                // App exits ambient mode - screen returns to normal
            }

            override fun onUpdateAmbient() {
                // Called periodically in ambient mode for updates
            }
        }
    }
}
