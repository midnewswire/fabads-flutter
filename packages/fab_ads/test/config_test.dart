import 'package:fab_ads/fab_ads.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reads the current format', () {
    final config = AdsConfig.fromJson({
      'enabled': true,
      'networks': ['AdMob', 'max', 'facebook', 'admob'],
      'interstitial': {'every': 4, 'min_seconds': 30},
      'app_open': {'enabled': true, 'on_resume': true},
      'native_every': 6,
      'placements': {'home_banner': false},
      'admob': {'banner': 'b', 'interstitial': 'i'},
      'fan': {'native': 'n'},
    });
    expect(config.enabled, isTrue);
    expect(config.networks, ['admob', 'applovin', 'meta']);
    expect(config.interstitialEvery, 4);
    expect(config.interstitialMinSeconds, 30);
    expect(config.appOpen, isTrue);
    expect(config.appOpenOnResume, isTrue);
    expect(config.nativeEvery, 6);
    expect(config.placement('home_banner'), isFalse);
    expect(config.placement('detail_banner'), isTrue);
    expect(config.network('admob').mrec, 'b');
    expect(config.network('meta').native, 'n');
    expect(config.network('unity').isEmpty, isTrue);
  });

  test('reads older payloads', () {
    final config = AdsConfig.fromJson({
      'enabled': 'true',
      'primary': 'admob',
      'fallback': 'startapp',
      'interstitial_every': '5',
      'app_open': true,
      'banner_on_detail': false,
      'startapp': {'app_id': '123'},
    });
    expect(config.enabled, isTrue);
    expect(config.networks, ['admob', 'startio']);
    expect(config.interstitialEvery, 5);
    expect(config.appOpen, isTrue);
    expect(config.placement('detail_banner'), isFalse);
    expect(config.network('startio').appId, '123');
  });

  test('missing settings turn ads off', () {
    final config = AdsConfig.fromJson(null);
    expect(config.enabled, isFalse);
    expect(config.networks, isEmpty);
    expect(config.rewarded, isTrue);
    expect(config.consentForm, isTrue);
  });

  test('interstitial shows on every Nth action', () async {
    final network = _FakeNetwork();
    FabAds.reset();
    FabAds.useNetworks(AdsConfig.fromJson({'enabled': true, 'interstitial': {'every': 2}}), [network]);
    for (var i = 0; i < 4; i++) {
      await FabAds.interstitial();
    }
    expect(network.shown, 2);
    FabAds.noAds = true;
    await FabAds.interstitial();
    await FabAds.interstitial();
    expect(network.shown, 2);
  });
}

class _FakeNetwork extends FabAdNetwork {
  int shown = 0;

  @override
  String get id => 'fake';

  @override
  bool supports(AdFormat format) => format == AdFormat.interstitial;

  @override
  Future<void> init() async {}

  @override
  Future<bool> showInterstitial() async {
    shown++;
    return true;
  }
}
