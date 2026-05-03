#!/usr/bin/env python3
"""
Validates that the WebRTC.xcframework links correctly on tvOS.

Creates a minimal Swift file that imports WebRTC and instantiates
RTCPeerConnectionFactory, then compiles it against the tvOS device
and simulator slices. Exits non-zero if either compilation fails.

Usage:
    python3 validate_tvos.py <xcframework_path>
"""

import subprocess
import sys
import tempfile
from pathlib import Path

SWIFT_SOURCE = """\
import WebRTC
let factory = RTCPeerConnectionFactory()
print("RTCPeerConnectionFactory created: \\(factory)")
"""

TARGETS = [
    ("tvOS device", "arm64-apple-tvos15.0", "tvos-arm64"),
    ("tvOS simulator", "arm64-apple-tvos15.0-simulator", "tvos-arm64-simulator"),
]


def main() -> None:
    if len(sys.argv) != 2:
        print("Usage: validate_tvos.py <xcframework_path>")
        sys.exit(1)

    xcframework = Path(sys.argv[1])
    if not xcframework.is_dir():
        print(f"Error: xcframework not found at: {xcframework}")
        sys.exit(1)

    with tempfile.TemporaryDirectory() as tmp:
        swift_file = Path(tmp) / "webrtc_tvos_validate.swift"
        swift_file.write_text(SWIFT_SOURCE)

        for label, target, slice_dir in TARGETS:
            framework_dir = xcframework / slice_dir
            if not framework_dir.is_dir():
                print(f"Error: slice directory missing: {framework_dir}")
                sys.exit(1)

            print(f"Validating {label} ({target})...")
            subprocess.check_call([
                "xcrun", "swiftc",
                "-target", target,
                "-F", str(framework_dir),
                "-framework", "WebRTC",
                str(swift_file),
                "-o", "/dev/null",
            ])
            print(f"  ✅ {label} validation passed")

    print("✅ All tvOS validations passed")


if __name__ == "__main__":
    main()
