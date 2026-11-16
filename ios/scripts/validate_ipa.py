#!/usr/bin/env python3
"""Validate app/extension identity and signing prerequisites in an exported IPA."""
import argparse
import plistlib
import re
import subprocess
import tempfile
import zipfile
from pathlib import Path

BRANDS = {"xplm": ("online.xplm.app", "X-Plm"), "kpax": ("space.kpax.app", "K-Pax")}
# Real Libbox Mach-O is tens of MB; symlink stubs in IPA zips are ~20 bytes.
MIN_LIBBOX_BYTES = 1_000_000
# Podfile / PacketTunnel / Libbox all target iOS 15; lower values risk TF install failures.
MIN_SUPPORTED_IOS = (15, 0)


def _parse_ios_version(raw) -> tuple[int, ...]:
    text = str(raw or "").strip()
    assert re.fullmatch(r"\d+(\.\d+)*", text), f"Invalid MinimumOSVersion: {raw!r}"
    return tuple(int(part) for part in text.split("."))


def _minimum_os_version(plist: dict) -> tuple[int, ...]:
    raw = plist.get("MinimumOSVersion") or plist.get("LSMinimumSystemVersion")
    assert raw, "MinimumOSVersion missing"
    return _parse_ios_version(raw)


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
    app_min = _minimum_os_version(app)
    ext_min = _minimum_os_version(extension)
    assert app_min >= MIN_SUPPORTED_IOS, f"App MinimumOSVersion {app_min} below {MIN_SUPPORTED_IOS}"
    assert ext_min >= MIN_SUPPORTED_IOS, f"Extension MinimumOSVersion {ext_min} below {MIN_SUPPORTED_IOS}"
    assert app_min == ext_min, f"App/extension MinimumOSVersion mismatch: {app_min} vs {ext_min}"


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


def _resolve_libbox_binary(fw: Path) -> Path | None:
    """Prefer a real Mach-O over a root symlink stub left by versioned frameworks."""
    candidates = [
        fw / "Libbox",
        fw / "Versions" / "A" / "Libbox",
        fw / "Versions" / "Current" / "Libbox",
    ]
    found: list[Path] = []
    for cand in candidates:
        if not cand.exists():
            continue
        try:
            size = cand.stat().st_size
        except OSError:
            continue
        if size < MIN_LIBBOX_BYTES:
            continue
        found.append(cand)
    if not found:
        return None
    return max(found, key=lambda p: p.stat().st_size)


def assert_no_frameworks_in_appex(extension: Path) -> None:
    """ASC 90205/90206: app extensions must not contain a Frameworks directory."""
    frameworks = extension / "Frameworks"
    if frameworks.exists():
        listing = sorted(p.relative_to(frameworks).as_posix() for p in frameworks.rglob("*") if p.is_file())
        raise AssertionError(
            "PacketTunnel.appex must not contain Frameworks/ (ASC 90206). Found:\n"
            + "\n".join(listing[:40])
        )
    print("PacketTunnel.appex has no Frameworks/ (ASC OK)")


def assert_libbox_in_host_app(app: Path, extension: Path, ext_plist: dict) -> None:
    frameworks = app / "Frameworks"
    embedded = list(frameworks.glob("Libbox.framework")) if frameworks.is_dir() else []
    if embedded:
        fw = embedded[0]
        lib_bin = _resolve_libbox_binary(fw)
        assert lib_bin is not None, (
            f"Libbox.framework in Runner but no real binary (>={MIN_LIBBOX_BYTES} bytes) under {fw}"
        )
        plist_path = fw / "Info.plist"
        assert plist_path.is_file(), f"Libbox.framework missing Info.plist: {fw}"
        resources_plist_path = fw / "Resources" / "Info.plist"
        assert resources_plist_path.is_file(), (
            "Libbox.framework missing Resources/Info.plist (ASC 90171 risk)"
        )
        assert not (fw / "Versions").exists(), (
            "Libbox.framework still has Versions/ — must be shallow for iOS ASC"
        )
        info = plistlib.loads(plist_path.read_bytes())
        assert info.get("CFBundleIdentifier"), "Libbox CFBundleIdentifier missing"
        assert info.get("CFBundleExecutable") == "Libbox", (
            f"Libbox CFBundleExecutable={info.get('CFBundleExecutable')!r}"
        )
        assert info.get("CFBundlePackageType") == "FMWK", "Libbox CFBundlePackageType must be FMWK"
        assert info.get("CFBundleVersion"), "Libbox CFBundleVersion missing"
        short_ver = str(info.get("CFBundleShortVersionString") or "")
        assert short_ver, "Libbox CFBundleShortVersionString missing"
        # ASC iris 90060: at most three non-negative integers, no leading "v".
        assert re.fullmatch(r"\d+(\.\d+){0,2}", short_ver), (
            f"Libbox CFBundleShortVersionString invalid for ASC: {short_ver!r}"
        )
        libbox_min = _minimum_os_version(info)
        assert libbox_min >= MIN_SUPPORTED_IOS, (
            f"Libbox MinimumOSVersion {libbox_min} below {MIN_SUPPORTED_IOS}"
        )
        # ASC 90535: nested Resources bundle must not declare CFBundleExecutable.
        resources_info = plistlib.loads(resources_plist_path.read_bytes())
        assert "CFBundleExecutable" not in resources_info, (
            "Libbox Resources/Info.plist must not contain CFBundleExecutable (ASC 90535)"
        )
        assert resources_info.get("CFBundlePackageType") == "BNDL", (
            "Libbox Resources/Info.plist CFBundlePackageType must be BNDL (ASC 90535)"
        )
        # ASC 90334: nested Resources CFBundleIdentifier must match the framework id.
        assert resources_info.get("CFBundleIdentifier") == info.get("CFBundleIdentifier"), (
            "Libbox Resources CFBundleIdentifier must match framework "
            f"(got {resources_info.get('CFBundleIdentifier')!r} vs {info.get('CFBundleIdentifier')!r})"
        )
        size = lib_bin.stat().st_size
        print(f"Libbox.framework OK in Runner.app ({lib_bin.relative_to(app)}, {size} bytes)")
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
            print("Libbox linked into PacketTunnel binary (static / no separate Frameworks copy)")
            print(linked.stdout)
            return
    listing = []
    app_fw = app / "Frameworks"
    if app_fw.is_dir():
        for p in sorted(app_fw.rglob("*")):
            if p.is_file():
                listing.append(f"{p.relative_to(app)} ({p.stat().st_size})")
    raise AssertionError(
        "Libbox.framework missing from Runner.app/Frameworks (required for PacketTunnel rpath)\n"
        f"Runner Frameworks preview:\n" + "\n".join(listing[:80])
    )


def _codesign_identifier(path: Path) -> str | None:
    result = subprocess.run(
        ["codesign", "-d", "--verbose=4", str(path)],
        check=True,
        capture_output=True,
        text=True,
    )
    return next(
        (
            line.removeprefix("Identifier=")
            for line in result.stderr.splitlines()
            if line.startswith("Identifier=")
        ),
        None,
    )


def validate_libbox_signature_identifier(framework: Path) -> None:
    """Outer bundle AND nested Mach-O must match CFBundleIdentifier (ASC 90334).

    exportArchive often re-stamps Libbox.framework/Libbox with basename "Libbox"
    while the .framework still reports the plist id — device Unable to Install.
    """
    info = plistlib.loads((framework / "Info.plist").read_bytes())
    expected = info["CFBundleIdentifier"]
    binary = framework / "Libbox"
    targets = [framework]
    if binary.is_file():
        targets.append(binary)
    for path in targets:
        actual = _codesign_identifier(path)
        assert actual == expected, (
            f"{path.name} signature identifier {actual!r} must match "
            f"{expected!r} (ASC 90334 / Unable to Install)"
        )
        print(f"Libbox codesign Identifier OK: {path.name}={actual}")


def _hard_codesign_verify(path: Path) -> None:
    """Libbox must verify cleanly — sealed-resource failures cause device Unable to Install."""
    result = subprocess.run(
        ["codesign", "--verify", "--verbose=4", str(path)],
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode == 0:
        print(f"codesign --verify OK: {path.name}")
        return
    detail = (result.stderr or result.stdout or "").strip()
    raise AssertionError(f"codesign --verify failed for {path}: {detail}")


def _soft_codesign_verify(path: Path) -> None:
    """Host app/appex can trip sealed-resource on otherwise valid Flutter IPAs."""
    result = subprocess.run(
        ["codesign", "--verify", str(path)],
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode == 0:
        print(f"codesign --verify OK: {path.name}")
        return
    detail = (result.stderr or result.stdout or "").strip()
    if "sealed resource is missing or invalid" in detail:
        print(f"codesign --verify soft-warn {path.name}: {detail}")
        return
    raise AssertionError(f"codesign --verify failed for {path}: {detail}")


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
        assert_no_frameworks_in_appex(extension)
        assert_libbox_in_host_app(app, extension, ext_plist)
        if signing:
            libbox = app / "Frameworks" / "Libbox.framework"
            if libbox.is_dir():
                validate_libbox_signature_identifier(libbox)
                _hard_codesign_verify(libbox)
            for path in (app, extension):
                _soft_codesign_verify(path)
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
