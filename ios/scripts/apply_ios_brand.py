#!/usr/bin/env python3
"""Apply K-Pax or X-Plm iOS identifiers (Windows-friendly twin of apply_ios_brand.rb)."""

from __future__ import annotations

import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BRAND = os.environ.get("BRAND", "kpax").strip().lower()

BRANDS = {
    "kpax": {
        "bundle_app": "space.kpax.app",
        "bundle_ext": "space.kpax.app.extension",
        "app_group": "group.space.kpax.app",
        "display_name": "K-Pax",
        "tunnel_name": "K-Pax Tunnel",
        "url_scheme": "kpax",
        "app_icon": "AppIcon",
        "local_network": "K-Pax uses the local network while the VPN tunnel is active.",
    },
    "xplm": {
        "bundle_app": "online.xplm.app",
        "bundle_ext": "online.xplm.app.extension",
        "app_group": "group.online.xplm.app",
        "display_name": "X-Plm",
        "tunnel_name": "X-Plm Tunnel",
        "url_scheme": "xplm",
        "app_icon": "AppIcon-Xplm",
        "local_network": "X-Plm uses the local network while the VPN tunnel is active.",
    },
}


def entitlements_xml(app_group: str) -> str:
    return f"""<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
\t<key>com.apple.developer.networking.networkextension</key>
\t<array>
\t\t<string>packet-tunnel-provider</string>
\t</array>
\t<key>com.apple.security.application-groups</key>
\t<array>
\t\t<string>{app_group}</string>
\t</array>
</dict>
</plist>
"""


def replace_plist_string(path: Path, key: str, value: str) -> None:
    text = path.read_text(encoding="utf-8")
    pattern = rf"(<key>{re.escape(key)}</key>\s*<string>)[^<]*(</string>)"
    new_text, n = re.subn(pattern, rf"\g<1>{value}\g<2>", text, count=1)
    if n != 1:
        raise SystemExit(f"key {key} not found in {path}")
    path.write_text(new_text, encoding="utf-8")


def replace_url_types(path: Path, bundle_app: str, scheme: str) -> None:
    text = path.read_text(encoding="utf-8")
    text, n1 = re.subn(
        r"(<key>CFBundleURLName</key>\s*<string>)[^<]*(</string>)",
        rf"\g<1>{bundle_app}\g<2>",
        text,
        count=1,
    )
    text, n2 = re.subn(
        r"(<key>CFBundleURLSchemes</key>\s*<array>\s*<string>)[^<]*(</string>)",
        rf"\g<1>{scheme}\g<2>",
        text,
        count=1,
    )
    if n1 != 1 or n2 != 1:
        raise SystemExit(f"CFBundleURLTypes patch failed in {path}")
    path.write_text(text, encoding="utf-8")


def patch_pbxproj(path: Path, bundle_app: str, app_icon: str) -> None:
    text = path.read_text(encoding="utf-8")
    for old in ("space.kpax.app", "online.xplm.app"):
        text = text.replace(
            f"PRODUCT_BUNDLE_IDENTIFIER = {old};",
            f"PRODUCT_BUNDLE_IDENTIFIER = {bundle_app};",
        )
        text = text.replace(
            f"PRODUCT_BUNDLE_IDENTIFIER = {old}.RunnerTests;",
            f"PRODUCT_BUNDLE_IDENTIFIER = {bundle_app}.RunnerTests;",
        )
    text = re.sub(
        r"ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon(?:-Xplm)?;",
        f"ASSETCATALOG_COMPILER_APPICON_NAME = {app_icon};",
        text,
    )
    path.write_text(text, encoding="utf-8")


def main() -> None:
    cfg = BRANDS.get(BRAND)
    if not cfg:
        raise SystemExit(f"Unknown BRAND={BRAND!r} (expected: {', '.join(BRANDS)})")

    (ROOT / "ios/Runner/Runner.entitlements").write_text(
        entitlements_xml(cfg["app_group"]), encoding="utf-8"
    )
    (ROOT / "ios/PacketTunnel/PacketTunnel.entitlements").write_text(
        entitlements_xml(cfg["app_group"]), encoding="utf-8"
    )

    runner_plist = ROOT / "ios/Runner/Info.plist"
    tunnel_plist = ROOT / "ios/PacketTunnel/Info.plist"
    replace_plist_string(runner_plist, "CFBundleDisplayName", cfg["display_name"])
    replace_plist_string(runner_plist, "CFBundleName", cfg["display_name"])
    replace_plist_string(
        runner_plist, "NSLocalNetworkUsageDescription", cfg["local_network"]
    )
    replace_url_types(runner_plist, cfg["bundle_app"], cfg["url_scheme"])
    replace_plist_string(tunnel_plist, "CFBundleDisplayName", cfg["tunnel_name"])
    patch_pbxproj(
        ROOT / "ios/Runner.xcodeproj/project.pbxproj",
        cfg["bundle_app"],
        cfg["app_icon"],
    )

    print(f"Applied iOS brand={BRAND}")
    print(f"  app={cfg['bundle_app']}")
    print(f"  ext={cfg['bundle_ext']}")
    print(f"  group={cfg['app_group']}")
    print(
        f"  name={cfg['display_name']} icon={cfg['app_icon']} scheme={cfg['url_scheme']}"
    )


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:  # noqa: BLE001
        print(exc, file=sys.stderr)
        raise SystemExit(1) from exc
