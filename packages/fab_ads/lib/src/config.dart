/// The ids of every network FabAds knows, and the older names the admin panels used for some of them.
abstract final class NetworkIds {
  static const admob = 'admob';
  static const adManager = 'admanager';
  static const applovin = 'applovin';
  static const meta = 'meta';
  static const unity = 'unity';
  static const startio = 'startio';
  static const ironsource = 'ironsource';
  static const pangle = 'pangle';
  static const mintegral = 'mintegral';
  static const liftoff = 'liftoff';
  static const inmobi = 'inmobi';
  static const chartboost = 'chartboost';
  static const yandex = 'yandex';
  static const wortise = 'wortise';

  static const all = [
    admob, adManager, applovin, meta, unity, startio, ironsource, //
    pangle, mintegral, liftoff, inmobi, chartboost, yandex, wortise,
  ];

  static const _aliases = {
    'startapp': startio,
    'start.io': startio,
    'google_ad_manager': adManager,
    'gam': adManager,
    'ad_manager': adManager,
    'max': applovin,
    'applovin_max': applovin,
    'fan': meta,
    'facebook': meta,
    'levelplay': ironsource,
    'vungle': liftoff,
  };

  static String normalize(String id) {
    final key = id.trim().toLowerCase();
    return _aliases[key] ?? key;
  }

  /// Older JSON keys that hold the same network's ids.
  static List<String> aliases(String id) => [
        for (final e in _aliases.entries)
          if (e.value == id) e.key,
      ];
}

/// The ads settings from the admin panel (or a JSON file in apps without one). Every key is optional.
/// The format is the same in the Kotlin SDK; see the README.
class AdsConfig {
  AdsConfig._(this.json);

  factory AdsConfig.fromJson(Map<String, dynamic>? json) => AdsConfig._(json ?? const {});

  /// Ads off.
  static final disabled = AdsConfig._(const {});

  final Map<String, dynamic> json;

  bool get enabled => _bool(json['enabled'], false);

  /// The networks to use, in the admin's order. The first one with an ad wins.
  List<String> get networks {
    final list = json['networks'] is List
        ? (json['networks'] as List).map((e) => '$e')
        : ['${json['primary'] ?? ''}', '${json['fallback'] ?? ''}'];
    final ids = list.map(NetworkIds.normalize).where((id) => id.isNotEmpty && id != 'none' && id != 'null');
    return ids.toSet().toList();
  }

  /// Ask every network for test ads.
  bool get testMode => _bool(json['test_mode'], false);

  /// Show an interstitial on every Nth action. 0 turns interstitials off.
  int get interstitialEvery => _int(_map(json['interstitial'])?['every'] ?? json['interstitial_every'], 3);

  /// Seconds that must pass between two interstitials.
  int get interstitialMinSeconds => _int(_map(json['interstitial'])?['min_seconds'], 0);

  /// Show an app open ad when the app starts.
  bool get appOpen {
    final value = json['app_open'];
    return value is Map ? _bool(value['enabled'], false) : _bool(value, false);
  }

  /// Also show an app open ad each time the user comes back to the app.
  bool get appOpenOnResume => _bool(_map(json['app_open'])?['on_resume'], false);

  bool get rewarded => _bool(_map(json['rewarded'])?['enabled'], true);

  /// Items between two native ads in lists. 0 turns them off.
  int get nativeEvery => _int(json['native_every'], 0);

  /// The app is for children (COPPA, Families policy).
  bool get childDirected => _bool(json['child_directed'], false);

  /// Show Google's consent form (UMP) before the first ad request.
  bool get consentForm => _bool(json['consent_form'], true);

  /// Whether the placement named [name] is on. Placements the admin does not list are on.
  bool placement(String name) {
    final placements = _map(json['placements']) ?? const {};
    final fallback = name == 'detail_banner' ? _bool(json['banner_on_detail'], true) : true;
    return _bool(placements[name], fallback);
  }

  /// The ids for one network. Empty when the admin left it blank.
  NetworkConfig network(String id) {
    for (final key in [id, ...NetworkIds.aliases(id)]) {
      final value = _map(json[key]);
      if (value != null) return NetworkConfig(id, value);
    }
    return NetworkConfig(id, const {});
  }

  @override
  String toString() => json.toString();
}

/// One network's settings: its app id or key, and one unit id per format.
class NetworkConfig {
  const NetworkConfig(this.id, this.json);

  final String id;
  final Map<String, dynamic> json;

  String string(String key) {
    final value = json[key];
    return value == null ? '' : '$value'.trim();
  }

  bool boolean(String key, [bool fallback = false]) => _bool(json[key], fallback);

  String get appId => string('app_id');
  String get appKey => string('app_key');
  String get banner => string('banner');

  /// Falls back to [banner] when empty.
  String get mrec => string('mrec').isEmpty ? banner : string('mrec');
  String get interstitial => string('interstitial');
  String get rewarded => string('rewarded');
  String get native => string('native');
  String get appOpen => string('app_open');
  bool get isEmpty => json.isEmpty;
}

Map<String, dynamic>? _map(Object? value) => value is Map ? value.cast<String, dynamic>() : null;

bool _bool(Object? value, bool fallback) => switch (value) {
      bool b => b,
      num n => n != 0,
      String s when s.toLowerCase() == 'true' || s == '1' => true,
      String s when s.toLowerCase() == 'false' || s == '0' => false,
      _ => fallback,
    };

int _int(Object? value, int fallback) => switch (value) {
      num n => n.toInt(),
      String s => int.tryParse(s) ?? fallback,
      _ => fallback,
    };
