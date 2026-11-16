import struct
import tempfile
import unittest
from pathlib import Path

from validate_ipa import (
    _CPU_TYPE_ARM64,
    _MH_MAGIC_64,
    _macho_mentions_arm64,
    assert_macho_arm64,
    validate_bundle_info,
)


class MachOArm64ContractTest(unittest.TestCase):
    def test_thin_arm64_header_detected(self):
        # Minimal little-endian MH_MAGIC_64 + CPU_TYPE_ARM64 header.
        header = struct.pack("<II", _MH_MAGIC_64, _CPU_TYPE_ARM64) + b"\x00" * 64
        self.assertTrue(_macho_mentions_arm64(header))

    def test_non_macho_rejected(self):
        self.assertFalse(_macho_mentions_arm64(b"not a macho binary!!!!"))

    def test_assert_macho_arm64_accepts_synthetic(self):
        header = struct.pack("<II", _MH_MAGIC_64, _CPU_TYPE_ARM64) + b"\x00" * 2048
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "fake"
            path.write_bytes(header)
            assert_macho_arm64(path, "synthetic")


class ArchiveContractTest(unittest.TestCase):
    def setUp(self):
        self.app = {
            "CFBundleIdentifier": "online.xplm.app",
            "CFBundleDisplayName": "X-Plm",
            "CFBundleVersion": "43",
            "CFBundleShortVersionString": "1.0.43",
            "MinimumOSVersion": "15.0",
        }
        self.ext = dict(
            self.app,
            CFBundleIdentifier="online.xplm.app.extension",
            NSExtension={"NSExtensionPointIdentifier": "com.apple.networkextension.packet-tunnel"},
        )
    def test_matching_app_and_extension(self):
        validate_bundle_info(self.app, self.ext, "xplm")
    def test_wrong_brand_rejected(self):
        with self.assertRaises(AssertionError): validate_bundle_info(self.app, self.ext, "kpax")
    def test_extension_version_mismatch_rejected(self):
        self.ext["CFBundleVersion"] = "1"
        with self.assertRaises(AssertionError): validate_bundle_info(self.app, self.ext, "xplm")
    def test_unresolved_version_rejected(self):
        self.app["CFBundleVersion"] = "$(FLUTTER_BUILD_NUMBER)"
        self.ext["CFBundleVersion"] = self.app["CFBundleVersion"]
        with self.assertRaises(AssertionError): validate_bundle_info(self.app, self.ext, "xplm")
    def test_minimum_os_too_low_rejected(self):
        self.app["MinimumOSVersion"] = "13.0"
        self.ext["MinimumOSVersion"] = "13.0"
        with self.assertRaises(AssertionError): validate_bundle_info(self.app, self.ext, "xplm")
    def test_minimum_os_mismatch_rejected(self):
        self.ext["MinimumOSVersion"] = "16.0"
        with self.assertRaises(AssertionError): validate_bundle_info(self.app, self.ext, "xplm")

if __name__ == "__main__": unittest.main()
