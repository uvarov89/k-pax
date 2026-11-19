import struct
import tempfile
import unittest
from pathlib import Path

from validate_ipa import (
    _CPU_TYPE_ARM64,
    _MH_MAGIC_64,
    _macho_mentions_arm64,
    assert_macho_arm64,
    assert_single_libbox_executable,
    assert_libbox_info_plist_seal,
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


class FrameworkStructureRegressionTest(unittest.TestCase):
    """Reproduces the ITMS-90171 duplicate Mach-O in K-Pax 1.0.68."""

    def test_single_canonical_executable_is_accepted(self):
        with tempfile.TemporaryDirectory() as tmp:
            fw = Path(tmp) / "Libbox.framework"
            fw.mkdir()
            (fw / "Libbox").write_bytes(
                struct.pack("<II", _MH_MAGIC_64, _CPU_TYPE_ARM64)
            )
            assert_single_libbox_executable(fw)

    def test_extra_executable_is_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            fw = Path(tmp) / "Libbox.framework"
            fw.mkdir()
            binary = fw / "Libbox"
            binary.write_bytes(struct.pack("<II", _MH_MAGIC_64, _CPU_TYPE_ARM64))
            (fw / "io.nekohasekai.libbox").write_bytes(binary.read_bytes())
            with self.assertRaisesRegex(AssertionError, "ITMS-90171"):
                assert_single_libbox_executable(fw)

    def test_symlink_executable_is_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            fw = Path(tmp) / "Libbox.framework"
            fw.mkdir()
            (fw / "io.nekohasekai.libbox").write_bytes(
                struct.pack("<II", _MH_MAGIC_64, _CPU_TYPE_ARM64)
            )
            (fw / "Libbox").symlink_to("io.nekohasekai.libbox")
            with self.assertRaises(AssertionError):
                assert_single_libbox_executable(fw)



class SignedInfoPlistRegressionTest(unittest.TestCase):
    """Regression for K-Pax 1.0.73 TestFlight install failure."""

    def _write_fake_libbox(self, fw: Path, sealed_plist: bytes) -> None:
        import hashlib
        fw.mkdir(parents=True)
        directory = bytearray(80)
        struct.pack_into(">I", directory, 0, 0xFADE0C02)
        struct.pack_into(">I", directory, 4, len(directory))
        struct.pack_into(">I", directory, 16, 80)  # hashOffset
        struct.pack_into(">I", directory, 24, 1)   # one special slot
        directory[36], directory[37] = 32, 2      # SHA-256
        directory[48:80] = hashlib.sha256(sealed_plist).digest()
        signature = struct.pack(">III", 0xFADE0CC0, 20 + len(directory), 1)
        signature += struct.pack(">II", 0, 20) + directory
        header = bytearray(32)
        struct.pack_into("<I", header, 0, _MH_MAGIC_64)
        struct.pack_into("<I", header, 16, 1)  # ncmds
        command = struct.pack("<IIII", 0x1D, 16, 48, len(signature))
        (fw / "Libbox").write_bytes(header + command + signature)

    def test_correct_root_plist_seal_passes(self):
        with tempfile.TemporaryDirectory() as tmp:
            fw = Path(tmp) / "Libbox.framework"
            info = b"canonical root plist"
            self._write_fake_libbox(fw, info)
            (fw / "Info.plist").write_bytes(info)
            assert_libbox_info_plist_seal(fw)

    def test_old_resources_plist_seal_is_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            fw = Path(tmp) / "Libbox.framework"
            self._write_fake_libbox(fw, b"old BNDL Resources/Info.plist")
            (fw / "Info.plist").write_bytes(b"correct FMWK root Info.plist")
            with self.assertRaisesRegex(AssertionError, "slot -1"):
                assert_libbox_info_plist_seal(fw)


if __name__ == "__main__": unittest.main()
