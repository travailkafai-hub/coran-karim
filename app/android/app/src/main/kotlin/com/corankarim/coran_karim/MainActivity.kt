package com.corankarim.coran_karim

import com.corankarim.coran_karim.fastconformer.FastConformerCtcPlugin
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.plugins.add(FastConformerCtcPlugin())
    }
}
