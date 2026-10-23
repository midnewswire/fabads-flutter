package com.fabads.flutter

import android.content.Context
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import com.fabads.AdNetwork
import com.fabads.AdUtils
import com.fabads.BannerSize
import com.fabads.NativeStyle
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

/** Banner and native views for FabBanner / FabNative. Each reports "failed" so Dart tries the next network. */
internal class AdViewFactory(
    private val messenger: BinaryMessenger,
    private val plugin: FabAdsPlugin,
    private val native: Boolean,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        @Suppress("UNCHECKED_CAST")
        val params = args as? Map<String, Any?> ?: emptyMap()
        return AdPlatformView(context, MethodChannel(messenger, "fabads/view_$viewId"), plugin, native, params)
    }
}

private class AdPlatformView(
    context: Context,
    private val channel: MethodChannel,
    plugin: FabAdsPlugin,
    private val native: Boolean,
    params: Map<String, Any?>,
) : PlatformView {
    private val container = FrameLayout(context)
    private val network: AdNetwork? = plugin.networks[params["id"] as? String]
    private var ad: View? = null
    private var disposed = false
    private val failed = AdUtils.onceUnit { if (!disposed) channel.invokeMethod("failed", null) }

    init {
        val activity = plugin.activity
        val network = network
        if (activity == null || network == null) {
            failed()
        } else if (native) {
            val style = runCatching { NativeStyle.valueOf(params["style"] as String) }.getOrDefault(NativeStyle.MEDIUM)
            runCatching {
                network.native(activity, style, params["dark"] == true) { view ->
                    if (view == null || disposed) failed() else show(view, Gravity.TOP, reportHeight = true)
                }
            }.onFailure { failed() }
        } else {
            val size = runCatching { BannerSize.valueOf(params["size"] as String) }.getOrDefault(BannerSize.BANNER)
            val view = runCatching { network.banner(activity, size, failed) }.getOrNull()
            if (view == null) failed() else show(view, Gravity.CENTER, reportHeight = false)
        }
    }

    private fun show(view: View, gravity: Int, reportHeight: Boolean) {
        ad = view
        (view.parent as? ViewGroup)?.removeView(view)
        val width = if (reportHeight) ViewGroup.LayoutParams.MATCH_PARENT else ViewGroup.LayoutParams.WRAP_CONTENT
        container.addView(view, FrameLayout.LayoutParams(width, ViewGroup.LayoutParams.WRAP_CONTENT, gravity))
        if (reportHeight) {
            // Native layouts differ by network and style; tell Dart the height they need at this width.
            container.addOnLayoutChangeListener { _, left, _, right, _, oldLeft, _, oldRight, _ ->
                if (right - left != oldRight - oldLeft) reportHeight(view)
            }
            container.post { reportHeight(view) }
        }
    }

    private fun reportHeight(view: View) {
        if (disposed || container.width == 0) return
        view.measure(
            View.MeasureSpec.makeMeasureSpec(container.width, View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED),
        )
        val density = container.resources.displayMetrics.density
        channel.invokeMethod("height", view.measuredHeight / density.toDouble())
    }

    override fun getView(): View = container

    override fun dispose() {
        disposed = true
        val view = ad ?: return
        val network = network ?: return
        container.removeAllViews()
        runCatching { if (native) network.destroyNative(view) else network.destroyBanner(view) }
    }
}
