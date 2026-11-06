import unittest
from validate_ipa import validate_bundle_info

class ArchiveContractTest(unittest.TestCase):
    def setUp(self):
        self.app = {"CFBundleIdentifier": "online.xplm.app", "CFBundleDisplayName": "X-Plm", "CFBundleVersion": "43", "CFBundleShortVersionString": "1.0.43"}
        self.ext = dict(self.app, CFBundleIdentifier="online.xplm.app.extension", NSExtension={"NSExtensionPointIdentifier": "com.apple.networkextension.packet-tunnel"})
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

if __name__ == "__main__": unittest.main()
