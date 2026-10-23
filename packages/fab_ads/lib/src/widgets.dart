import 'package:flutter/widgets.dart';

import 'fab_ads.dart';
import 'network.dart';

/// A banner from the first network that has one. Takes no space while ads are off or no network has an ad.
class FabBanner extends StatefulWidget {
  const FabBanner({super.key, this.placement, this.size = FabBannerSize.banner});

  /// The admin can turn this placement off. Null: always on while ads are on.
  final String? placement;
  final FabBannerSize size;

  @override
  State<FabBanner> createState() => _FabBannerState();
}

class _FabBannerState extends State<FabBanner> {
  /// Networks before this one in the order had no ad.
  int _next = 0;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: FabAds.changes,
      builder: (context, _) {
        final placement = widget.placement;
        if (!FabAds.enabled || (placement != null && !FabAds.placement(placement))) return const SizedBox.shrink();
        final order = FabAds.bannerNetworks(widget.size);
        for (var i = _next; i < order.length; i++) {
          final ad = order[i].banner(widget.size, onFailed: () {
            if (mounted) setState(() => _next = i + 1);
          });
          if (ad != null) {
            return SizedBox(
              height: widget.size.height.toDouble(),
              child: Center(child: KeyedSubtree(key: ValueKey('${order[i].id}/${widget.size.name}'), child: ad)),
            );
          }
        }
        return const SizedBox.shrink();
      },
    );
  }
}

/// A native ad from the first network that has one, falling back to a banner (or medium rectangle for the
/// bigger styles) when none does.
class FabNative extends StatefulWidget {
  const FabNative({
    super.key,
    this.placement,
    this.style = NativeStyle.medium,
    this.dark,
    this.fallbackToBanner = true,
  });

  final String? placement;
  final NativeStyle style;

  /// Null: follows the app's theme brightness.
  final bool? dark;
  final bool fallbackToBanner;

  @override
  State<FabNative> createState() => _FabNativeState();
}

class _FabNativeState extends State<FabNative> {
  int _next = 0;

  @override
  Widget build(BuildContext context) {
    final dark = widget.dark ?? MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    return ListenableBuilder(
      listenable: FabAds.changes,
      builder: (context, _) {
        final placement = widget.placement;
        if (!FabAds.enabled || (placement != null && !FabAds.placement(placement))) return const SizedBox.shrink();
        final order = FabAds.nativeNetworks();
        for (var i = _next; i < order.length; i++) {
          final ad = order[i].native(widget.style, dark: dark, onFailed: () {
            if (mounted) setState(() => _next = i + 1);
          });
          if (ad != null) return KeyedSubtree(key: ValueKey('${order[i].id}/${widget.style.name}'), child: ad);
        }
        return widget.fallbackToBanner ? FabBanner(size: widget.style.fallbackSize) : const SizedBox.shrink();
      },
    );
  }
}
