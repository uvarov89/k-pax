#!/usr/bin/env python3
"""Offline proof: Libbox embeds into Runner only; appex must not contain Frameworks."""
from __future__ import annotations

import importlib.util
import re
import shutil
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SETUP = ROOT / "ios" / "scripts" / "setup_packet_tunnel.rb"
VALIDATE = ROOT / "ios" / "scripts" / "validate_ipa.py"


def _load_validate():
    spec = importlib.util.spec_from_file_location("validate_ipa", VALIDATE)
    mod = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    sys.modules["validate_ipa"] = mod
    spec.loader.exec_module(mod)
    return mod


def pick_slice(xcframework: Path, platform_name: str) -> Path | None:
    if platform_name == "iphonesimulator":
        candidates = sorted(xcframework.glob("ios-*-simulator")) + list(
            xcframework.glob("ios-arm64_x86_64-simulator")
        )
        for d in candidates:
            if (d / "Libbox.framework").is_dir():
                return d
        return None
    preferred = xcframework / "ios-arm64"
    if (preferred / "Libbox.framework").is_dir():
        return preferred
    for d in sorted(xcframework.glob("ios-arm64*")):
        if "simulator" in d.name:
            continue
        if (d / "Libbox.framework").is_dir():
            return d
    return None


def embed_copy(
    project_dir: Path,
    target_build_dir: Path,
    frameworks_folder_path: str,
    platform_name: str,
) -> Path:
    xc = project_dir / "Frameworks" / "Libbox.xcframework"
    slice_dir = pick_slice(xc, platform_name)
    if slice_dir is None:
        raise FileNotFoundError(f"no Libbox slice for {platform_name}")
    src = slice_dir / "Libbox.framework"
    dest_dir = target_build_dir / frameworks_folder_path
    dest = dest_dir / "Libbox.framework"
    dest_dir.mkdir(parents=True, exist_ok=True)
    if dest.exists():
        shutil.rmtree(dest)
    shutil.copytree(src, dest)
    binary = dest / "Libbox"
    if not binary.is_file():
        alt = dest / "Versions" / "Current" / "Libbox"
        if alt.is_file():
            binary = alt
    if not binary.is_file():
        raise FileNotFoundError(f"Libbox binary missing after copy in {dest}")
    return binary


class EmbedLibboxScriptTest(unittest.TestCase):
    def test_setup_rb_embeds_into_runner_not_appex(self) -> None:
        text = SETUP.read_text(encoding="utf-8")
        self.assertIn("Embed Libbox into Runner", text)
        self.assertIn("Strip Frameworks from PacketTunnel", text)
        self.assertIn("ASC 90206", text)
        self.assertIn("@executable_path/../../Frameworks", text)
        self.assertIn("ASC 90171", text)
        self.assertIn("normalize_libbox_framework.sh", text)
        self.assertIn("OK Libbox in Runner", text)
        self.assertNotIn("OK Embedded Libbox.framework", text)
        script = text.split("runner_phase.shell_script = <<~'SCRIPT'", 1)[-1].split("SCRIPT", 1)[0]
        self.assertIn("TARGET_BUILD_DIR", script)
        self.assertIn("FRAMEWORKS_FOLDER_PATH", script)
        self.assertIn("Resources/Info.plist", script)
        self.assertIn("--identifier=", script)
        self.assertIn("ASC 90334", script)
        self.assertIn("Libbox CFBundleIdentifier mismatch", script)
        self.assertIn("want Libbox", script)
        self.assertIn('BINARY="$DEST/Libbox"', script)
        self.assertIn("Re-sign Libbox identifiers", text)
        self.assertIn("after Thin Binary", text)
        self.assertNotIn("--preserve-metadata", script)
        resign = (ROOT / "ios" / "scripts" / "resign_libbox_in_ipa.sh").read_text(encoding="utf-8")
        self.assertIn("--identifier=", resign)
        self.assertIn("exportArchive", resign)
        self.assertIn("Apple Distribution", resign)
        self.assertIn("Renaming Mach-O", resign)
        self.assertIn("leftover short-name Mach-O", resign)
        self.assertIn("LC_LOAD_DYLIB", resign)
        self.assertIn("install_name_tool -change", resign)
        self.assertIn("CFBundleExecutable", resign)
        self.assertIn("codesign_identifier", resign)
        self.assertIn("--timestamp", resign)
        self.assertNotIn("--timestamp=none", resign)
        self.assertIn("--generate-entitlement-der", resign)
        self.assertIn("basename-proof", resign)
        norm = (ROOT / "ios" / "scripts" / "normalize_libbox_framework.sh").read_text(encoding="utf-8")
        self.assertIn("io.nekohasekai.libbox", norm)
        self.assertIn('LIBBOX_EXEC_NAME="Libbox"', norm)
        self.assertIn('CFBundleExecutable string "$LIBBOX_EXEC_NAME"', norm)
        self.assertIn("Keep Mach-O basename", norm)
        self.assertIn("resign_libbox_in_ipa.sh", norm)
        self.assertIn("ditto", norm)
        self.assertIn("relink_archive_to_dylib", norm)
        self.assertIn("-force_load", norm)
        self.assertIn("is_archive", norm)
        self.assertIn("clang++ -dynamiclib", norm)
        self.assertIn("UIKit", norm)
        self.assertIn("LIBBOX_NORMALIZE_SLICES", norm)
        self.assertIn("libbox_message_pump_kqueue_stub.cpp", norm)
        self.assertIn("prune_xcframework_slices", norm)
        self.assertIn("assert_xcframework_all_dylibs", norm)
        self.assertIn("CocoaPods rejects static+dynamic", norm)
        self.assertIn('marketing="${marketing#v}"', norm)
        self.assertIn("iris 90060", norm)
        self.assertIn("patch_resources_plist", norm)
        self.assertIn("ASC 90535", norm)
        self.assertIn("ASC 90334", norm)
        self.assertIn("BNDL", norm)
        self.assertIn("CFBundlePackageType string BNDL", norm)
        self.assertNotIn("io.nekohasekai.libbox.resources", norm)
        build = (ROOT / "ios" / "scripts" / "build_libbox.sh").read_text(encoding="utf-8")
        self.assertIn('LIBBOX_APPLE_PLATFORM:-ios}', build)
        self.assertIn("NORMALIZE_SLICES", build)
        self.assertIn("rm -rf", build)
        self.assertIn("Libbox.xcframework", build)

    def test_validate_ipa_requires_host_libbox_forbids_appex_frameworks(self) -> None:
        text = VALIDATE.read_text(encoding="utf-8")
        self.assertIn("assert_no_frameworks_in_appex", text)
        self.assertIn("assert_libbox_in_host_app", text)
        self.assertIn("MIN_LIBBOX_BYTES", text)
        self.assertIn(r"\d+(\.\d+){0,2}", text)
        self.assertIn("invalid for ASC", text)
        self.assertIn("ASC 90535", text)
        self.assertIn("BNDL", text)
        self.assertIn("validate_libbox_signature_identifier", text)
        self.assertIn("_codesign_identifier", text)
        self.assertIn("ASC 90334", text)
        self.assertIn("Unable to Install", text)
        self.assertIn("MIN_SUPPORTED_IOS", text)
        self.assertIn("_minimum_os_version", text)
        self.assertIn("_hard_codesign_verify", text)
        self.assertNotIn("_soft_codesign_verify", text)
        self.assertIn("Resources CFBundleIdentifier must match framework", text)
        self.assertIn("must equal", text)
        self.assertIn("short-name Mach-O", text)
        # Nested Mach-O resolved via CFBundleExecutable (basename-proof).
        self.assertIn("CFBundleExecutable", text)

    def test_device_slice_copied_into_runner_frameworks(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            slice_dir = (
                root / "Frameworks" / "Libbox.xcframework" / "ios-arm64" / "Libbox.framework"
            )
            slice_dir.mkdir(parents=True)
            (slice_dir / "Libbox").write_bytes(b"fake-libbox-binary")
            target = root / "Build" / "Products" / "Release-iphoneos" / "Runner.app"
            target.mkdir(parents=True)
            binary = embed_copy(
                project_dir=root,
                target_build_dir=target,
                frameworks_folder_path="Frameworks",
                platform_name="iphoneos",
            )
            self.assertEqual(binary.read_bytes(), b"fake-libbox-binary")

    def test_validate_rejects_appex_frameworks(self) -> None:
        validate = _load_validate()
        with tempfile.TemporaryDirectory() as tmp:
            appex = Path(tmp) / "PacketTunnel.appex"
            (appex / "Frameworks" / "Libbox.framework").mkdir(parents=True)
            (appex / "Frameworks" / "Libbox.framework" / "Libbox").write_bytes(b"x" * 1_500_000)
            with self.assertRaises(AssertionError) as ctx:
                validate.assert_no_frameworks_in_appex(appex)
            self.assertIn("90206", str(ctx.exception))

    def test_resolve_libbox_skips_symlink_stub(self) -> None:
        validate = _load_validate()
        with tempfile.TemporaryDirectory() as tmp:
            fw = Path(tmp) / "Libbox.framework"
            (fw / "Versions" / "A").mkdir(parents=True)
            (fw / "Libbox").write_bytes(b"Versions/Current/Libbox\n")
            real = fw / "Versions" / "A" / "Libbox"
            real.write_bytes(b"x" * 1_500_000)
            self.assertEqual(validate._resolve_libbox_binary(fw), real)

    def test_simulator_slice_preferred_for_simulator(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            device = (
                root / "Frameworks" / "Libbox.xcframework" / "ios-arm64" / "Libbox.framework"
            )
            device.mkdir(parents=True)
            (device / "Libbox").write_bytes(b"device")
            sim = (
                root
                / "Frameworks"
                / "Libbox.xcframework"
                / "ios-arm64-simulator"
                / "Libbox.framework"
            )
            sim.mkdir(parents=True)
            (sim / "Libbox").write_bytes(b"sim")
            target = root / "Runner.app"
            target.mkdir()
            binary = embed_copy(root, target, "Frameworks", "iphonesimulator")
            self.assertEqual(binary.read_bytes(), b"sim")


if __name__ == "__main__":
    unittest.main()
