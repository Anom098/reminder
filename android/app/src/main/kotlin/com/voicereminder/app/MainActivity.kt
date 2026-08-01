package com.voicereminder.app

import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

/**
 * Single-activity host for the Flutter engine.
 *
 * The activity is declared with `showWhenLocked` / `turnScreenOn` in the
 * manifest so that a full-screen reminder can surface above the lock screen.
 * All reminder scheduling and speech work happens in Dart; this class exists
 * only to own the engine lifecycle.
 */
class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
    }
}
