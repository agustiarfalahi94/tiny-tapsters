package com.inkpebble.tiny_tapsters

import android.content.Context
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Keep the screen on while the app is in front.
        //
        // A toddler looking at a jigsaw touches nothing for a minute at a
        // time, and the phone locking mid-game ends it — the clock pauses, the
        // music stops, and a four-year-old cannot get back in. The flag is
        // tied to this window, so it lifts by itself the moment the app is
        // backgrounded; there is no wake lock to leak and no permission
        // needed. Done here rather than with a package because it is one line.
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }

    /**
     * A one-string preference store, used only for the chosen language.
     *
     * A package would work too, but this app writes nothing else to the
     * device and adding a dependency to hold a single word is a poor trade.
     * Nothing here is written unless the language is actually changed.
     */
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.inkpebble.tiny_tapsters/prefs",
        ).setMethodCallHandler { call, result ->
            val prefs = getSharedPreferences("tiny_tapsters", Context.MODE_PRIVATE)
            when (call.method) {
                "get" -> result.success(prefs.getString(call.argument<String>("key"), null))
                "set" -> {
                    prefs.edit()
                        .putString(call.argument<String>("key"), call.argument<String>("value"))
                        .apply()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
}
