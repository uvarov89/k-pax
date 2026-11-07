import 'package:flutter/material.dart';

import 'package:pulse_vpn/app/brand/app_brand.dart';

/// Brand asset for the active application flavor.
class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.size = 36});

  final double size;

  @override
  Widget build(BuildContext context) {
    final brand = AppBrand.current;
    return Image.asset(
      brand.logoAsset,
      width: size,
      height: size,
      fit: BoxFit.contain,
    );
  }
}
