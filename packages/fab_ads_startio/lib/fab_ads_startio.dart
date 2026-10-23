import 'package:fab_ads/fab_ads.dart';

/// Start.io, run through the Kotlin SDK. Android only: on iOS it never starts and the next network is used.
class FabStartIo extends FabBridgeNetwork {
  const FabStartIo() : super(NetworkIds.startio);
}
