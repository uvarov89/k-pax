#!/usr/bin/env python3
"""Offline check: embed shell logic resolves slices and copies Libbox.framework."""
from __future__ import annotations

import os
import subprocess
import tempfile
import unittest
from pathlib import Path


SCRIPT = r"""
set -euo pipefail
XCFRAMEWORK="${PROJECT_DIR}/Frameworks/Libbox.xcframework"
SLICE=""
if [ "${PLATFORM_NAME:-}" = "iphonesimulator" ]; then
  for d in "$XCFRAMEWORK"/ios-*-simulator "$XCFRAMEWORK"/ios-arm64_x86_64-simulator; do
    if [ -d "$d/Libbox.framework" ]; then SLICE="$d"; break; fi
  done
else
  if [ -d "$XCFRAMEWORK/ios-arm64/Libbox.framework" ]; then
    SLICE="$XCFRAMEWORK/ios-arm64"
  else
    for d in "$XCFRAMEWORK"/ios-arm64*; do
      case "$d" in *simulator*) continue ;; esac
      if [ -d "$d/Libbox.framework" ]; then SLICE="$d"; break; fi
    done
  fi
fi
SRC="${SLICE}/Libbox.framework"
FFP="${FRAMEWORKS_FOLDER_PATH:-Frameworks}"
DEST_DIR="${TARGET_BUILD_DIR}/${FFP}"
DEST="${DEST_DIR}/Libbox.framework"
mkdir -p "$DEST_DIR"
rm -rf "$DEST"
cp -R "$SRC" "$DEST"
test -f "$DEST/Libbox"
echo OK
"""


class EmbedLibboxScriptTest(unittest.TestCase):
    def test_device_slice_copied_into_appex_frameworks(self) -> None:
        if os.name == "nt":
            sh = subprocess.run(["where", "bash"], capture_output=True, text=True)
            if sh.returncode != 0:
                self.skipTest("bash not available on Windows")
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            slice_dir = root / "Frameworks" / "Libbox.xcframework" / "ios-arm64" / "Libbox.framework"
            slice_dir.mkdir(parents=True)
            (slice_dir / "Libbox").write_bytes(b"fake-libbox-binary")
            target = root / "Build" / "PacketTunnel.appex"
            target.mkdir(parents=True)
            env = os.environ.copy()
            env.update(
                {
                    "PROJECT_DIR": str(root),
                    "PLATFORM_NAME": "iphoneos",
                    "TARGET_BUILD_DIR": str(target),
                    "FRAMEWORKS_FOLDER_PATH": "Frameworks",
                    "FULL_PRODUCT_NAME": "PacketTunnel.appex",
                }
            )
            subprocess.run(
                ["bash", "-c", SCRIPT],
                check=True,
                env=env,
                cwd=str(root),
            )
            dest = target / "Frameworks" / "Libbox.framework" / "Libbox"
            self.assertTrue(dest.is_file(), dest)
            self.assertEqual(dest.read_bytes(), b"fake-libbox-binary")


if __name__ == "__main__":
    unittest.main()
