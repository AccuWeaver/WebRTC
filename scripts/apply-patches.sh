#!/bin/sh
# Applies all patches to the WebRTC source tree for tvOS compatibility.
# Run this after `gclient sync` and before `ninja` builds.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_DIR="${SCRIPT_DIR}/../src"

echo "Applying source patches..."

# Helper: wraps an ObjC source or header file in #if !TARGET_OS_TV / #endif
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

AUDIO_CONFIG="${SRC_DIR}/sdk/objc/components/audio/RTCAudioSessionConfiguration.m"
if [ -f "$AUDIO_CONFIG" ]; then
    sed -i '' 's/AVAudioSessionCategoryOptionAllowBluetooth;/AVAudioSessionCategoryOptionAllowBluetoothHFP;/' "$AUDIO_CONFIG"
    echo "  Fixed Bluetooth deprecation in RTCAudioSessionConfiguration.m"
fi

# --- tvOS guards: BOTH headers AND implementation files ---
# Headers must be guarded too, because even if the .m is guarded,
# the .m still #imports the .h which triggers availability errors.

# Audio session
wrap_in_tvos_guard "${SRC_DIR}/sdk/objc/components/audio/RTCAudioSessionConfiguration.h"
wrap_in_tvos_guard "${SRC_DIR}/sdk/objc/components/audio/RTCAudioSessionConfiguration.m"
wrap_in_tvos_guard "${SRC_DIR}/sdk/objc/components/audio/RTCAudioSession.h"
wrap_in_tvos_guard "${SRC_DIR}/sdk/objc/components/audio/RTCAudioSession+Private.h"
wrap_in_tvos_guard "${SRC_DIR}/sdk/objc/components/audio/RTCAudioSession.mm"
wrap_in_tvos_guard "${SRC_DIR}/sdk/objc/components/audio/RTCAudioSession+Configuration.mm"
wrap_in_tvos_guard "${SRC_DIR}/sdk/objc/components/audio/RTCNativeAudioSessionDelegateAdapter.h"
wrap_in_tvos_guard "${SRC_DIR}/sdk/objc/components/audio/RTCNativeAudioSessionDelegateAdapter.mm"

# Camera preview
wrap_in_tvos_guard "${SRC_DIR}/sdk/objc/helpers/RTCCameraPreviewView.h"
wrap_in_tvos_guard "${SRC_DIR}/sdk/objc/helpers/RTCCameraPreviewView.m"

# AVCapture helpers
wrap_in_tvos_guard "${SRC_DIR}/sdk/objc/helpers/AVCaptureSession+DevicePosition.h"
wrap_in_tvos_guard "${SRC_DIR}/sdk/objc/helpers/AVCaptureSession+DevicePosition.mm"

# Native audio device
wrap_in_tvos_guard "${SRC_DIR}/sdk/objc/native/src/audio/voice_processing_audio_unit.h"
wrap_in_tvos_guard "${SRC_DIR}/sdk/objc/native/src/audio/voice_processing_audio_unit.mm"
wrap_in_tvos_guard "${SRC_DIR}/sdk/objc/native/src/audio/audio_device_ios.h"
wrap_in_tvos_guard "${SRC_DIR}/sdk/objc/native/src/audio/audio_device_ios.mm"
wrap_in_tvos_guard "${SRC_DIR}/sdk/objc/native/src/audio/audio_device_module_ios.h"
wrap_in_tvos_guard "${SRC_DIR}/sdk/objc/native/src/audio/audio_device_module_ios.mm"
wrap_in_tvos_guard "${SRC_DIR}/sdk/objc/native/src/audio/helpers.h"
wrap_in_tvos_guard "${SRC_DIR}/sdk/objc/native/src/audio/helpers.mm"
wrap_in_tvos_guard "${SRC_DIR}/sdk/objc/native/src/audio/audio_session_observer.h"
wrap_in_tvos_guard "${SRC_DIR}/sdk/objc/native/api/audio_device_module.h"
wrap_in_tvos_guard "${SRC_DIR}/sdk/objc/native/api/audio_device_module.mm"

# Camera capturer (headers + implementations)
wrap_in_tvos_guard "${SRC_DIR}/sdk/objc/components/capturer/RTCCameraVideoCapturer.h"
wrap_in_tvos_guard "${SRC_DIR}/sdk/objc/components/capturer/RTCCameraVideoCapturer.m"
wrap_in_tvos_guard "${SRC_DIR}/sdk/objc/components/capturer/RTCFileVideoCapturer.h"
wrap_in_tvos_guard "${SRC_DIR}/sdk/objc/components/capturer/RTCFileVideoCapturer.m"

# OpenGL renderer
wrap_in_tvos_guard "${SRC_DIR}/sdk/objc/components/renderer/opengl/RTCEAGLVideoView.h"
wrap_in_tvos_guard "${SRC_DIR}/sdk/objc/components/renderer/opengl/RTCEAGLVideoView.m"
wrap_in_tvos_guard "${SRC_DIR}/sdk/objc/components/renderer/opengl/RTCDisplayLinkTimer.h"
wrap_in_tvos_guard "${SRC_DIR}/sdk/objc/components/renderer/opengl/RTCDisplayLinkTimer.m"

# Video codec (UIDevice+H264Profile)
wrap_in_tvos_guard "${SRC_DIR}/sdk/objc/components/video_codec/UIDevice+H264Profile.h"
wrap_in_tvos_guard "${SRC_DIR}/sdk/objc/components/video_codec/UIDevice+H264Profile.mm"

# UIDevice+RTCDevice helper
wrap_in_tvos_guard "${SRC_DIR}/sdk/objc/helpers/UIDevice+RTCDevice.h"
wrap_in_tvos_guard "${SRC_DIR}/sdk/objc/helpers/UIDevice+RTCDevice.mm"

# --- Metal renderer TARGET_OS_IOS -> TARGET_OS_IPHONE fix ---
MTL_RENDERER_H="${SRC_DIR}/sdk/objc/components/renderer/metal/RTCMTLRenderer.h"
if [ -f "$MTL_RENDERER_H" ]; then
    sed -i '' 's/#if TARGET_OS_IOS/#if TARGET_OS_IPHONE/g' "$MTL_RENDERER_H"
    echo "  Patched RTCMTLRenderer.h (TARGET_OS_IOS -> TARGET_OS_IPHONE)"
fi

echo "All patches applied."
