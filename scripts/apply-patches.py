#!/usr/bin/env python3
"""
Applies source patches to the WebRTC tree for tvOS compatibility.

Run after `gclient sync` and before `ninja` builds.

The tvOS build uses target_os="ios" in GN, so WEBRTC_IOS is defined at
compile time. We use TARGET_OS_TV (from <TargetConditionals.h>) to
distinguish tvOS from real iOS. Three strategies:

1. guard_file: wrap entire file in #if !TARGET_OS_TV / #endif
2. patch_webrtc_ios_guards: add && !TARGET_OS_TV to all WEBRTC_IOS guards
3. Surgical line-level patches for files needing selective changes
"""

import os
import re
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
SRC_DIR = SCRIPT_DIR.parent / "src"


def read_file(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="surrogateescape")


def write_file(path: Path, content: str) -> None:
    path.write_text(content, encoding="utf-8", errors="surrogateescape")


# ------------------------------------------------------------------
# Strategy 1: wrap entire file in #if !TARGET_OS_TV
# ------------------------------------------------------------------
def guard_file(rel_path: str) -> None:
    path = SRC_DIR / rel_path
    if not path.exists():
        return
    content = read_file(path)
    if "TARGET_OS_TV" in content:
        return
    guarded = (
        "#include <TargetConditionals.h>\n"
        "#if !TARGET_OS_TV\n"
        + content
        + "\n#endif  // !TARGET_OS_TV\n"
    )
    write_file(path, guarded)
    print(f"  Guarded {path.name}")


# ------------------------------------------------------------------
# Strategy 2: patch every WEBRTC_IOS guard to add && !TARGET_OS_TV
# ------------------------------------------------------------------
def patch_webrtc_ios_guards(rel_path: str) -> None:
    """Add && !TARGET_OS_TV to all WEBRTC_IOS preprocessor guards.

    Also inserts #include <TargetConditionals.h> after the first
    #import or #include directive.
    """
    path = SRC_DIR / rel_path
    if not path.exists():
        return
    content = read_file(path)
    if "TARGET_OS_TV" in content:
        return

    # Insert TargetConditionals.h after the first #import or #include
    inserted = False
    lines = content.split("\n")
    out: list[str] = []
    for line in lines:
        out.append(line)
        if not inserted and re.match(r"^#(import|include)\s", line):
            out.append("#include <TargetConditionals.h>")
            inserted = True
    content = "\n".join(out)

    # Patch all forms of WEBRTC_IOS guards
    content = content.replace(
        "#if defined(WEBRTC_IOS)",
        "#if defined(WEBRTC_IOS) && !TARGET_OS_TV",
    )
    content = content.replace(
        "#ifdef WEBRTC_IOS",
        "#if defined(WEBRTC_IOS) && !TARGET_OS_TV",
    )
    content = content.replace(
        "#elif defined(WEBRTC_IOS)",
        "#elif defined(WEBRTC_IOS) && !TARGET_OS_TV",
    )

    write_file(path, content)
    print(f"  Patched WEBRTC_IOS guards in {path.name}")


# ------------------------------------------------------------------
# Strategy 3: surgical per-file patches
# ------------------------------------------------------------------
def patch_audio_device_impl() -> None:
    """Patch modules/audio_device/audio_device_impl.cc for tvOS.

    This file has an #elif chain: WEBRTC_IOS -> WEBRTC_MAC.
    On tvOS both are defined. We need to:
      - Guard the #include of audio_device_ios.h (guarded empty on tvOS)
      - Guard the #include of audio_device_mac.h (CoreAudio not on tvOS)
      - Guard the iOS ADM creation (AudioDeviceIOS uses guarded code)
      - Guard the Mac ADM creation (AudioDeviceMac needs CoreAudio)
      - KEEP the platform detection (tvOS should report kPlatformIOS)
      - KEEP GetPlayoutAudioParameters (base class methods, fine on tvOS)
    """
    path = SRC_DIR / "modules/audio_device/audio_device_impl.cc"
    if not path.exists():
        return
    content = read_file(path)
    if "TARGET_OS_TV" in content:
        return

    lines = content.split("\n")
    out: list[str] = []
    # Insert TargetConditionals.h at the very top
    out.append("#include <TargetConditionals.h>")

    i = 0
    while i < len(lines):
        line = lines[i]

        # --- Guard the iOS include ---
        if line.strip() == '#include "sdk/objc/native/src/audio/audio_device_ios.h"':
            out.append("#if !TARGET_OS_TV")
            out.append(line)
            out.append("#endif")
            i += 1
            continue

        # --- Guard the Mac include ---
        if line.strip() == '#include "modules/audio_device/mac/audio_device_mac.h"':
            out.append("#if !TARGET_OS_TV")
            out.append(line)
            out.append("#endif")
            i += 1
            continue

        # --- Guard the iOS ADM creation block ---
        # Matches: "// iOS ADM implementation." comment followed by
        # #if defined(WEBRTC_IOS)
        if line.strip() == "// iOS ADM implementation.":
            out.append(line)
            i += 1
            if i < len(lines) and "#if defined(WEBRTC_IOS)" in lines[i]:
                out.append(
                    lines[i].replace(
                        "#if defined(WEBRTC_IOS)",
                        "#if defined(WEBRTC_IOS) && !TARGET_OS_TV",
                    )
                )
                i += 1
            continue

        # --- Guard the Mac ADM creation block ---
        # Matches: "// Mac OS X ADM implementation." comment followed by
        # #elif defined(WEBRTC_MAC)
        if line.strip() == "// Mac OS X ADM implementation.":
            out.append(line)
            i += 1
            if i < len(lines) and "#elif defined(WEBRTC_MAC)" in lines[i]:
                out.append(
                    lines[i].replace(
                        "#elif defined(WEBRTC_MAC)",
                        "#elif defined(WEBRTC_MAC) && !TARGET_OS_TV",
                    )
                )
                i += 1
            continue

        # Everything else passes through unchanged
        out.append(line)
        i += 1

    write_file(path, "\n".join(out))
    print("  Patched audio_device_impl.cc")


def patch_bluetooth_deprecation() -> None:
    """Replace deprecated AVAudioSessionCategoryOptionAllowBluetooth."""
    path = SRC_DIR / "sdk/objc/components/audio/RTCAudioSessionConfiguration.m"
    if not path.exists():
        return
    content = read_file(path)
    new = content.replace(
        "AVAudioSessionCategoryOptionAllowBluetooth;",
        "AVAudioSessionCategoryOptionAllowBluetoothHFP;",
    )
    if new != content:
        write_file(path, new)
        print("  Fixed Bluetooth deprecation")


def patch_metal_renderer() -> None:
    """Change TARGET_OS_IOS to TARGET_OS_IPHONE in Metal renderer header.

    tvOS is TARGET_OS_IPHONE (1) but not TARGET_OS_IOS (0).
    """
    path = SRC_DIR / "sdk/objc/components/renderer/metal/RTCMTLRenderer.h"
    if not path.exists():
        return
    content = read_file(path)
    new = content.replace("#if TARGET_OS_IOS", "#if TARGET_OS_IPHONE")
    if new != content:
        write_file(path, new)
        print("  Patched RTCMTLRenderer.h")


# ------------------------------------------------------------------
# Main
# ------------------------------------------------------------------
def main() -> None:
    if not SRC_DIR.exists():
        print(f"Error: WebRTC source directory not found at {SRC_DIR}")
        sys.exit(1)

    print("Applying source patches...")

    # --- Bluetooth deprecation fix (all platforms) ---
    patch_bluetooth_deprecation()

    # === STRATEGY 1: Full-file guards for entirely iOS-only files ===

    # Audio session
    for f in [
        "sdk/objc/components/audio/RTCAudioSessionConfiguration.h",
        "sdk/objc/components/audio/RTCAudioSessionConfiguration.m",
        "sdk/objc/components/audio/RTCAudioSession.h",
        "sdk/objc/components/audio/RTCAudioSession+Private.h",
        "sdk/objc/components/audio/RTCAudioSession.mm",
        "sdk/objc/components/audio/RTCAudioSession+Configuration.mm",
        "sdk/objc/components/audio/RTCNativeAudioSessionDelegateAdapter.h",
        "sdk/objc/components/audio/RTCNativeAudioSessionDelegateAdapter.mm",
    ]:
        guard_file(f)

    # Camera preview
    for f in [
        "sdk/objc/helpers/RTCCameraPreviewView.h",
        "sdk/objc/helpers/RTCCameraPreviewView.m",
    ]:
        guard_file(f)

    # AVCapture helpers
    for f in [
        "sdk/objc/helpers/AVCaptureSession+DevicePosition.h",
        "sdk/objc/helpers/AVCaptureSession+DevicePosition.mm",
    ]:
        guard_file(f)

    # Native audio device
    for f in [
        "sdk/objc/native/src/audio/voice_processing_audio_unit.h",
        "sdk/objc/native/src/audio/voice_processing_audio_unit.mm",
        "sdk/objc/native/src/audio/audio_device_ios.h",
        "sdk/objc/native/src/audio/audio_device_ios.mm",
        "sdk/objc/native/src/audio/audio_device_module_ios.h",
        "sdk/objc/native/src/audio/audio_device_module_ios.mm",
        "sdk/objc/native/src/audio/helpers.h",
        "sdk/objc/native/src/audio/helpers.mm",
        "sdk/objc/native/src/audio/audio_session_observer.h",
        "sdk/objc/native/api/audio_device_module.h",
        "sdk/objc/native/api/audio_device_module.mm",
    ]:
        guard_file(f)

    # Camera capturer
    for f in [
        "sdk/objc/components/capturer/RTCCameraVideoCapturer.h",
        "sdk/objc/components/capturer/RTCCameraVideoCapturer.m",
        "sdk/objc/components/capturer/RTCFileVideoCapturer.h",
        "sdk/objc/components/capturer/RTCFileVideoCapturer.m",
    ]:
        guard_file(f)

    # OpenGL renderer
    for f in [
        "sdk/objc/components/renderer/opengl/RTCEAGLVideoView.h",
        "sdk/objc/components/renderer/opengl/RTCEAGLVideoView.m",
        "sdk/objc/components/renderer/opengl/RTCDisplayLinkTimer.h",
        "sdk/objc/components/renderer/opengl/RTCDisplayLinkTimer.m",
    ]:
        guard_file(f)

    # UIDevice helpers
    for f in [
        "sdk/objc/components/video_codec/UIDevice+H264Profile.h",
        "sdk/objc/components/video_codec/UIDevice+H264Profile.mm",
        "sdk/objc/helpers/UIDevice+RTCDevice.h",
        "sdk/objc/helpers/UIDevice+RTCDevice.mm",
    ]:
        guard_file(f)

    # === STRATEGY 2: Patch WEBRTC_IOS guards in mixed-use files ===

    for f in [
        # H264 profile — references UIDevice+H264Profile.h (guarded)
        "sdk/objc/components/video_codec/RTCH264ProfileLevelId.mm",
        # H264 encoder — references UIDevice+RTCDevice.h (guarded)
        "sdk/objc/components/video_codec/RTCVideoEncoderH264.mm",
        # H264 decoder — references UIDevice+RTCDevice.h (guarded)
        "sdk/objc/components/video_codec/RTCVideoDecoderH264.mm",
        # PeerConnectionFactory — references audio_device_module.h (guarded)
        "sdk/objc/api/peerconnection/RTCPeerConnectionFactory.mm",
        # PeerConnectionFactoryBuilder — same
        "sdk/objc/api/peerconnection/RTCPeerConnectionFactoryBuilder+DefaultComponents.mm",
        # Network monitor factory — iOS-only factory
        "sdk/objc/native/api/network_monitor_factory.mm",
        # Debug code with UIKit
        "sdk/objc/api/video_frame_buffer/RTCNativeI420Buffer.mm",
        "sdk/objc/components/video_frame_buffer/RTCCVPixelBuffer.mm",
    ]:
        patch_webrtc_ios_guards(f)

    # === STRATEGY 3: Targeted patches ===

    patch_metal_renderer()
    patch_audio_device_impl()

    print("All patches applied.")


if __name__ == "__main__":
    main()
