package com.tabibukenya.tabibu

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

// local_auth shows the system biometric prompt as a fragment, so the host must be a
// FragmentActivity; on a plain FlutterActivity every authenticate() call fails.
class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        HybridAiPlugin.register(flutterEngine, this)
    }
}
