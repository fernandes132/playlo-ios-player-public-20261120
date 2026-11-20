"""Synthetic archives test rejection rules; these are never installable apps."""
import importlib.util
import plistlib
import struct
import tempfile
import unittest
import zipfile
from pathlib import Path

spec = importlib.util.spec_from_file_location("validator", Path(__file__).with_name("validate-ipa.py"))
validator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validator)


class ValidationTests(unittest.TestCase):
    def check_archive(self, cpu=0x0100000C, platform=2, supported="iPhoneOS", truncated=False):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "synthetic-test.zip"
            binary = struct.pack("<8I", 0xFEEDFACF, cpu, 0, 2, 1, 24, 0, 0)
            binary += struct.pack("<6I", 0x32, 24, platform, 0, 0, 0)
            if truncated:
                binary = binary[:-4]
            info = {"CFBundleIdentifier": "nl.playlo.app", "CFBundleExecutable": "Playlo",
                    "CFBundleSupportedPlatforms": [supported], "MinimumOSVersion": "16.0"}
            with zipfile.ZipFile(path, "w") as archive:
                archive.writestr("Payload/Playlo.app/Info.plist", plistlib.dumps(info))
                archive.writestr("Payload/Playlo.app/Playlo", binary)
            return validator.validate(path)

    def test_device_header(self):
        self.assertEqual(self.check_archive()["architecture"], "arm64")

    def test_simulator_plist_rejected(self):
        with self.assertRaisesRegex(ValueError, "device build"):
            self.check_archive(supported="iPhoneSimulator")

    def test_arm64_simulator_binary_rejected(self):
        with self.assertRaisesRegex(ValueError, "not built for iOS"):
            self.check_archive(platform=7)

    def test_wrong_architecture_rejected(self):
        with self.assertRaisesRegex(ValueError, "arm64"):
            self.check_archive(cpu=0x01000007)

    def test_truncated_binary_rejected(self):
        with self.assertRaisesRegex(ValueError, "Truncated"):
            self.check_archive(truncated=True)


if __name__ == "__main__":
    unittest.main()
