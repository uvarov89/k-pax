#!/usr/bin/env python3
"""Offline proof: embed path + slice pick match setup_packet_tunnel.rb (no bash/Xcode)."""
from __future__ import annotations

import re
import shutil
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SETUP = ROOT / "ios" / "scripts" / "setup_packet_tunnel.rb"
VALIDATE = ROOT / "ios" / "scripts" / "validate_ipa.py"


def pick_slice(xcframework: Path, platform_name: str) -> Path | None:
    """Mirror the shell slice logic from Embed Libbox into PacketTunnel."""
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
    def test_setup_rb_uses_target_build_dir_and_hard_fails(self) -> None:
        text = SETUP.read_text(encoding="utf-8")
        self.assertIn("TARGET_BUILD_DIR", text)
        self.assertIn("FRAMEWORKS_FOLDER_PATH", text)
        self.assertIn('abort "Missing #{FRAMEWORKS}', text)
        self.assertIn("Libbox binary missing after copy", text)
        self.assertIn("Embed Libbox into PacketTunnel", text)
        # Only the shell phase matters — comments may mention the bad flag.
        script = text.split("phase.shell_script = <<~'SCRIPT'", 1)[-1].split("SCRIPT", 1)[0]
        self.assertNotIn("--preserve-metadata", script)
        self.assertIn('codesign --force --sign "$IDENTITY" --timestamp=none "$BINARY"', script)
        self.assertIn("codesign --verify", script)
        # Must not rely on Copy Files / Code Sign On Copy for Libbox.
        self.assertNotRegex(
            text,
            r"Embed Frameworks.*Libbox\.xcframework.*CodeSignOnCopy",
        )
        # Shell phase must be moved last.
        self.assertIn("phases << phase", text)
        # DEST must be under TARGET_BUILD_DIR (CocoaPods style), not only BUILT_PRODUCTS_DIR.
        m = re.search(
            r'DEST_DIR="\$\{TARGET_BUILD_DIR\}/\$\{FFP\}"',
            text,
        )
        self.assertIsNotNone(m, "DEST_DIR must use TARGET_BUILD_DIR/FFP")

    def test_validate_ipa_requires_libbox_binary(self) -> None:
        text = VALIDATE.read_text(encoding="utf-8")
        self.assertIn("assert_libbox_in_extension", text)
        self.assertIn("Libbox.framework", text)
        self.assertIn("Libbox not embedded", text)

    def test_device_slice_copied_into_appex_frameworks(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            slice_dir = (
                root / "Frameworks" / "Libbox.xcframework" / "ios-arm64" / "Libbox.framework"
            )
            slice_dir.mkdir(parents=True)
            (slice_dir / "Libbox").write_bytes(b"fake-libbox-binary")
            # Also plant a simulator slice that must NOT be picked for iphoneos.
            sim = (
                root
                / "Frameworks"
                / "Libbox.xcframework"
                / "ios-arm64-simulator"
                / "Libbox.framework"
            )
            sim.mkdir(parents=True)
            (sim / "Libbox").write_bytes(b"simulator-binary")

            # CocoaPods-style: TARGET_BUILD_DIR is the .appex itself.
            target = root / "Build" / "Products" / "Release-iphoneos" / "PacketTunnel.appex"
            target.mkdir(parents=True)

            binary = embed_copy(
                project_dir=root,
                target_build_dir=target,
                frameworks_folder_path="Frameworks",
                platform_name="iphoneos",
            )
            self.assertEqual(binary.read_bytes(), b"fake-libbox-binary")
            dest = target / "Frameworks" / "Libbox.framework" / "Libbox"
            self.assertTrue(dest.is_file(), dest)
            self.assertEqual(dest.read_bytes(), b"fake-libbox-binary")

    def test_correct_dest_is_inside_appex_not_products_sibling(self) -> None:
        """validate_ipa only accepts appex/Frameworks/Libbox — not Products/Frameworks."""
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            slice_dir = (
                root / "Frameworks" / "Libbox.xcframework" / "ios-arm64" / "Libbox.framework"
            )
            slice_dir.mkdir(parents=True)
            (slice_dir / "Libbox").write_bytes(b"bin")

            products = root / "DerivedData" / "Build" / "Products" / "Release-iphoneos"
            target = products / "PacketTunnel.appex"
            target.mkdir(parents=True)
            orphan = products / "Frameworks" / "Libbox.framework"
            orphan.mkdir(parents=True)
            (orphan / "Libbox").write_bytes(b"orphan")

            embed_copy(
                project_dir=root,
                target_build_dir=target,
                frameworks_folder_path="Frameworks",
                platform_name="iphoneos",
            )
            inside = target / "Frameworks" / "Libbox.framework" / "Libbox"
            self.assertEqual(inside.read_bytes(), b"bin")
            self.assertEqual((orphan / "Libbox").read_bytes(), b"orphan")
            # IPA layout check equivalent: extension/Frameworks must contain Libbox.
            self.assertTrue((target / "Frameworks" / "Libbox.framework").is_dir())

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
            target = root / "PacketTunnel.appex"
            target.mkdir()
            binary = embed_copy(root, target, "Frameworks", "iphonesimulator")
            self.assertEqual(binary.read_bytes(), b"sim")


if __name__ == "__main__":
    unittest.main()
