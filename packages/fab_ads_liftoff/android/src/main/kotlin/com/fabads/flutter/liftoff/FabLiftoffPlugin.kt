package com.fabads.flutter.liftoff

import io.flutter.embedding.engine.plugins.FlutterPlugin

/** Adds the fabads-kotlin liftoff module to the app. fab_ads runs it; this class only makes Flutter link the package. */
class FabLiftoffPlugin : FlutterPlugin {
    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {}
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {}
}
