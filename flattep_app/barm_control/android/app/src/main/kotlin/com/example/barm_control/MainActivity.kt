package com.example.barm_control

import android.view.KeyEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val VOLUME_CHANNEL = "com.barm.control/volume"
    private val VOLUME_EVENT_CHANNEL = "com.barm.control/volume_events"
    
    private var volumeButtonsEnabled = false
    private var eventSink: EventChannel.EventSink? = null
    
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // Method channel for enable/disable
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, VOLUME_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "enableVolumeButtons" -> {
                    volumeButtonsEnabled = true
                    result.success(true)
                }
                "disableVolumeButtons" -> {
                    volumeButtonsEnabled = false
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
        
        // Event channel for volume button events
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, VOLUME_EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                }
                
                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            }
        )
    }
    
    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        if (volumeButtonsEnabled) {
            when (keyCode) {
                KeyEvent.KEYCODE_VOLUME_UP -> {
                    eventSink?.success("up")
                    return true
                }
                KeyEvent.KEYCODE_VOLUME_DOWN -> {
                    eventSink?.success("down")
                    return true
                }
            }
        }
        return super.onKeyDown(keyCode, event)
    }
}
