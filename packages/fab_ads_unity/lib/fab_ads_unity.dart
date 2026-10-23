import 'dart:async';

import 'package:fab_ads/fab_ads.dart';
import 'package:flutter/widgets.dart';
import 'package:unity_ads_plugin/unity_ads_plugin.dart' as unity;

/// Apps import only their network packages; each one brings the whole FabAds API.
export 'package:fab_ads/fab_ads.dart';

/// Unity Ads, on Android and iOS: banner, medium rectangle, interstitial and rewarded video.
/// Needs `game_id` in the admin's unity settings (the Android or iOS game id). Units are Unity placement ids.
class FabUnity extends FabNetwork {
  const FabUnity();

  @override
  String get id => NetworkIds.unity;

  @override
  Future<FabAdNetwork?> create(NetworkConfig config, AdEnvironment env) async {
    final gameId = config.string('game_id');
    if (gameId.isEmpty) {
      FabAds.log(id, 'no game_id; skipped');
      return null;
    }
    return _UnityNetwork(config, env, gameId);
  }
}

class _UnityNetwork extends FabAdNetwork {
  _UnityNetwork(this.config, this.env, this.gameId);

  final NetworkConfig config;
  final AdEnvironment env;
  final String gameId;
  bool _interstitialReady = false;
  bool _interstitialLoading = false;

  @override
  String get id => NetworkIds.unity;

  @override
  bool supports(AdFormat format) => switch (format) {
        AdFormat.banner => config.banner.isNotEmpty,
        AdFormat.mrec => config.mrec.isNotEmpty,
        AdFormat.interstitial => config.interstitial.isNotEmpty,
        AdFormat.rewarded => config.rewarded.isNotEmpty,
        AdFormat.native || AdFormat.appOpen => false,
      };

  @override
  Future<void> init() async {
    final privacy = env.privacy;
    if (privacy.gdprApplies) await unity.UnityAds.setPrivacyConsent(unity.PrivacyConsentType.gdpr, privacy.consent);
    await unity.UnityAds.setPrivacyConsent(unity.PrivacyConsentType.ccpa, !privacy.doNotSell);
    if (privacy.childDirected) await unity.UnityAds.setPrivacyConsent(unity.PrivacyConsentType.ageGate, false);
    final done = Completer<void>();
    await unity.UnityAds.init(
      gameId: gameId,
      testMode: env.testMode || config.boolean('test_mode'),
      onComplete: () => done.complete(),
      onFailed: (error, message) {
        FabAds.log(id, 'init: $message');
        done.complete();
      },
    );
    return done.future;
  }

  @override
  void loadInterstitial() {
    if (_interstitialReady || _interstitialLoading || !supports(AdFormat.interstitial)) return;
    _interstitialLoading = true;
    unity.UnityAds.load(
      placementId: config.interstitial,
      onComplete: (_) {
        _interstitialLoading = false;
        _interstitialReady = true;
      },
      onFailed: (_, error, message) {
        _interstitialLoading = false;
        FabAds.log(id, 'interstitial: $message');
      },
    );
  }

  @override
  Future<bool> showInterstitial() async {
    if (!_interstitialReady) return false;
    _interstitialReady = false;
    return await _show(config.interstitial) != null;
  }

  @override
  Future<bool?> showRewarded() async {
    if (!supports(AdFormat.rewarded)) return null;
    final loaded = Completer<bool>();
    await unity.UnityAds.load(
      placementId: config.rewarded,
      onComplete: (_) => loaded.complete(true),
      onFailed: (_, error, message) {
        FabAds.log(id, 'rewarded: $message');
        loaded.complete(false);
      },
    );
    return await loaded.future ? _show(config.rewarded) : null;
  }

  /// True when watched to the end, false when skipped, null when it could not show.
  Future<bool?> _show(String placement) async {
    final result = Completer<bool?>();
    void done(bool? value) {
      if (!result.isCompleted) result.complete(value);
    }

    await unity.UnityAds.showVideoAd(
      placementId: placement,
      onComplete: (_) => done(true),
      onSkipped: (_) => done(false),
      onFailed: (_, error, message) {
        FabAds.log(id, 'show: $message');
        done(null);
      },
    );
    return result.future;
  }

  @override
  Widget? banner(FabBannerSize size, {required VoidCallback onFailed}) {
    final mrec = size == FabBannerSize.mrec;
    final placement = mrec ? config.mrec : config.banner;
    if (placement.isEmpty) return null;
    return unity.UnityBannerAd(
      key: ValueKey(placement),
      placementId: placement,
      size: unity.BannerSize(width: size.width, height: size.height),
      onFailed: (_, error, message) {
        FabAds.log(id, 'banner: $message');
        onFailed();
      },
    );
  }
}
