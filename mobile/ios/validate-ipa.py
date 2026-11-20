"""Validate the actual iPhone binary and produce downloadable build evidence."""
import hashlib
import json
import plistlib
import struct
import sys
import zipfile
from pathlib import Path


def validate(path):
    path = Path(path)
    with zipfile.ZipFile(path) as archive:
        if archive.testzip() is not None:
            raise ValueError("Corrupt IPA member")
        prefix = "Payload/Playlo.app/"
        info = plistlib.loads(archive.read(prefix + "Info.plist"))
        if info.get("CFBundleIdentifier") != "nl.playlo.app":
            raise ValueError("Unexpected bundle identifier")
        if info.get("CFBundleSupportedPlatforms") != ["iPhoneOS"]:
            raise ValueError("IPA must contain an iPhoneOS device build")
        if info.get("CFBundleExecutable") != "Playlo":
            raise ValueError("Unexpected app executable")
        binary = archive.read(prefix + "Playlo")
        # The generic iphoneos build produces a thin little-endian arm64 Mach-O.
        if len(binary) < 32:
            raise ValueError("Missing Mach-O header")
        magic, cpu, _, filetype, commands, command_bytes, _, _ = struct.unpack_from("<8I", binary)
        if (magic, cpu, filetype) != (0xFEEDFACF, 0x0100000C, 2):
            raise ValueError("Expected executable arm64 Mach-O")
        end = 32 + command_bytes
        if end > len(binary):
            raise ValueError("Truncated Mach-O load commands")
        offset = 32
        device_platform = False
        for _ in range(commands):
            if offset + 8 > end:
                raise ValueError("Missing load command")
            command, size = struct.unpack_from("<2I", binary, offset)
            if size < 8 or offset + size > end:
                raise ValueError("Invalid load command size")
            if command == 0x32 and size >= 24:  # LC_BUILD_VERSION
                platform = struct.unpack_from("<I", binary, offset + 8)[0]
                if platform != 2:  # PLATFORM_IOS; simulator is 7
                    raise ValueError("Binary is not built for iOS devices")
                device_platform = True
            offset += size
        if not device_platform or offset != end:
            raise ValueError("Missing iOS device build metadata")
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    result = {
        "filename": path.name, "bytes": path.stat().st_size, "sha256": digest,
        "bundle_id": info["CFBundleIdentifier"], "architecture": "arm64",
        "platform": "iPhoneOS", "minimum_ios": info.get("MinimumOSVersion"),
        "installation_tested": False, "signing": "Sign and install using iLoader",
    }
    return result


if __name__ == "__main__":
    ipa = Path(sys.argv[1])
    report = validate(ipa)
    Path(str(ipa) + ".validation.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    Path(str(ipa) + ".sha256").write_text(report["sha256"] + "  " + ipa.name + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2))
