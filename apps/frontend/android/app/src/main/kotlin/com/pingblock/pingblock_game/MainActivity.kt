package com.pingblock.pingblock_game

import io.flutter.embedding.android.FlutterActivity

/**
 * Uses the engine pre-warmed by [PingBlockApplication] instead of creating
 * a new one. This keeps the Dart VM alive during Solana MWA flows where the
 * wallet app temporarily takes over the foreground.
 *
 * With a cached engine, `shouldDestroyEngineWithHost()` automatically returns
 * `false`, so Android's activity lifecycle cannot destroy the Flutter engine.
 */
class MainActivity : FlutterActivity() {
    override fun getCachedEngineId(): String = PingBlockApplication.ENGINE_ID
}
