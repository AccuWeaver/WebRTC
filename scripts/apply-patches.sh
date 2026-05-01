#!/bin/sh
# Applies all patches to the WebRTC source tree for tvOS compatibility.
# Run this after `gclient sync` and before `ninja` builds.
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_DIR="${SCRIPT_DIR}/../src"

echo "Applying source patches..."

# Helper: wraps ENTIRE file in #if !TARGET_OS_TV / #endif
guard_file() {
    local f="$1"
    [ ! -f "$f" ] && return
    grep -q "TARGET_OS_TV" "$f" && return
    local tmp="${f}.tmp"
    printf '#include <TargetConditionals.h>\n#if !TARGET_OS_TV\n' > "$tmp"
    cat "$f" >> "$tmp"
    printf '\n#endif  // !TARGET_OS_TV\n' >> "$tmp"
    mv "$tmp" "$f"
    echo "  Guarded $(basename "$f")"
}

# --- Bluetooth deprecation fix (all platforms) ---
AUDIO_CFG="${SRC_DIR}/sdk/objc/components/audio/RTCAudioSessionConfiguration.m"
[ -f "$AUDIO_CFG" ] && sed -i '' 's/AVAudioSessionCategoryOptionAllowBluetooth;/AVAudioSessionCategoryOptionAllowBluetoothHFP;/' "$AUDIO_CFG" && echo "  Fixed Bluetooth deprecation"

# --- tvOS guards: entire files (headers + implementations) ---

# Audio session
guard_file "${SRC_DIR}/sdk/objc/components/audio/RTCAudioSessionConfiguration.h"
guard_file "${SRC_DIR}/sdk/objc/components/audio/RTCAudioSessionConfiguration.m"
guard_file "${SRC_DIR}/sdk/objc/components/audio/RTCAudioSession.h"
guard_file "${SRC_DIR}/sdk/objc/components/audio/RTCAudioSession+Private.h"
guard_file "${SRC_DIR}/sdk/objc/components/audio/RTCAudioSession.mm"
guard_file "${SRC_DIR}/sdk/objc/components/audio/RTCAudioSession+Configuration.mm"
guard_file "${SRC_DIR}/sdk/objc/components/audio/RTCNativeAudioSessionDelegateAdapter.h"
guard_file "${SRC_DIR}/sdk/objc/components/audio/RTCNativeAudioSessionDelegateAdapter.mm"

# Camera preview
guard_file "${SRC_DIR}/sdk/objc/helpers/RTCCameraPreviewView.h"
guard_file "${SRC_DIR}/sdk/objc/helpers/RTCCameraPreviewView.m"

# AVCapture helpers
guard_file "${SRC_DIR}/sdk/objc/helpers/AVCaptureSession+DevicePosition.h"
guard_file "${SRC_DIR}/sdk/objc/helpers/AVCaptureSession+DevicePosition.mm"

# Native audio device
guard_file "${SRC_DIR}/sdk/objc/native/src/audio/voice_processing_audio_unit.h"
guard_file "${SRC_DIR}/sdk/objc/native/src/audio/voice_processing_audio_unit.mm"
guard_file "${SRC_DIR}/sdk/objc/native/src/audio/audio_device_ios.h"
guard_file "${SRC_DIR}/sdk/objc/native/src/audio/audio_device_ios.mm"
guard_file "${SRC_DIR}/sdk/objc/native/src/audio/audio_device_module_ios.h"
guard_file "${SRC_DIR}/sdk/objc/native/src/audio/audio_device_module_ios.mm"
guard_file "${SRC_DIR}/sdk/objc/native/src/audio/helpers.h"
guard_file "${SRC_DIR}/sdk/objc/native/src/audio/helpers.mm"
guard_file "${SRC_DIR}/sdk/objc/native/src/audio/audio_session_observer.h"
guard_file "${SRC_DIR}/sdk/objc/native/api/audio_device_module.h"
guard_file "${SRC_DIR}/sdk/objc/native/api/audio_device_module.mm"

# Camera capturer
guard_file "${SRC_DIR}/sdk/objc/components/capturer/RTCCameraVideoCapturer.h"
guard_file "${SRC_DIR}/sdk/objc/components/capturer/RTCCameraVideoCapturer.m"
guard_file "${SRC_DIR}/sdk/objc/components/capturer/RTCFileVideoCapturer.h"
guard_file "${SRC_DIR}/sdk/objc/components/capturer/RTCFileVideoCapturer.m"

# OpenGL renderer
guard_file "${SRC_DIR}/sdk/objc/components/renderer/opengl/RTCEAGLVideoView.h"
guard_file "${SRC_DIR}/sdk/objc/components/renderer/opengl/RTCEAGLVideoView.m"
guard_file "${SRC_DIR}/sdk/objc/components/renderer/opengl/RTCDisplayLinkTimer.h"
guard_file "${SRC_DIR}/sdk/objc/components/renderer/opengl/RTCDisplayLinkTimer.m"

# Video codec
guard_file "${SRC_DIR}/sdk/objc/components/video_codec/UIDevice+H264Profile.h"
guard_file "${SRC_DIR}/sdk/objc/components/video_codec/UIDevice+H264Profile.mm"

# UIDevice helper
guard_file "${SRC_DIR}/sdk/objc/helpers/UIDevice+RTCDevice.h"
guard_file "${SRC_DIR}/sdk/objc/helpers/UIDevice+RTCDevice.mm"

# --- Metal renderer: TARGET_OS_IOS -> TARGET_OS_IPHONE ---
MTL_H="${SRC_DIR}/sdk/objc/components/renderer/metal/RTCMTLRenderer.h"
[ -f "$MTL_H" ] && sed -i '' 's/#if TARGET_OS_IOS/#if TARGET_OS_IPHONE/g' "$MTL_H" && echo "  Patched RTCMTLRenderer.h"

# --- Core C++ audio_device_impl.cc: skip iOS ADM on tvOS ---
ADM="${SRC_DIR}/modules/audio_device/audio_device_impl.cc"
if [ -f "$ADM" ] && ! grep -q "TARGET_OS_TV" "$ADM"; then
    sed -i '' '1i\
#include <TargetConditionals.h>
' "$ADM"
    sed -i '' 's/^#elif defined(WEBRTC_IOS)/#elif defined(WEBRTC_IOS) \&\& !TARGET_OS_TV/' "$ADM"
    sed -i '' 's/^#if defined(WEBRTC_IOS)/#if defined(WEBRTC_IOS) \&\& !TARGET_OS_TV/' "$ADM"
    echo "  Patched audio_device_impl.cc"
fi

echo "All patches applied."
