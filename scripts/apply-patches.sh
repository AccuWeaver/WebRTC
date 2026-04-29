#!/bin/sh
# Applies all patches to the WebRTC source tree for tvOS compatibility.
# Run this after `gclient sync` and before `ninja` builds.
#
# Strategy: Many ObjC SDK files use iOS-specific APIs (AVCaptureSession,
# AVAudioSession, UIDevice orientation, Voice Processing Audio Unit) that
# are either unavailable on tvOS or require tvOS 17.0+ while our deployment
# target is 15.0. Since the tvOS app is receive-only (no camera, no mic),
# we wrap these files in #if !TARGET_OS_TV guards so they compile as empty
# translation units on tvOS while remaining unchanged on iOS/macOS.

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
        return  # already patched
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

# Fix 1: AVAudioSessionCategoryOptionAllowBluetooth deprecated in Xcode 26+
# Replace with AVAudioSessionCategoryOptionAllowBluetoothHFP (for iOS/macOS)
AUDIO_CONFIG="${SRC_DIR}/sdk/objc/components/audio/RTCAudioSessionConfiguration.m"
if [ -f "$AUDIO_CONFIG" ]; then
    sed -i '' 's/AVAudioSessionCategoryOptionAllowBluetooth;/AVAudioSessionCategoryOptionAllowBluetoothHFP;/' "$AUDIO_CONFIG"
    echo "  Fixed Bluetooth deprecation in RTCAudioSessionConfiguration.m"
fi

# Fix 2: Guard files that use tvOS 17.0+ or iOS-only APIs
# These are all capture/audio-session/device-orientation helpers that a
# receive-only tvOS streaming app does not need.

# Audio session configuration (AVAudioSession APIs require tvOS 17.0+)
wrap_in_tvos_guard "${SRC_DIR}/sdk/objc/components/audio/RTCAudioSessionConfiguration.m"
wrap_in_tvos_guard "${SRC_DIR}/sdk/objc/components/audio/RTCAudioSession.mm"
wrap_in_tvos_guard "${SRC_DIR}/sdk/objc/components/audio/RTCAudioSession+Configuration.mm"

# Camera preview (AVCaptureSession, UIDeviceOrientation unavailable on tvOS)
wrap_in_tvos_guard "${SRC_DIR}/sdk/objc/helpers/RTCCameraPreviewView.m"

# AVCapture helpers (AVCaptureSession requires tvOS 17.0+)
wrap_in_tvos_guard "${SRC_DIR}/sdk/objc/helpers/AVCaptureSession+DevicePosition.mm"

# Native audio device (Voice Processing Audio Unit, audio_device_ios)
wrap_in_tvos_guard "${SRC_DIR}/sdk/objc/native/src/audio/voice_processing_audio_unit.mm"
wrap_in_tvos_guard "${SRC_DIR}/sdk/objc/native/src/audio/audio_device_ios.mm"
wrap_in_tvos_guard "${SRC_DIR}/sdk/objc/native/src/audio/audio_device_module_ios.mm"
wrap_in_tvos_guard "${SRC_DIR}/sdk/objc/native/src/audio/helpers.mm"

# Camera capturer (AVCaptureSession, AVCaptureDevice)
wrap_in_tvos_guard "${SRC_DIR}/sdk/objc/components/capturer/RTCCameraVideoCapturer.m"

# OpenGL renderer (GLKit/EAGL deprecated, UIApplication references)
wrap_in_tvos_guard "${SRC_DIR}/sdk/objc/components/renderer/opengl/RTCEAGLVideoView.m"
wrap_in_tvos_guard "${SRC_DIR}/sdk/objc/components/renderer/opengl/RTCDisplayLinkTimer.m"

echo "All patches applied."
