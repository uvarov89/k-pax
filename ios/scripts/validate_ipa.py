#!/usr/bin/env python3
"""Validate app/extension identity and signing prerequisites in an exported IPA."""
import argparse
import plistlib
import subprocess
import tempfile
import zipfile
from pathlib import Path

BRANDS = {"xplm": ("online.xplm.app", "X-Plm"), "kpax": ("space.kpax.app", "K-Pax")}

def validate_bundle_info(app, extension, brand):
    bundle, name = BRANDS[brand]
    assert app.get("CFBundleIdentifier") == bundle, "Wrong application Bundle ID"
    assert app.get("CFBundleDisplayName") == name, "Wrong application name"
    assert extension.get("CFBundleIdentifier") == bundle + ".extension", "Wrong extension Bundle ID"
    for key in ("CFBundleVersion", "CFBundleShortVersionString"):
        value = app.get(key)
        assert value and "$" not in str(value), f"Unresolved app version: {key}"
        assert extension.get(key) == value, f"App/extension version mismatch: {key}"
    assert extension.get("NSExtension", {}).get("NSExtensionPointIdentifier") == "com.apple.networkextension.packet-tunnel", "Not a Packet Tunnel extension"

def validate_signing(path, bundle):
    result = subprocess.run(["security", "cms", "-D", "-i", str(path / "embedded.mobileprovision")], check=True, capture_output=True)
    profile = plistlib.loads(result.stdout)
    signed = subprocess.run(["codesign", "-d", "--entitlements", ":-", str(path)], check=True, capture_output=True)
    entitlements = plistlib.loads(signed.stdout)
    for values in (profile["Entitlements"], entitlements):
        assert "group." + bundle in values.get("com.apple.security.application-groups", []), "Missing App Group"
        assert "packet-tunnel-provider" in values.get("com.apple.developer.networking.networkextension", []), "Missing Packet Tunnel entitlement"
    return entitlements.get("com.apple.developer.team-identifier")

def _extension_binary(extension: Path, ext_plist: dict) -> Path:
    name = ext_plist.get("CFBundleExecutable") or extension.stem
    return extension / name

def assert_libbox_in_extension(extension: Path, ext_plist: dict) -> None:
    frameworks = extension / "Frameworks"
    if frameworks.is_dir() and list(frameworks.glob("Libbox.framework")):
        print("Libbox.framework present in PacketTunnel.appex/Frameworks")
        return
    binary = _extension_binary(extension, ext_plist)
    if binary.is_file():
        linked = subprocess.run(
            ["otool", "-L", str(binary)],
            check=False,
            capture_output=True,
            text=True,
        )
        if linked.returncode == 0 and "Libbox" in linked.stdout:
            print("Libbox linked into PacketTunnel binary (no separate Frameworks copy)")
            return
    raise AssertionError("Libbox not embedded/linked in PacketTunnel.appex")

def validate_archive(ipa, brand, signing=True):
    with tempfile.TemporaryDirectory(prefix="ios-archive-check-") as temp:
        with zipfile.ZipFile(ipa) as archive:
            archive.extractall(temp)
        apps = list((Path(temp) / "Payload").glob("*.app"))
        assert len(apps) == 1, "Expected exactly one app"
        app = apps[0]
        extensions = list((app / "PlugIns").glob("*.appex"))
        assert len(extensions) == 1, "Expected exactly one VPN extension"
        extension = extensions[0]
        app_plist = plistlib.loads((app / "Info.plist").read_bytes())
        ext_plist = plistlib.loads((extension / "Info.plist").read_bytes())
        validate_bundle_info(app_plist, ext_plist, brand)
        assert_libbox_in_extension(extension, ext_plist)
        if signing:
            # Avoid --deep/--strict: nested gomobile frameworks often trip
            # "sealed resource is missing or invalid" even on valid TestFlight IPAs.
            for path in (app, extension):
                subprocess.run(["codesign", "--verify", str(path)], check=True)
            bundle = BRANDS[brand][0]
            app_team = validate_signing(app, bundle)
            extension_team = validate_signing(extension, bundle)
            assert app_team and app_team == extension_team, "Signing team mismatch"
    print(f"IPA identity, versions and signing verified: {brand}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--brand", required=True, choices=BRANDS)
    parser.add_argument("ipa", type=Path)
    args = parser.parse_args()
    validate_archive(args.ipa, args.brand)
