import 'dart:convert';

import 'package:fab_ads_admob/fab_ads_admob.dart';
import 'package:fab_ads_applovin/fab_ads_applovin.dart';
import 'package:fab_ads_chartboost/fab_ads_chartboost.dart';
import 'package:fab_ads_inmobi/fab_ads_inmobi.dart';
import 'package:fab_ads_ironsource/fab_ads_ironsource.dart';
import 'package:fab_ads_liftoff/fab_ads_liftoff.dart';
import 'package:fab_ads_meta/fab_ads_meta.dart';
import 'package:fab_ads_mintegral/fab_ads_mintegral.dart';
import 'package:fab_ads_pangle/fab_ads_pangle.dart';
import 'package:fab_ads_startio/fab_ads_startio.dart';
import 'package:fab_ads_unity/fab_ads_unity.dart';
import 'package:fab_ads_wortise/fab_ads_wortise.dart';
import 'package:fab_ads_yandex/fab_ads_yandex.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The demo ships every network. A real app lists only the networks it uses, here and in pubspec.yaml.
const networks = <FabNetwork>[
  FabAdMob(),
  FabAdManager(),
  FabAppLovin(),
  FabUnity(),
  FabMeta(),
  FabStartIo(),
  FabIronSource(),
  FabPangle(),
  FabMintegral(),
  FabLiftoff(),
  FabInMobi(),
  FabChartboost(),
  FabYandex(),
  FabWortise(),
];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DemoApp());
  final json = jsonDecode(await rootBundle.loadString('assets/ads.json')) as Map<String, dynamic>;
  await FabAds.start(AdsConfig.fromJson(json), networks: networks, debug: true);
}

class DemoApp extends StatelessWidget {
  const DemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FabAds demo',
      theme: ThemeData(colorSchemeSeed: Colors.indigo),
      darkTheme: ThemeData(colorSchemeSeed: Colors.indigo, brightness: Brightness.dark),
      home: const DemoPage(),
    );
  }
}

class DemoPage extends StatefulWidget {
  const DemoPage({super.key});

  @override
  State<DemoPage> createState() => _DemoPageState();
}

class _DemoPageState extends State<DemoPage> {
  String _status = '';

  void _say(String text) => setState(() => _status = text);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('FabAds demo')),
      bottomNavigationBar: const SafeArea(child: FabBanner(placement: 'home_banner')),
      body: ListenableBuilder(
        listenable: FabAds.changes,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Built in: ${FabAds.installedNetworks.join(', ')}'),
            Text('Running: ${FabAds.activeNetworks.join(', ')}'),
            if (_status.isNotEmpty) Text(_status),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: () async => _say(await FabAds.showInterstitialNow() ? 'Interstitial closed' : 'No interstitial yet'),
                  child: const Text('Interstitial'),
                ),
                FilledButton(
                  onPressed: () async => _say(await FabAds.rewarded() ? 'Reward earned' : 'No reward'),
                  child: const Text('Rewarded'),
                ),
                OutlinedButton(
                  onPressed: () => FabAds.noAds = !FabAds.noAds,
                  child: Text(FabAds.noAds ? 'Turn ads on' : 'Premium (no ads)'),
                ),
                OutlinedButton(onPressed: FabAds.showPrivacyOptions, child: const Text('Privacy settings')),
              ],
            ),
            for (final style in NativeStyle.values) ...[
              const SizedBox(height: 16),
              Text('Native: ${style.name}'),
              FabNative(style: style),
            ],
            const SizedBox(height: 16),
            const Text('Medium rectangle'),
            const FabBanner(size: FabBannerSize.mrec),
          ],
        ),
      ),
    );
  }
}
