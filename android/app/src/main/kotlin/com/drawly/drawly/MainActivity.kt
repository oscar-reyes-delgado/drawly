package com.drawly.drawly

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var video: VideoEncoderChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        video = VideoEncoderChannel(flutterEngine.dartExecutor.binaryMessenger)
    }
}
