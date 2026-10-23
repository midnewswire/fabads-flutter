import 'dart:async';

import 'package:flutter/widgets.dart';

import 'bridge.dart';
import 'config.dart';
import 'network.dart';

/// The one entry point apps use. Call [start] once with the admin's [AdsConfig] and the networks the app ships,
/// then use [FabBanner] / [FabNative], [interstitial] and [rewarded].
///
/// Only networks passed to [start] exist here. Networks the admin turns on but the app does not include are
/// skipped, and the next network in the admin's order is used.
abstract final class FabAds {
  /// Logs every network's load results and forces test ads.
  static bool debug = false;

  static AdsConfig _config = AdsConfig.disabled;
  static AdsConfig get config => _config;

  static Map<String, FabNetwork> _installed = const {};
  static List<FabAdNetwork> _networks = const [];
  static final _changes = ValueNotifier<int>(0);
  static bool _noAds = false;
  static bool _started = false;
  static DateTime _startedAt = DateTime.now();
  static int _actions = 0;
  static DateTime? _lastInterstitialAt;
  static DateTime? _lastFullScreenAt;
  static bool _fullScreen = false;
  static bool _coldStartAppOpenDone = false;
  static AppLifecycleListener? _lifecycle;

  static const _coldStartWindow = Duration(seconds: 8);

  /// Notifies when ads turn on or off or a network finishes starting. The ad widgets rebuild on it.
  static Listenable get changes => _changes;

  /// Premium / "remove ads" users: turns every ad off except [rewarded].
  static bool get noAds => _noAds;
  static set noAds(bool value) {
    if (_noAds == value) return;
    _noAds = value;
    _changes.value++;
  }

  /// Networks the app was built with.
  static List<String> get installedNetworks => _installed.keys.toList()..sort();

  /// Networks that are running now, in the admin's order.
  static List<String> get activeNetworks => [for (final n in _networks) n.id];

  static bool get enabled => _config.enabled && !_noAds && _networks.isNotEmpty;

  /// Items between two native ads in lists; 0 when native ads are off.
  static int get nativeEvery => enabled && _config.placement('native') ? _config.nativeEvery : 0;

  /// True when the placement named [name] should show an ad.
  static bool placement(String name) => enabled && _config.placement(name);

  static void log(String network, Object? message) {
    if (debug) debugPrint('FabAds [$network] $message');
  }

  /// Asks for consent where needed, then starts the networks in [config] that are in [networks]. Completes once
  /// every network has started. Use it once per app run.
  static Future<void> start(AdsConfig config, {required List<FabNetwork> networks, bool debug = false}) async {
    _config = config;
    FabAds.debug = debug;
    if (_started) return;
    _started = true;
    _startedAt = DateTime.now();
    _installed = {for (final n in networks) NetworkIds.normalize(n.id): n};
    _lifecycle = AppLifecycleListener(onShow: _onShow);
    if (!config.enabled && !config.rewarded) return;

    for (final id in config.networks.where((id) => !_installed.containsKey(id))) {
      log(id, 'turned on in the admin but not built into this app; skipped');
    }
    final privacy = await _consent(config);
    final env = AdEnvironment(
      testMode: config.testMode || debug,
      debug: debug,
      privacy: privacy.copyWith(childDirected: config.childDirected),
    );
    final created = <FabAdNetwork>[];
    for (final id in config.networks) {
      final network = _installed[id];
      if (network == null) continue;
      try {
        final ad = await network.create(config.network(id), env);
        if (ad != null) created.add(ad);
      } catch (e) {
        log(id, 'could not start: $e');
      }
    }
    _networks = created;
    _changes.value++;
    await Future.wait(created.map((network) async {
      try {
        await network.init().timeout(const Duration(seconds: 20));
      } catch (e) {
        log(network.id, 'init failed: $e');
      }
      _changes.value++;
      if (config.enabled && !_noAds) {
        if (config.interstitialEvery > 0) network.loadInterstitial();
        if (config.appOpen || config.appOpenOnResume) _loadAppOpen(network);
      }
    }));
  }

  /// Call on each action that may show an interstitial (opening an item, changing screens). An ad shows on every
  /// Nth call, at most once per `min_seconds`. Completes when the ad closes, or right away when none showed:
  /// navigate after it so the app never waits on an ad.
  static Future<void> interstitial({String? placement}) async {
    final every = _config.interstitialEvery;
    if (!enabled || every <= 0 || (placement != null && !_config.placement(placement))) return;
    _actions++;
    final last = _lastInterstitialAt;
    final tooSoon = last != null && DateTime.now().difference(last).inSeconds < _config.interstitialMinSeconds;
    if (_actions % every != 0 || tooSoon) return;
    await showInterstitialNow();
  }

  /// Shows an interstitial now if one is loaded, ignoring the frequency settings. True when one showed.
  static Future<bool> showInterstitialNow() async {
    if (!enabled || _fullScreen) return false;
    _fullScreen = true;
    try {
      for (final network in _networks.where((n) => n.supports(AdFormat.interstitial))) {
        if (await _safe(network.showInterstitial(), false)) {
          _lastInterstitialAt = DateTime.now();
          network.loadInterstitial();
          return true;
        }
      }
      for (final network in _networks) {
        network.loadInterstitial();
      }
      return false;
    } finally {
      _closedFullScreen();
    }
  }

  /// True when the admin turned rewarded ads on and a network can serve them.
  static bool get rewardedAvailable => _config.rewarded && _networks.any((n) => n.supports(AdFormat.rewarded));

  /// Loads and shows a rewarded ad, trying each network in order. True when the reward was earned.
  static Future<bool> rewarded() async {
    if (!_config.rewarded || _fullScreen) return false;
    _fullScreen = true;
    try {
      for (final network in _networks.where((n) => n.supports(AdFormat.rewarded))) {
        final earned = await _safe<bool?>(network.showRewarded(), null);
        if (earned != null) return earned;
      }
      return false;
    } finally {
      _closedFullScreen();
    }
  }

  /// Whether the app should show a "Privacy settings" item (users in the EEA, UK and some US states).
  static Future<bool> privacyOptionsRequired() async {
    for (final network in _installed.values) {
      final required = await _safe(network.privacyOptionsRequired(), null);
      if (required != null) return required;
    }
    return Bridge.supported && await Bridge.call<bool>('privacyOptionsRequired') == true;
  }

  /// Opens Google's consent form again so the user can change their choices.
  static Future<void> showPrivacyOptions() async {
    for (final network in _installed.values) {
      if (await _safe(network.showPrivacyOptions(), false)) return;
    }
    if (Bridge.supported) await Bridge.call<void>('showPrivacyOptions');
  }

  /// Networks with a unit for [size], in order. Used by [FabBanner].
  static List<FabAdNetwork> bannerNetworks(FabBannerSize size) {
    final format = size == FabBannerSize.mrec ? AdFormat.mrec : AdFormat.banner;
    return [for (final n in _networks) if (n.supports(format)) n];
  }

  /// Networks with a native unit, in order. Used by [FabNative].
  static List<FabAdNetwork> nativeNetworks() => [for (final n in _networks) if (n.supports(AdFormat.native)) n];

  static Future<Privacy> _consent(AdsConfig config) async {
    if (config.consentForm) {
      for (final network in _installed.values) {
        final privacy = await _safe(network.requestConsent(debug: debug), null);
        // The form saves its answers as IAB strings; on Android the bridge reads them in full.
        if (privacy != null) return Bridge.supported ? await _savedPrivacy() : privacy;
      }
      if (Bridge.supported) return Privacy.fromMap(await Bridge.call<Map>('consent', {'debug': debug}));
    }
    return _savedPrivacy();
  }

  static Future<Privacy> _savedPrivacy() async =>
      Bridge.supported ? Privacy.fromMap(await Bridge.call<Map>('privacy')) : const Privacy();

  static void _loadAppOpen(FabAdNetwork network) {
    if (!network.supports(AdFormat.appOpen)) return;
    network.loadAppOpen(() {
      // Cold start: show the first app open ad that loads within a few seconds of launch.
      final fresh = DateTime.now().difference(_startedAt) < _coldStartWindow;
      if (_config.appOpen && !_coldStartAppOpenDone && fresh) {
        _coldStartAppOpenDone = true;
        _showAppOpen();
      }
    });
  }

  static Future<void> _showAppOpen() async {
    if (!enabled || _fullScreen) return;
    _fullScreen = true;
    try {
      for (final network in _networks.where((n) => n.supports(AdFormat.appOpen))) {
        if (await _safe(network.showAppOpen(), false)) {
          _loadAppOpen(network);
          return;
        }
      }
    } finally {
      _closedFullScreen();
    }
  }

  static void _closedFullScreen() {
    _fullScreen = false;
    _lastFullScreenAt = DateTime.now();
  }

  static void _onShow() {
    // Full screen ads hide the app too; coming back from one must not trigger another ad.
    final last = _lastFullScreenAt;
    final fromAd = _fullScreen || (last != null && DateTime.now().difference(last) < const Duration(seconds: 2));
    if (_config.appOpenOnResume && !fromAd) _showAppOpen();
  }

  static Future<T> _safe<T>(Future<T> future, T fallback) async {
    try {
      return await future;
    } catch (e) {
      log('fabads', e);
      return fallback;
    }
  }

  /// Stops listening to the app's lifecycle. For tests.
  @visibleForTesting
  static void reset() {
    _lifecycle?.dispose();
    _lifecycle = null;
    _started = false;
    _networks = const [];
    _installed = const {};
    _config = AdsConfig.disabled;
    _actions = 0;
    _lastInterstitialAt = null;
    _noAds = false;
    _coldStartAppOpenDone = false;
  }

  @visibleForTesting
  static void useNetworks(AdsConfig config, List<FabAdNetwork> networks) {
    _config = config;
    _networks = networks;
    _changes.value++;
  }
}
