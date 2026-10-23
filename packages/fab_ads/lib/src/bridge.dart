import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'config.dart';
import 'fab_ads.dart';
import 'network.dart';

/// The channel to the Kotlin SDK (fabads-kotlin) on Android. It runs Google's consent form and every network
/// that has no Flutter plugin of its own.
abstract final class Bridge {
  static const _channel = MethodChannel('fabads');
  static final _appOpenLoaded = <String, VoidCallback>{};
  static bool _listening = false;

  static bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<T?> call<T>(String method, [Map<String, Object?>? args]) {
    if (!_listening) {
      _listening = true;
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'appOpenLoaded') _appOpenLoaded[call.arguments as String]?.call();
      });
    }
    return _channel.invokeMethod<T>(method, args);
  }
}

/// A network that runs through the Kotlin SDK. Android only: on other platforms it never starts.
///
/// Each `fab_ads_<network>` package that has no Flutter plugin of its own exposes one of these, and adds the
/// matching fabads-kotlin module to the Android build.
class FabBridgeNetwork extends FabNetwork {
  const FabBridgeNetwork(this.id);

  @override
  final String id;

  @override
  Future<FabAdNetwork?> create(NetworkConfig config, AdEnvironment env) async {
    if (!Bridge.supported) return null;
    final formats = await Bridge.call<List>('create', {
      'id': id,
      'config': config.json,
      'testMode': env.testMode,
      'debug': env.debug,
      'privacy': env.privacy.toMap(),
    });
    if (formats == null) {
      FabAds.log(id, 'not started: its app id or key is missing, or its module is not in the Android build');
      return null;
    }
    return _BridgeAdNetwork(id, {
      for (final f in formats)
        for (final format in AdFormat.values)
          if (format.name.toLowerCase() == '$f'.replaceAll('_', '').toLowerCase()) format,
    });
  }
}

class _BridgeAdNetwork extends FabAdNetwork {
  _BridgeAdNetwork(this.id, this.formats);

  @override
  final String id;
  final Set<AdFormat> formats;

  Map<String, Object?> get _args => {'id': id};

  @override
  bool supports(AdFormat format) => formats.contains(format);

  @override
  Future<void> init() => Bridge.call<void>('init', _args);

  @override
  void loadInterstitial() => Bridge.call<void>('loadInterstitial', _args);

  @override
  Future<bool> showInterstitial() async => await Bridge.call<bool>('showInterstitial', _args) ?? false;

  @override
  Future<bool?> showRewarded() => Bridge.call<bool>('showRewarded', _args);

  @override
  void loadAppOpen(VoidCallback onLoaded) {
    Bridge._appOpenLoaded[id] = onLoaded;
    Bridge.call<void>('loadAppOpen', _args);
  }

  @override
  Future<bool> showAppOpen() async => await Bridge.call<bool>('showAppOpen', _args) ?? false;

  @override
  Widget? banner(FabBannerSize size, {required VoidCallback onFailed}) {
    if (!supports(size == FabBannerSize.mrec ? AdFormat.mrec : AdFormat.banner)) return null;
    return _BridgeView(
      viewType: 'fabads/banner',
      params: {'id': id, 'size': size.name.toUpperCase()},
      height: size.height.toDouble(),
      onFailed: onFailed,
    );
  }

  @override
  Widget? native(NativeStyle style, {required bool dark, required VoidCallback onFailed}) {
    if (!supports(AdFormat.native)) return null;
    return _BridgeView(
      viewType: 'fabads/native',
      params: {'id': id, 'style': style.name.toUpperCase(), 'dark': dark},
      height: _nativeHeights[style]!,
      onFailed: onFailed,
    );
  }

  /// First guesses; the native view reports its real height once laid out.
  static const _nativeHeights = {
    NativeStyle.small: 96.0,
    NativeStyle.medium: 330.0,
    NativeStyle.large: 410.0,
    NativeStyle.news: 330.0,
    NativeStyle.radio: 96.0,
    NativeStyle.video: 330.0,
  };
}

/// An Android view from the Kotlin SDK, shown with hybrid composition so ad clicks and video work.
class _BridgeView extends StatefulWidget {
  const _BridgeView({required this.viewType, required this.params, required this.height, required this.onFailed});

  final String viewType;
  final Map<String, Object?> params;
  final double height;
  final VoidCallback onFailed;

  @override
  State<_BridgeView> createState() => _BridgeViewState();
}

class _BridgeViewState extends State<_BridgeView> {
  late double _height = widget.height;
  MethodChannel? _channel;

  void _created(int id) {
    _channel = MethodChannel('fabads/view_$id')
      ..setMethodCallHandler((call) async {
        if (!mounted) return;
        switch (call.method) {
          case 'failed':
            widget.onFailed();
          case 'height':
            final height = (call.arguments as num).toDouble();
            if (height > 0 && height != _height) setState(() => _height = height);
        }
      });
  }

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _height,
      child: PlatformViewLink(
        viewType: widget.viewType,
        surfaceFactory: (context, controller) => AndroidViewSurface(
          controller: controller as AndroidViewController,
          gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
          hitTestBehavior: PlatformViewHitTestBehavior.opaque,
        ),
        onCreatePlatformView: (params) => PlatformViewsService.initExpensiveAndroidView(
          id: params.id,
          viewType: widget.viewType,
          layoutDirection: Directionality.maybeOf(context) ?? TextDirection.ltr,
          creationParams: widget.params,
          creationParamsCodec: const StandardMessageCodec(),
          onFocus: () => params.onFocusChanged(true),
        )
          ..addOnPlatformViewCreatedListener(params.onPlatformViewCreated)
          ..addOnPlatformViewCreatedListener(_created)
          ..create(),
      ),
    );
  }
}
