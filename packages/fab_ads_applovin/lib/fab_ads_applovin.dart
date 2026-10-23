import 'dart:async';

import 'package:applovin_max/applovin_max.dart' as max;
import 'package:fab_ads/fab_ads.dart';
import 'package:flutter/widgets.dart';

/// AppLovin MAX, on Android and iOS: banner, medium rectangle, interstitial, rewarded and app open.
/// Needs `sdk_key` in the admin's applovin settings. Units are MAX ad unit ids.
class FabAppLovin extends FabNetwork {
  const FabAppLovin();

  @override
  String get id => NetworkIds.applovin;

  @override
  Future<FabAdNetwork?> create(NetworkConfig config, AdEnvironment env) async {
    final sdkKey = config.string('sdk_key');
    if (sdkKey.isEmpty) {
      FabAds.log(id, 'no sdk_key; skipped');
      return null;
    }
    return _AppLovinNetwork(config, env, sdkKey);
  }
}

class _AppLovinNetwork extends FabAdNetwork {
  _AppLovinNetwork(this.config, this.env, this.sdkKey);

  final NetworkConfig config;
  final AdEnvironment env;
  final String sdkKey;

  // MAX has one listener per format for the whole app, so each format keeps the callback of the ad showing now.
  bool _interstitialReady = false;
  bool _appOpenReady = false;
  Completer<bool>? _interstitialClosed;
  Completer<bool>? _appOpenClosed;
  Completer<bool?>? _rewardedResult;
  bool _earned = false;
  VoidCallback? _onAppOpenLoaded;

  @override
  String get id => NetworkIds.applovin;

  @override
  bool supports(AdFormat format) => switch (format) {
        AdFormat.banner => config.banner.isNotEmpty,
        AdFormat.mrec => config.mrec.isNotEmpty,
        AdFormat.interstitial => config.interstitial.isNotEmpty,
        AdFormat.rewarded => config.rewarded.isNotEmpty,
        AdFormat.appOpen => config.appOpen.isNotEmpty,
        AdFormat.native => false,
      };

  @override
  Future<void> init() async {
    max.AppLovinMAX.setHasUserConsent(env.privacy.consent);
    max.AppLovinMAX.setDoNotSell(env.privacy.doNotSell);
    max.AppLovinMAX.setVerboseLogging(env.debug);
    _listen();
    await max.AppLovinMAX.initialize(sdkKey);
  }

  void _listen() {
    void done<T>(Completer<T>? completer, T value) {
      if (completer != null && !completer.isCompleted) completer.complete(value);
    }

    max.AppLovinMAX.setInterstitialListener(max.InterstitialListener(
      onAdLoadedCallback: (_) => _interstitialReady = true,
      onAdLoadFailedCallback: (_, error) => FabAds.log(id, 'interstitial: ${error.message}'),
      onAdDisplayedCallback: (_) {},
      onAdDisplayFailedCallback: (_, __) => done(_interstitialClosed, true),
      onAdClickedCallback: (_) {},
      onAdHiddenCallback: (_) => done(_interstitialClosed, true),
    ));
    max.AppLovinMAX.setRewardedAdListener(max.RewardedAdListener(
      onAdLoadedCallback: (_) {
        if (_rewardedResult != null) max.AppLovinMAX.showRewardedAd(config.rewarded);
      },
      onAdLoadFailedCallback: (_, error) {
        FabAds.log(id, 'rewarded: ${error.message}');
        done(_rewardedResult, null);
      },
      onAdDisplayedCallback: (_) {},
      onAdDisplayFailedCallback: (_, __) => done(_rewardedResult, null),
      onAdClickedCallback: (_) {},
      onAdHiddenCallback: (_) => done(_rewardedResult, _earned),
      onAdReceivedRewardCallback: (_, __) => _earned = true,
    ));
    max.AppLovinMAX.setAppOpenAdListener(max.AppOpenAdListener(
      onAdLoadedCallback: (_) {
        _appOpenReady = true;
        _onAppOpenLoaded?.call();
      },
      onAdLoadFailedCallback: (_, error) => FabAds.log(id, 'app open: ${error.message}'),
      onAdDisplayedCallback: (_) {},
      onAdDisplayFailedCallback: (_, __) => done(_appOpenClosed, true),
      onAdClickedCallback: (_) {},
      onAdHiddenCallback: (_) => done(_appOpenClosed, true),
    ));
  }

  @override
  void loadInterstitial() {
    if (!_interstitialReady && supports(AdFormat.interstitial)) max.AppLovinMAX.loadInterstitial(config.interstitial);
  }

  @override
  Future<bool> showInterstitial() async {
    if (!_interstitialReady || await max.AppLovinMAX.isInterstitialReady(config.interstitial) != true) return false;
    _interstitialReady = false;
    final closed = _interstitialClosed = Completer<bool>();
    max.AppLovinMAX.showInterstitial(config.interstitial);
    return closed.future;
  }

  @override
  Future<bool?> showRewarded() async {
    if (!supports(AdFormat.rewarded)) return null;
    _earned = false;
    final result = _rewardedResult = Completer<bool?>();
    if (await max.AppLovinMAX.isRewardedAdReady(config.rewarded) == true) {
      max.AppLovinMAX.showRewardedAd(config.rewarded);
    } else {
      max.AppLovinMAX.loadRewardedAd(config.rewarded);
    }
    final earned = await result.future;
    _rewardedResult = null;
    return earned;
  }

  @override
  void loadAppOpen(VoidCallback onLoaded) {
    if (!supports(AdFormat.appOpen)) return;
    _onAppOpenLoaded = onLoaded;
    if (_appOpenReady) return onLoaded();
    max.AppLovinMAX.loadAppOpenAd(config.appOpen);
  }

  @override
  Future<bool> showAppOpen() async {
    if (!_appOpenReady || await max.AppLovinMAX.isAppOpenAdReady(config.appOpen) != true) return false;
    _appOpenReady = false;
    final closed = _appOpenClosed = Completer<bool>();
    max.AppLovinMAX.showAppOpenAd(config.appOpen);
    return closed.future;
  }

  @override
  Widget? banner(FabBannerSize size, {required VoidCallback onFailed}) {
    final mrec = size == FabBannerSize.mrec;
    final unit = mrec ? config.mrec : config.banner;
    if (unit.isEmpty) return null;
    return max.MaxAdView(
      key: ValueKey(unit),
      adUnitId: unit,
      adFormat: mrec ? max.AdFormat.mrec : max.AdFormat.banner,
      isAdaptiveBannerEnabled: false,
      listener: max.AdViewAdListener(
        onAdLoadedCallback: (_) {},
        onAdLoadFailedCallback: (_, error) {
          FabAds.log(id, 'banner: ${error.message}');
          onFailed();
        },
        onAdClickedCallback: (_) {},
        onAdExpandedCallback: (_) {},
        onAdCollapsedCallback: (_) {},
      ),
    );
  }
}
