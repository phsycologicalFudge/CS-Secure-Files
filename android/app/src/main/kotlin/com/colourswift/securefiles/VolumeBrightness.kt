package com.colourswift.securefiles

import android.content.Context
import android.media.AudioManager
import android.provider.Settings
import androidx.annotation.NonNull
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class VolumeBrightnessPlugin: FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context

    override fun onAttachedToEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "volume_brightness")
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        when (call.method) {
            "getVolume" -> {
                val level = audio.getStreamVolume(AudioManager.STREAM_MUSIC).toFloat() /
                        audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                result.success(level)
            }
            "setVolume" -> {
                val v = (call.argument<Double>("level")!! *
                        audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC)).toInt()
                audio.setStreamVolume(AudioManager.STREAM_MUSIC, v, 0)
                result.success(true)
            }
            "getBrightness" -> {
                val b = Settings.System.getInt(
                    context.contentResolver,
                    Settings.System.SCREEN_BRIGHTNESS, 128
                ) / 255f
                result.success(b)
            }
            "setBrightness" -> {
                val v = ((call.argument<Double>("level")!!).coerceIn(0.0, 1.0) * 255).toInt()
                Settings.System.putInt(
                    context.contentResolver,
                    Settings.System.SCREEN_BRIGHTNESS, v
                )
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }
}
