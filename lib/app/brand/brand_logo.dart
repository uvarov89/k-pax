import 'package:flutter/material.dart';

import 'package:pulse_vpn/app/brand/app_brand.dart';
import 'package:pulse_vpn/app/brand/xplm_mark.dart';

/// Brand mark: vector X for X-Plm, raster asset for K-Pax.
class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.size = 36});

  final double size;

  @override
  Widget build(BuildContext context) {
    final brand = AppBrand.current;
    if (brand.isXplm) {
      return XplmMark(size: size);
    }
    return Image.asset(
      brand.logoAsset,
      width: size,
      height: size,
      fit: BoxFit.contain,
    );
  }
}
