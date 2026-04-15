package com.pingblock.pingblock_game

import android.app.Application
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor

/**
 * Custom Application class that pre-warms and caches the Flutter engine.
 *
 * Why this is needed for Solana MWA:
 * The Mobile Wallet Adapter flow opens the wallet app in the foreground.
 * When this happens, Android moves our Flutter activity to the background
 * and may destroy it (especially on debug builds or under memory pressure).
 * By default, the Flutter engine is tied to the activity lifecycle and is
 * destroyed with the activity, which breaks the Dart platform channel callback
 * that `scenario.start()` is waiting on.
 *
 * By caching the engine here (in Application, which outlives any activity),
 * the Dart VM keeps running while the wallet is in the foreground. The
 * `scenario.start()` future resolves, `authorize()` is called, and the MWA
 * handshake completes successfully.
 */
class PingBlockApplication : Application() {

    companion object {
        /** Key used to retrieve the cached engine from [FlutterEngineCache]. */
        const val ENGINE_ID = "pingblock_mwa_engine"
    }

    override fun onCreate() {
        super.onCreate()

        // Pre-warm the Flutter engine.
        // executeDartEntrypoint starts the Dart isolate immediately so the
        // first frame renders without a cold-start delay.
        val engine = FlutterEngine(this)
        engine.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint.createDefault()
        )
        FlutterEngineCache.getInstance().put(ENGINE_ID, engine)
    }
}
