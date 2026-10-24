# FabAds for Flutter

One ads API for every fab Flutter app. Pick the ad networks you want, give FabAds the settings from your admin
panel (or a JSON file), and use the same few calls for banners, native ads, interstitials, rewarded and app open
ads. FabAds tries your networks in the order you set and moves to the next one when a network has no ad.

The settings format, the network ids and the behaviour are the same as in
[FabAds for Android](https://github.com/midnewswire/fabads-kotlin), so one admin panel serves both.

| Package | Network | Platforms |
| --- | --- | --- |
| `fab_ads` | core: consent form, waterfall, widgets | Android, iOS |
| `fab_ads_admob` | AdMob (`FabAdMob`) and Google Ad Manager (`FabAdManager`) | Android, iOS |
| `fab_ads_applovin` | AppLovin MAX (`FabAppLovin`) | Android, iOS |
| `fab_ads_unity` | Unity Ads (`FabUnity`) | Android, iOS |
| `fab_ads_meta` | Meta Audience Network (`FabMeta`) | Android |
| `fab_ads_startio` | Start.io (`FabStartIo`) | Android |
| `fab_ads_ironsource` | ironSource LevelPlay (`FabIronSource`) | Android |
| `fab_ads_pangle` | Pangle (`FabPangle`) | Android |
| `fab_ads_mintegral` | Mintegral (`FabMintegral`) | Android |
| `fab_ads_liftoff` | Liftoff / Vungle (`FabLiftoff`) | Android |
| `fab_ads_inmobi` | InMobi (`FabInMobi`) | Android |
| `fab_ads_chartboost` | Chartboost (`FabChartboost`) | Android |
| `fab_ads_yandex` | Yandex Ads (`FabYandex`) | Android |
| `fab_ads_wortise` | Wortise (`FabWortise`) | Android, needs `minSdk` 24 |

AdMob, AppLovin and Unity use each network's own Flutter plugin. The Android only packages run the network
modules of FabAds for Android through `fab_ads`; on iOS they never start and the next network in the order is used.

## Choose your ad networks

**Ship only the networks you use.** Every network is a separate package, and an app contains only the network
SDKs it depends on. Bundling many ad SDKs you do not use makes the app bigger, and Google Play has removed apps
whose ad SDKs it found to break its policies, so a small, deliberate set is the safest choice. A common setup is
one network, or one main network plus one backup.

The fab apps ship with AdMob only. To add a network, add its package to `pubspec.yaml` and its class to the list
in `lib/config/ads.dart`. To remove AdMob, delete both of its lines the same way. That is all: the admin panel then decides whether it runs, in what order, and with
which ad units.

## Install

`pubspec.yaml`, one entry per network, all at the same `ref`. Each network package brings `fab_ads` with it, so
do not list `fab_ads` itself (pub would see two different copies of it):

```yaml
dependencies:
  fab_ads_admob:
    git:
      url: https://github.com/midnewswire/fabads-flutter
      path: packages/fab_ads_admob
      ref: 1.0.0
  # fab_ads_applovin:
  #   git:
  #     url: https://github.com/midnewswire/fabads-flutter
  #     path: packages/fab_ads_applovin
  #     ref: 1.0.0
```

Import a network package and you have the whole API: `import 'package:fab_ads_admob/fab_ads_admob.dart';`.

AdMob and Ad Manager need your AdMob app id in `android/app/src/main/AndroidManifest.xml`:

```xml
<meta-data android:name="com.google.android.gms.ads.APPLICATION_ID" android:value="ca-app-pub-xxxxxxxx~yyyyyyyy" />
```

and in `ios/Runner/Info.plist`:

```xml
<key>GADApplicationIdentifier</key>
<string>ca-app-pub-xxxxxxxx~yyyyyyyy</string>
```

Android needs `minSdk` 23 or higher (24 with Wortise).

## Use

```dart
// lib/config/ads.dart: the networks this app ships.
const adNetworks = <FabNetwork>[FabAdMob()];

// Once the admin's settings are loaded:
await FabAds.start(AdsConfig.fromJson(json['ads']), networks: adNetworks, debug: kDebugMode);

// Widgets
const FabBanner(placement: 'home_banner')
const FabBanner(size: FabBannerSize.mrec)
const FabNative(style: NativeStyle.news)     // small, medium, large, news, radio, video

// Interstitial on every Nth action (from the admin). Navigate after it; it returns at once when no ad shows.
await FabAds.interstitial(placement: 'open_item');
openItem();

// Rewarded
if (await FabAds.rewarded()) unlock();

// Premium users
FabAds.noAds = user.isPremium;

// Lists: a native ad after every N items
final every = FabAds.nativeEvery;

// Privacy settings item for users in the EEA, UK and some US states
if (await FabAds.privacyOptionsRequired()) FabAds.showPrivacyOptions();
```

App open ads show once at launch (`app_open.enabled`) and, if `app_open.on_resume` is on, each time the user
returns to the app. FabAds never shows one on top of another full screen ad.

## Consent

`FabAds.start` shows Google's consent form (UMP) first where the law requires it, then passes the answer to every
network. With `fab_ads_admob` the form runs on Android and iOS; without it, it runs on Android through `fab_ads`.
Set the form up once in the AdMob console under Privacy & messaging. Apps that handle consent themselves set
`"consent_form": false`.

## Settings (the `ads` JSON)

The admin panel serves this object; apps without an admin load it from a file. Every key is optional.

```json
{
  "enabled": true,
  "networks": ["admob", "applovin"],
  "test_mode": false,
  "child_directed": false,
  "consent_form": true,
  "interstitial": { "every": 3, "min_seconds": 60 },
  "app_open": { "enabled": true, "on_resume": false },
  "rewarded": { "enabled": true },
  "native_every": 8,
  "placements": { "home_banner": true, "detail_banner": true, "native": true },
  "admob": { "banner": "", "mrec": "", "interstitial": "", "rewarded": "", "native": "", "app_open": "" },
  "applovin": { "sdk_key": "", "banner": "", "mrec": "", "interstitial": "", "rewarded": "", "app_open": "" }
}
```

- `networks` is the waterfall order. A network listed here but not built into the app is skipped.
- `test_mode` (and `debug: true`) requests test ads.
- `placements` are names the app chooses. A placement the admin does not list is on.
- `mrec` falls back to `banner` when empty.
- Older payloads with `primary` / `fallback`, `interstitial_every`, `app_open: true` and `startapp` still work.

The keys each network needs are listed in the
[FabAds for Android README](https://github.com/midnewswire/fabads-kotlin#network-ids). In Flutter, AppLovin
has no native ads and needs `sdk_key` in the settings; native ads from the other networks fall back to a banner
when a network has none.

## Example

`example/` shows every format with test ads from `example/assets/ads.json`: `cd example && flutter run`.

## Releases

Tag a version (`1.0.0`) and point the `ref` of every package at it. A commit id works as a `ref` too, and that is
what the fab apps use until the first tag exists. The Android only packages depend on the FabAds for Android build
named in their `android/build.gradle` (a JitPack tag or commit id); keep it in step with fabads-kotlin.
