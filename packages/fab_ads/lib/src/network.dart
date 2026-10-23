import 'package:flutter/widgets.dart';

import 'config.dart';

enum AdFormat { banner, mrec, interstitial, rewarded, native, appOpen }

enum FabBannerSize {
  /// 320 x 50
  banner(320, 50),

  /// Medium rectangle, 300 x 250
  mrec(300, 250);

  const FabBannerSize(this.width, this.height);

  final int width;
  final int height;
}

/// Native ad layouts, one per kind of product screen.
enum NativeStyle {
  /// Icon, title and button in one row. For lists.
  small,

  /// Title row, media, text and a full width button.
  medium,

  /// Like [medium] with taller media. For detail screens.
  large,

  /// Media on top, then title and text. Looks like a news card.
  news,

  /// A compact row for player screens.
  radio,

  /// Like [medium], for video networks.
  video;

  /// The banner size used when no network has a native ad.
  FabBannerSize get fallbackSize => this == small || this == radio ? FabBannerSize.banner : FabBannerSize.mrec;
}

/// What the user agreed to on the consent form.
class Privacy {
  const Privacy({this.gdprApplies = false, this.consent = true, this.doNotSell = false, this.childDirected = false});

  factory Privacy.fromMap(Map<Object?, Object?>? map) => Privacy(
        gdprApplies: map?['gdprApplies'] == true,
        consent: map?['consent'] != false,
        doNotSell: map?['doNotSell'] == true,
        childDirected: map?['childDirected'] == true,
      );

  final bool gdprApplies;

  /// Personalized ads allowed. Always true where GDPR does not apply.
  final bool consent;
  final bool doNotSell;
  final bool childDirected;

  Privacy copyWith({bool? childDirected}) => Privacy(
        gdprApplies: gdprApplies,
        consent: consent,
        doNotSell: doNotSell,
        childDirected: childDirected ?? this.childDirected,
      );

  Map<String, Object> toMap() =>
      {'gdprApplies': gdprApplies, 'consent': consent, 'doNotSell': doNotSell, 'childDirected': childDirected};
}

class AdEnvironment {
  const AdEnvironment({required this.testMode, required this.debug, required this.privacy});

  /// Request test ads.
  final bool testMode;
  final bool debug;
  final Privacy privacy;
}

/// A network package's entry point. Apps pass one per network they ship to [FabAds.start].
abstract class FabNetwork {
  const FabNetwork();

  String get id;

  /// Returns null when [config] lacks what the network needs (an app id, for example) or the platform is not supported.
  Future<FabAdNetwork?> create(NetworkConfig config, AdEnvironment env);

  /// Networks that ship a consent form (AdMob, through Google UMP) show it here. The rest return null.
  Future<Privacy?> requestConsent({required bool debug}) async => null;

  Future<bool?> privacyOptionsRequired() async => null;

  Future<bool> showPrivacyOptions() async => false;
}

/// One running network. Every method is optional except [supports] and [init].
abstract class FabAdNetwork {
  String get id;

  bool supports(AdFormat format);

  Future<void> init();

  void loadInterstitial() {}

  /// Shows a loaded interstitial and completes with true once it closes, or right away with false when none is loaded.
  Future<bool> showInterstitial() async => false;

  /// Loads and shows a rewarded ad. Completes with true when the reward was earned, false when the user closed it
  /// early, and null when no ad could be shown (the next network is tried).
  Future<bool?> showRewarded() async => null;

  /// Loads an app open ad and calls [onLoaded] when it is ready.
  void loadAppOpen(VoidCallback onLoaded) {}

  /// Like [showInterstitial], for app open ads.
  Future<bool> showAppOpen() async => false;

  /// A widget that loads a banner and calls [onFailed] when it has none. Null when this network has no unit for [size].
  Widget? banner(FabBannerSize size, {required VoidCallback onFailed}) => null;

  /// Like [banner], for native ads.
  Widget? native(NativeStyle style, {required bool dark, required VoidCallback onFailed}) => null;
}
