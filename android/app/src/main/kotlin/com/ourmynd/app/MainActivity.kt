package com.ourmynd.app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.TimeZone

class MainActivity : FlutterActivity() {
    // The real IANA zone, e.g. "Europe/London" or "Asia/Kathmandu".
    //
    // Dart cannot read this, and the scan NotificationService used instead
    // picked the first tz-database zone whose CURRENT offset matched - which on
    // a +01:00 device is Africa/Algiers, one of 24 candidates and the wrong DST
    // rules. Android tolerated the resulting drift; iOS drops a trigger that
    // lands in the past, so only iPhone looked broken.
    //
    // flutter_timezone would have done this, but its Kotlin compiles at
    // jvmTarget 1.8 while its Java lands on 11 and Gradle refuses the mix. Two
    // dozen lines here avoid that fight entirely.
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.ourmynd.app/timezone",
        ).setMethodCallHandler { call, result ->
            if (call.method == "localTimeZone") {
                result.success(TimeZone.getDefault().id)
            } else {
                result.notImplemented()
            }
        }
    }
}
