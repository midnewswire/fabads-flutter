package com.fabads.flutter.meta

import io.flutter.embedding.engine.plugins.FlutterPlugin

/** Adds the fabads-kotlin meta module to the app. fab_ads runs it; this class only makes Flutter link the package. */
class FabMetaPlugin : FlutterPlugin {
    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {}
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {}
}
