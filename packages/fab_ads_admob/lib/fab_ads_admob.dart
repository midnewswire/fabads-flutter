import 'dart:async';

import 'package:fab_ads/fab_ads.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Apps import only their network packages; each one brings the whole FabAds API.
export 'package:fab_ads/fab_ads.dart';

/// AdMob, on Android and iOS. Also runs Google's consent form (UMP) for every network.
///
/// Put your AdMob app id in AndroidManifest.xml (`com.google.android.gms.ads.APPLICATION_ID`) and Info.plist
/// (`GADApplicationIdentifier`).
class FabAdMob extends FabNetwork {
  const FabAdMob();

  @override
  String get id => NetworkIds.admob;

  @override
  Future<FabAdNetwork?> create(NetworkConfig config, AdEnvironment env) async =>
      _GoogleNetwork(id, config, env, manager: false);

  @override
  Future<Privacy?> requestConsent({required bool debug}) => _consent();

  @override
  Future<bool?> privacyOptionsRequired() async =>
      await ConsentInformation.instance.getPrivacyOptionsRequirementStatus() == PrivacyOptionsRequirementStatus.required;

  @override
  Future<bool> showPrivacyOptions() async {
    final done = Completer<bool>();
    await ConsentForm.showPrivacyOptionsForm((_) => done.complete(true));
    return done.future;
  }
}

/// Google Ad Manager, on Android and iOS. Unit keys hold ad unit paths (`/1234/home_banner`).
class FabAdManager extends FabNetwork {
  const FabAdManager();

  @override
  String get id => NetworkIds.adManager;

  @override
  Future<FabAdNetwork?> create(NetworkConfig config, AdEnvironment env) async =>
      _GoogleNetwork(id, config, env, manager: true);
}

Future<Privacy?> _consent() async {
  final done = Completer<void>();
  ConsentInformation.instance.requestConsentInfoUpdate(
    ConsentRequestParameters(),
    () => ConsentForm.loadAndShowConsentFormIfRequired((_) => done.complete()),
    (error) {
      FabAds.log('consent', error.message);
      done.complete();
    },
  );
  await done.future;
  return Privacy(consent: await ConsentInformation.instance.canRequestAds());
}

class _GoogleNetwork extends FabAdNetwork {
  _GoogleNetwork(this.id, this.config, this.env, {required this.manager});

  @override
  final String id;
  final NetworkConfig config;
  final AdEnvironment env;
  final bool manager;

  AdWithoutView? _interstitial;
  bool _interstitialLoading = false;
  AppOpenAd? _appOpen;
  bool _appOpenLoading = false;

  static final _android = defaultTargetPlatform == TargetPlatform.android;

  /// Google's sample units, used in test mode.
  static final _testUnits = _android
      ? const {
          'banner': 'ca-app-pub-3940256099942544/6300978111',
          'interstitial': 'ca-app-pub-3940256099942544/1033173712',
          'rewarded': 'ca-app-pub-3940256099942544/5224354917',
          'native': 'ca-app-pub-3940256099942544/2247696110',
          'app_open': 'ca-app-pub-3940256099942544/9257395921',
        }
      : const {
          'banner': 'ca-app-pub-3940256099942544/2934735716',
          'interstitial': 'ca-app-pub-3940256099942544/4411468910',
          'rewarded': 'ca-app-pub-3940256099942544/1712485313',
          'native': 'ca-app-pub-3940256099942544/3986624511',
          'app_open': 'ca-app-pub-3940256099942544/5575463023',
        };

  String _unit(String format, String value) =>
      value.isEmpty ? '' : (env.testMode && !manager ? _testUnits[format]! : value);

  AdRequest get _request => const AdRequest();
  AdManagerAdRequest get _managerRequest => const AdManagerAdRequest();

  @override
  bool supports(AdFormat format) => switch (format) {
        AdFormat.banner => config.banner.isNotEmpty,
        AdFormat.mrec => config.mrec.isNotEmpty,
        AdFormat.interstitial => config.interstitial.isNotEmpty,
        AdFormat.rewarded => config.rewarded.isNotEmpty,
        AdFormat.native => config.native.isNotEmpty,
        AdFormat.appOpen => config.appOpen.isNotEmpty,
      };

  @override
  Future<void> init() async {
    await MobileAds.instance.updateRequestConfiguration(RequestConfiguration(
      ageRestrictedTreatment: env.privacy.childDirected ? AgeRestrictedTreatment.child : AgeRestrictedTreatment.unspecified,
    ));
    await MobileAds.instance.initialize();
  }

  @override
  void loadInterstitial() {
    if (_interstitial != null || _interstitialLoading || !supports(AdFormat.interstitial)) return;
    _interstitialLoading = true;
    final unit = _unit('interstitial', config.interstitial);
    void failed(LoadAdError error) {
      _interstitialLoading = false;
      FabAds.log(id, 'interstitial: ${error.message}');
    }

    void loaded(AdWithoutView ad) {
      _interstitialLoading = false;
      _interstitial = ad;
    }

    if (manager) {
      AdManagerInterstitialAd.load(
        adUnitId: unit,
        request: _managerRequest,
        adLoadCallback: AdManagerInterstitialAdLoadCallback(onAdLoaded: loaded, onAdFailedToLoad: failed),
      );
    } else {
      InterstitialAd.load(
        adUnitId: unit,
        request: _request,
        adLoadCallback: InterstitialAdLoadCallback(onAdLoaded: loaded, onAdFailedToLoad: failed),
      );
    }
  }

  @override
  Future<bool> showInterstitial() async {
    final ad = _interstitial;
    if (ad == null) return false;
    _interstitial = null;
    final closed = Completer<bool>();
    void done(Ad ad) {
      ad.dispose();
      if (!closed.isCompleted) closed.complete(true);
    }

    if (ad is InterstitialAd) {
      ad.fullScreenContentCallback = FullScreenContentCallback(
        onAdDismissedFullScreenContent: done,
        onAdFailedToShowFullScreenContent: (ad, _) => done(ad),
      );
      await ad.show();
    } else if (ad is AdManagerInterstitialAd) {
      ad.fullScreenContentCallback = FullScreenContentCallback(
        onAdDismissedFullScreenContent: done,
        onAdFailedToShowFullScreenContent: (ad, _) => done(ad),
      );
      await ad.show();
    }
    return closed.future;
  }

  @override
  Future<bool?> showRewarded() async {
    if (!supports(AdFormat.rewarded)) return null;
    final result = Completer<bool?>();
    final unit = _unit('rewarded', config.rewarded);
    final callback = RewardedAdLoadCallback(
      onAdLoaded: (ad) {
        var earned = false;
        void done(RewardedAd ad, bool? value) {
          ad.dispose();
          if (!result.isCompleted) result.complete(value);
        }

        ad.fullScreenContentCallback = FullScreenContentCallback(
          onAdDismissedFullScreenContent: (ad) => done(ad, earned),
          onAdFailedToShowFullScreenContent: (ad, _) => done(ad, null),
        );
        ad.show(onUserEarnedReward: (_, __) => earned = true);
      },
      onAdFailedToLoad: (error) {
        FabAds.log(id, 'rewarded: ${error.message}');
        result.complete(null);
      },
    );
    if (manager) {
      await RewardedAd.loadWithAdManagerAdRequest(
          adUnitId: unit, adManagerRequest: _managerRequest, rewardedAdLoadCallback: callback);
    } else {
      await RewardedAd.load(adUnitId: unit, request: _request, rewardedAdLoadCallback: callback);
    }
    return result.future;
  }

  @override
  void loadAppOpen(VoidCallback onLoaded) {
    if (_appOpen != null) return onLoaded();
    if (_appOpenLoading || !supports(AdFormat.appOpen)) return;
    _appOpenLoading = true;
    final callback = AppOpenAdLoadCallback(
      onAdLoaded: (ad) {
        _appOpenLoading = false;
        _appOpen = ad;
        onLoaded();
      },
      onAdFailedToLoad: (error) {
        _appOpenLoading = false;
        FabAds.log(id, 'app open: ${error.message}');
      },
    );
    final unit = _unit('app_open', config.appOpen);
    if (manager) {
      AppOpenAd.loadWithAdManagerAdRequest(adUnitId: unit, adManagerAdRequest: _managerRequest, adLoadCallback: callback);
    } else {
      AppOpenAd.load(adUnitId: unit, request: _request, adLoadCallback: callback);
    }
  }

  @override
  Future<bool> showAppOpen() async {
    final ad = _appOpen;
    if (ad == null) return false;
    _appOpen = null;
    final closed = Completer<bool>();
    void done(AppOpenAd ad) {
      ad.dispose();
      if (!closed.isCompleted) closed.complete(true);
    }

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: done,
      onAdFailedToShowFullScreenContent: (ad, _) => done(ad),
    );
    await ad.show();
    return closed.future;
  }

  @override
  Widget? banner(FabBannerSize size, {required VoidCallback onFailed}) {
    final mrec = size == FabBannerSize.mrec;
    if (!supports(mrec ? AdFormat.mrec : AdFormat.banner)) return null;
    final unit = _unit('banner', mrec ? config.mrec : config.banner);
    return _GoogleAdView(
      key: ValueKey(unit),
      height: size.height.toDouble(),
      width: size.width.toDouble(),
      create: (listener) {
        final adSize = mrec ? AdSize.mediumRectangle : AdSize.banner;
        return manager
            ? AdManagerBannerAd(
                sizes: [adSize],
                adUnitId: unit,
                request: _managerRequest,
                listener: AdManagerBannerAdListener(onAdLoaded: listener.onAdLoaded, onAdFailedToLoad: listener.onAdFailedToLoad),
              )
            : BannerAd(
                size: adSize,
                adUnitId: unit,
                request: _request,
                listener: BannerAdListener(onAdLoaded: listener.onAdLoaded, onAdFailedToLoad: listener.onAdFailedToLoad),
              );
      },
      onFailed: (error) {
        FabAds.log(id, 'banner: ${error.message}');
        onFailed();
      },
    );
  }

  @override
  Widget? native(NativeStyle style, {required bool dark, required VoidCallback onFailed}) {
    if (!supports(AdFormat.native)) return null;
    final small = style == NativeStyle.small || style == NativeStyle.radio;
    final unit = _unit('native', config.native);
    final templateStyle = NativeTemplateStyle(
      templateType: small ? TemplateType.small : TemplateType.medium,
      mainBackgroundColor: dark ? const Color(0xFF1E1E1E) : Colors.white,
      primaryTextStyle: NativeTemplateTextStyle(textColor: dark ? Colors.white : Colors.black87),
      secondaryTextStyle: NativeTemplateTextStyle(textColor: dark ? Colors.white70 : Colors.black54),
      tertiaryTextStyle: NativeTemplateTextStyle(textColor: dark ? Colors.white70 : Colors.black54),
      cornerRadius: 8,
    );
    return _GoogleAdView(
      key: ValueKey('$unit/${style.name}/$dark'),
      height: small ? 110 : 340,
      create: (listener) {
        final nativeListener =
            NativeAdListener(onAdLoaded: listener.onAdLoaded, onAdFailedToLoad: listener.onAdFailedToLoad);
        return manager
            ? NativeAd.fromAdManagerRequest(
                adUnitId: unit,
                adManagerRequest: _managerRequest,
                listener: nativeListener,
                nativeTemplateStyle: templateStyle,
              )
            : NativeAd(adUnitId: unit, request: _request, listener: nativeListener, nativeTemplateStyle: templateStyle);
      },
      onFailed: (error) {
        FabAds.log(id, 'native: ${error.message}');
        onFailed();
      },
    );
  }
}

class _Listener {
  _Listener(this.onAdLoaded, this.onAdFailedToLoad);

  final void Function(Ad ad) onAdLoaded;
  final void Function(Ad ad, LoadAdError error) onAdFailedToLoad;
}

/// Loads one banner or native ad and shows it once loaded. Takes no space until then.
class _GoogleAdView extends StatefulWidget {
  const _GoogleAdView({super.key, required this.create, required this.height, this.width, required this.onFailed});

  final AdWithView Function(_Listener listener) create;
  final double height;
  final double? width;
  final void Function(LoadAdError error) onFailed;

  @override
  State<_GoogleAdView> createState() => _GoogleAdViewState();
}

class _GoogleAdViewState extends State<_GoogleAdView> {
  AdWithView? _ad;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _ad = widget.create(_Listener(
      (_) {
        if (mounted) setState(() => _loaded = true);
      },
      (ad, error) {
        ad.dispose();
        _ad = null;
        if (mounted) widget.onFailed(error);
      },
    ))
      ..load();
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ad = _ad;
    if (ad == null || !_loaded) return const SizedBox.shrink();
    return SizedBox(width: widget.width, height: widget.height, child: AdWidget(ad: ad));
  }
}
