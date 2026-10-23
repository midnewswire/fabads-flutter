import 'package:fab_ads/fab_ads.dart';

/// Meta Audience Network, run through the Kotlin SDK. Android only: on iOS it never starts and the next network is used.
class FabMeta extends FabBridgeNetwork {
  const FabMeta() : super(NetworkIds.meta);
}
