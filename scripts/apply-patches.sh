#!/bin/sh
# Applies all patches to the WebRTC source tree for tvOS compatibility.
# Run this after `gclient sync` and before `ninja` builds.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_DIR="${SCRIPT_DIR}/../src"

echo "Applying source patches..."

# Helper: wraps an ObjC file in #if !TARGET_OS_TV / #endif
wrap_in_tvos_guard() {
    local filepath="$1"
    if [ ! -f "$filepath" ]; then
        return
    fi
    if grep -q "TARGET_OS_TV" "$filepath"; then
        return
    fi
    python3 - "$filepath" << 'PYEOF'
import sys
filepath = sys.argv[1]
with open(filepath, 'r') as f:
    content = f.read()
lines = content.split('\n')
last_import_idx = 0
for i, line in enumerate(lines):
    stripped = line.strip()
    if stripped.startswith('#import') or stripped.startswith('#include'):
        last_import_idx = i
lines.insert(last_import_idx + 1, '')
lines.insert(last_import_idx + 2, '#include <TargetConditionals.h>')
lines.insert(last_import_idx + 3, '#if !TARGET_OS_TV')
lines.append('#endif  // !TARGET_OS_TV')
with open(filepath, 'w') as f:
    f.write('\n'.join(lines))
PYEOF
    echo "  Guarded $(basename $filepath)"
}

# --- Xcode 26+ SDK deprecation fixes (affects all platforms) ---

# Fix: AVAudioSessionCategoryOptionAllowBluetooth deprecated
AUDIO_CONFIG="${SRC_DIR}/sdk/objc/components/audio/RTCAudioSessionConfiguration.m"
if [ -f "$AUDIO_CONFIG" ]; then
    sed -i '' 's/AVAudioSessionCategoryOptionAllowBluetooth;/AVAudioSessionCategoryOptionAllowBluetoothHFP;/' "$AUDIO_CONFIG"
    echo "  Fixed Bluetooth deprecation in RTCAudioSessionConfiguration.m"
fi

# --- tvOS #if !TARGET_OS_TV guards (files using tvOS 17.0+ or iOS-only APIs) ---

# Audio session (AVAudioSession APIs require tvOS 17.0+)
wrap_in_tvos_guard "${SRC_DIR}/sdk/objc/components/audio/RTCAudioSessionConfiguration.m"
wrap_in_tvos_guard "${SRC_DIR}/sdk/objc/components/audio/RTCAudioSession.mm"
wrap_in_tvos_guard "${SRC_DIR}/sdk/objc/components/audio/RTCAudioSession+Configuration.mm"
wrap_in_tvos_guard "${SRC_DIR}/sdk/objc/components/audio/RTCNativeAudioSessionDelegateAdapter.mm"

# Camera preview (AVCaptureSession, UIDeviceOrientation unavailable on tvOS)
wrap_in_tvos_guard "${SRC_DIR}/sdk/objc/helpers/RTCCameraPreviewView.m"

# AVCapture helpers (AVCaptureSession requires tvOS 17.0+)
wrap_in_tvos_guard "${SRC_DIR}/sdk/objc/helpers/AVCaptureSession+DevicePosition.mm"

# Native audio device (Voice Processing Audio Unit, audio_device_ios)
wrap_in_tvos_guard "${SRC_DIR}/sdk/objc/native/src/audio/voice_processing_audio_unit.mm"
wrap_in_tvos_guard "${SRC_DIR}/sdk/objc/native/src/audio/audio_device_ios.mm"
wrap_in_tvos_guard "${SRC_DIR}/sdk/objc/native/src/audio/audio_device_module_ios.mm"
wrap_in_tvos_guard "${SRC_DIR}/sdk/objc/native/src/audio/helpers.mm"
wrap_in_tvos_guard "${SRC_DIR}/sdk/objc/native/api/audio_device_module.mm"

# Camera capturer (AVCaptureSession, AVCaptureDevice)
wrap_in_tvos_guard "${SRC_DIR}/sdk/objc/components/capturer/RTCCameraVideoCapturer.m"
wrap_in_tvos_guard "${SRC_DIR}/sdk/objc/components/capturer/RTCFileVideoCapturer.m"

# OpenGL renderer (GLKit/EAGL deprecated, UIApplication references)
wrap_in_tvos_guard "${SRC_DIR}/sdk/objc/components/renderer/opengl/RTCEAGLVideoView.m"
wrap_in_tvos_guard "${SRC_DIR}/sdk/objc/components/renderer/opengl/RTCDisplayLinkTimer.m"

# Video codec (UIDevice+H264Profile uses iOS-specific device checks)
wrap_in_tvos_guard "${SRC_DIR}/sdk/objc/components/video_codec/UIDevice+H264Profile.mm"

# --- Metal renderer TARGET_OS_IOS -> TARGET_OS_IPHONE fix ---
# RTCMTLRenderer.h uses #if TARGET_OS_IOS which is false on tvOS.
# tvOS uses UIKit like iOS, so the correct check is TARGET_OS_IPHONE
# (true for both iOS and tvOS). Without this fix, tvOS falls into the
# #else branch which imports AppKit and uses NSView (macOS-only).
MTL_RENDERER_H="${SRC_DIR}/sdk/objc/components/renderer/metal/RTCMTLRenderer.h"
if [ -f "$MTL_RENDERER_H" ]; then
    sed -i '' 's/#if TARGET_OS_IOS/#if TARGET_OS_IPHONE/g' "$MTL_RENDERER_H"
    sed -i '' 's/#if TARGET_OS_iOS/#if TARGET_OS_IPHONE/g' "$MTL_RENDERER_H"
    echo "  Patched RTCMTLRenderer.h (TARGET_OS_IOS -> TARGET_OS_IPHONE)"
fi

# --- Disable scheduled release workflow (no releases exist yet) ---
# The release.py crashes with IndexError when no GitHub releases exist.
# This is handled by disabling the workflow in the repo settings instead.

echo "All patches applied."
