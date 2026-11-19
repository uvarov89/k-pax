#!/usr/bin/env python3
"""Validate app/extension identity and signing prerequisites in an exported IPA."""
import argparse
import plistlib
import re
import struct
import subprocess
import tempfile
import zipfile
from pathlib import Path

BRANDS = {"xplm": ("online.xplm.app", "X-Plm"), "kpax": ("space.kpax.app", "K-Pax")}
# Real Libbox Mach-O is tens of MB; symlink stubs in IPA zips are ~20 bytes.
MIN_LIBBOX_BYTES = 1_000_000
# Podfile / PacketTunnel / Libbox all target iOS 15; lower values risk TF install failures.
MIN_SUPPORTED_IOS = (15, 0)
# Mach-O / fat magics (native endian + swapped).
_MH_MAGIC_64 = 0xFEEDFACF
_MH_CIGAM_64 = 0xCFFAEDFE
_MH_MAGIC = 0xFEEDFACE
_MH_CIGAM = 0xCEFAEDFE
_FAT_MAGIC = 0xCAFEBABE
_FAT_CIGAM = 0xBEBAFECA
_CPU_TYPE_ARM64 = 0x0100000C
_CPU_TYPE_ARM64_SWAPPED = 0x0C000001


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


def _macho_mentions_arm64(data: bytes) -> bool:
    """True if bytes look like Mach-O / fat containing arm64 (no lipo needed)."""
    if len(data) < 8:
        return False
    magic = struct.unpack(">I", data[:4])[0]
    magic_le = struct.unpack("<I", data[:4])[0]
    if magic in (_FAT_MAGIC, _FAT_CIGAM) or magic_le in (_FAT_MAGIC, _FAT_CIGAM):
        swapped = magic == _FAT_CIGAM or magic_le == _FAT_CIGAM
        nfat = struct.unpack(">I" if not swapped else "<I", data[4:8])[0]
        off = 8
        for _ in range(min(nfat, 16)):
            if off + 20 > len(data):
                break
            fmt = ">II" if not swapped else "<II"
            cputype, _cpusub = struct.unpack(fmt, data[off : off + 8])
            if cputype in (_CPU_TYPE_ARM64, _CPU_TYPE_ARM64_SWAPPED):
                return True
            off += 20
        return False
    if magic_le in (_MH_MAGIC_64, _MH_MAGIC):
        cputype = struct.unpack("<I", data[4:8])[0]
        return cputype == _CPU_TYPE_ARM64
    if magic in (_MH_CIGAM_64, _MH_CIGAM) or magic_le in (_MH_CIGAM_64, _MH_CIGAM):
        cputype = struct.unpack(">I", data[4:8])[0]
        return cputype == _CPU_TYPE_ARM64
    return False


def assert_macho_arm64(path: Path, label: str | None = None) -> None:
    """ASC 90085: lipo must see arm64 in every bundle executable / Libbox dylib."""
    name = label or path.name
    assert path.is_file(), f"missing Mach-O for arch check: {name} ({path})"
    size = path.stat().st_size
    assert size >= 1024, f"{name} too small ({size} bytes) — ASC 90085"
    # Prefer lipo on macOS CI; fall back to header parse (Windows offline).
    lipo_err = "lipo unavailable"
    try:
        lipo = subprocess.run(
            ["lipo", "-info", str(path)],
            check=False,
            capture_output=True,
            text=True,
        )
        if lipo.returncode == 0:
            info = (lipo.stdout or lipo.stderr or "").strip()
            assert "arm64" in info, f"{name} has no arm64 (lipo: {info}) — ASC 90085"
            print(f"Mach-O arm64 OK: {name} ({info})")
            return
        lipo_err = (lipo.stderr or lipo.stdout or "").strip() or str(lipo.returncode)
    except FileNotFoundError:
        lipo_err = "lipo not found"
    data = path.read_bytes()[:4096]
    assert _macho_mentions_arm64(data), (
        f"{name} is not a readable arm64 Mach-O (lipo failed: {lipo_err}) — ASC 90085"
    )
    print(f"Mach-O arm64 OK: {name} (header parse; {lipo_err})")


def _resolve_libbox_binary(fw: Path, executable: str | None = None) -> Path | None:
    """Resolve the canonical Libbox Mach-O (with legacy-layout fallback).

    The caller rejects extra executable aliases before final IPA acceptance.
    """
    names: list[str] = []
    if executable:
        names.append(executable)
    names.extend(
        [
            "io.nekohasekai.libbox",
            "Libbox",  # may be a symlink stub (~20B) — skipped by size gate
        ]
    )
    candidates: list[Path] = []
    for name in names:
        candidates.extend(
            [
                fw / name,
                fw / "Versions" / "A" / name,
                fw / "Versions" / "Current" / name,
            ]
        )
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


def assert_single_libbox_executable(framework: Path) -> None:
    """Reject extra root-level Mach-O files in the iOS framework (ITMS-90171).

    A hardlink or copied Libbox binary with another filename is still an extra
    executable in the ZIP, regardless of whether it shares the inode locally.
    """
    executable = framework / "Libbox"
    assert executable.is_file() and not executable.is_symlink(), (
        "Libbox.framework must contain one regular executable named Libbox"
    )
    magics = {
        b"\xcf\xfa\xed\xfe",  # arm64 Mach-O
        b"\xfe\xed\xfa\xcf",
        b"\xca\xfe\xba\xbe",  # universal Mach-O
        b"\xbe\xba\xfe\xca",
    }
    executables = []
    for item in framework.iterdir():
        if item.is_dir() or item.is_symlink() or not item.is_file():
            continue
        with item.open("rb") as stream:
            if stream.read(4) in magics:
                executables.append(item.name)
    assert executables == ["Libbox"], (
        f"ITMS-90171: unexpected root-level Mach-O in Libbox.framework: {executables}"
    )


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
        bundle_id = info.get("CFBundleIdentifier")
        exec_name = info.get("CFBundleExecutable")
        assert bundle_id, "Libbox CFBundleIdentifier missing"
        assert exec_name, "Libbox CFBundleExecutable missing"
        # Apple: CFBundleExecutable is the framework's *filename*, Libbox.
        # CFBundleIdentifier is a separate reverse-DNS value and must NOT be
        # used as a second executable name (ITMS-90171).
        assert exec_name == "Libbox", (
            f"Libbox.framework CFBundleExecutable={exec_name!r}; "
            "expected Libbox, not CFBundleIdentifier"
        )
        assert info.get("CFBundlePackageType") == "FMWK", "Libbox CFBundlePackageType must be FMWK"
        assert_single_libbox_executable(fw)
        lib_bin = _resolve_libbox_binary(fw, str(exec_name))
        assert lib_bin is not None, (
            f"Libbox.framework in Runner but no real binary (>={MIN_LIBBOX_BYTES} bytes) under {fw}"
        )
        assert_macho_arm64(lib_bin, f"Libbox.framework/{exec_name}")
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
    """Check the signing identifier separately from executable filename.

    Framework executable is Libbox; its reverse-DNS signature identifier is
    supplied by CFBundleIdentifier.
    """
    info = plistlib.loads((framework / "Info.plist").read_bytes())
    expected = info["CFBundleIdentifier"]
    exec_name = info.get("CFBundleExecutable") or expected
    binary = framework / str(exec_name)
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
    """Must verify cleanly — sealed-resource failures cause device Unable to Install."""
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
        # ASC 90085: every bundle executable must still be a valid arm64 Mach-O.
        app_exec = app / str(app_plist.get("CFBundleExecutable") or app.stem)
        ext_exec = _extension_binary(extension, ext_plist)
        assert_macho_arm64(app_exec, f"Runner/{app_exec.name}")
        assert_macho_arm64(ext_exec, f"PacketTunnel/{ext_exec.name}")
        if signing:
            libbox = app / "Frameworks" / "Libbox.framework"
            if libbox.is_dir():
                validate_libbox_signature_identifier(libbox)
                _hard_codesign_verify(libbox)
                lib_bin = libbox / str(
                    plistlib.loads((libbox / "Info.plist").read_bytes()).get(
                        "CFBundleExecutable"
                    )
                    or "Libbox"
                )
                if lib_bin.is_file():
                    _hard_codesign_verify(lib_bin)
            # Framework signatures are nested and must match the distribution
            # identity after re-signing Runner (see ASC 90034).
            frameworks_dir = app / "Frameworks"
            if frameworks_dir.is_dir():
                for fw in sorted(frameworks_dir.glob("*.framework")):
                    _hard_codesign_verify(fw)
            # After post-IPA resign, host/appex must verify — soft-warn hid seal breaks.
            for path in (app, extension):
                _hard_codesign_verify(path)
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
