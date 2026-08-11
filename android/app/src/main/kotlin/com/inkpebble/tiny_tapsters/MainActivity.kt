package com.inkpebble.tiny_tapsters

import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity

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
}
