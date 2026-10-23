package com.fabads.flutter

import android.app.Activity
import android.content.Context
import com.fabads.AdEnvironment
import com.fabads.AdFormat
import com.fabads.AdNetwork
import com.fabads.AdUtils
import com.fabads.FabAds
import com.fabads.NetworkConfig
import com.fabads.NetworkIds
import com.fabads.Privacy
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

/**
 * The Android side of fab_ads. It runs Google's consent form and every network module of the Kotlin SDK
 * (fabads-kotlin) that the app's fab_ads_<network> packages added, so Flutter apps get the same networks.
 */
class FabAdsPlugin : FlutterPlugin, ActivityAware, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    internal var activity: Activity? = null
        private set
    internal val networks = mutableMapOf<String, AdNetwork>()

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "fabads")
        channel.setMethodCallHandler(this)
        val registry = binding.platformViewRegistry
        registry.registerViewFactory("fabads/banner", AdViewFactory(binding.binaryMessenger, this, native = false))
        registry.registerViewFactory("fabads/native", AdViewFactory(binding.binaryMessenger, this, native = true))
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) { activity = binding.activity }
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) { activity = binding.activity }
    override fun onDetachedFromActivityForConfigChanges() { activity = null }
    override fun onDetachedFromActivity() { activity = null }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val reply = AdUtils.once<Any?> { result.success(it) }
        when (call.method) {
            "installed" -> reply(NetworkIds.all.filter { FabAds.provider(it) != null })
            "privacy" -> reply(FabAds.savedPrivacy(context).toMap())
            "consent" -> {
                FabAds.debug = call.argument<Boolean>("debug") ?: false
                val activity = activity ?: return reply(FabAds.savedPrivacy(context).toMap())
                FabAds.requestConsent(activity) { reply(it.toMap()) }
            }
            "privacyOptionsRequired" -> reply(activity?.let { FabAds.privacyOptionsRequired(it) } ?: false)
            "showPrivacyOptions" -> activity?.let { FabAds.showPrivacyOptions(it) { reply(null) } } ?: reply(null)
            "create" -> reply(create(call))
            else -> {
                val network = networks[call.argument<String>("id")]
                val activity = activity
                if (network == null || activity == null) return reply(null)
                runCatching { run(call.method, network, activity, reply) }.onFailure {
                    AdUtils.log(network.id, "${call.method}: ${it.message}")
                    reply(null)
                }
            }
        }
    }

    /** Starts network `id` and returns the formats it can serve, or null when it cannot run in this app. */
    private fun create(call: MethodCall): List<String>? {
        val id = NetworkIds.normalize(call.argument<String>("id").orEmpty())
        val provider = FabAds.provider(id) ?: return null
        FabAds.debug = call.argument<Boolean>("debug") ?: false
        val config = NetworkConfig(id, JSONObject(call.argument<Map<String, Any?>>("config") ?: emptyMap<String, Any?>()))
        val privacy = call.argument<Map<String, Any?>>("privacy").orEmpty()
        val env = AdEnvironment(
            testMode = call.argument<Boolean>("testMode") ?: false,
            debug = FabAds.debug,
            privacy = Privacy(
                gdprApplies = privacy["gdprApplies"] == true,
                consent = privacy["consent"] != false,
                doNotSell = privacy["doNotSell"] == true,
                childDirected = privacy["childDirected"] == true,
            ),
        )
        val network = runCatching { provider.create(context, config, env) }
            .onFailure { AdUtils.log(id, "could not start: ${it.message}") }
            .getOrNull() ?: return null
        networks[id] = network
        return AdFormat.entries.filter { network.supports(it) }.map { it.name }
    }

    private fun run(method: String, network: AdNetwork, activity: Activity, reply: (Any?) -> Unit) {
        when (method) {
            "init" -> network.init(activity) { reply(null) }
            "loadInterstitial" -> { network.loadInterstitial(activity); reply(null) }
            "showInterstitial" -> if (!network.showInterstitial(activity) { reply(true) }) reply(false)
            "showRewarded" -> network.showRewarded(activity) { reply(it) }
            "loadAppOpen" -> {
                network.loadAppOpen(activity) { AdUtils.onMain { channel.invokeMethod("appOpenLoaded", network.id) } }
                reply(null)
            }
            "showAppOpen" -> if (!network.showAppOpen(activity) { reply(true) }) reply(false)
            else -> reply(null)
        }
    }

    private fun Privacy.toMap() = mapOf(
        "gdprApplies" to gdprApplies,
        "consent" to consent,
        "doNotSell" to doNotSell,
        "childDirected" to childDirected,
    )
}
