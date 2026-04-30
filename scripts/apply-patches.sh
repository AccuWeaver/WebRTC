#!/bin/sh
# Applies all patches to the WebRTC source tree for tvOS compatibility.
# Run this after `gclient sync` and before `ninja` builds.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_DIR="${SCRIPT_DIR}/../src"

echo "Applying source patches..."

# Helper: wraps ENTIRE file in #if !TARGET_OS_TV / #endif
# This includes the imports, so the file is completely empty on tvOS.
wrap_in_tvos_guard() {
    local filepath="$1"
    if [ ! -f "$filepath" ]; then
        return
    fi
    if grep -q "TARGET_OS_TV" "$filepath"; then
        return
    fi
    # Prepend guard at top, append endif at bottom
    local tmp="${filepath}.tvos_tmp"
    {
        echo "#include <TargetConditionals.h>"
        echo "#if !TARGET_OS_TV"
        cat "$filepath"
        echo ""
        echo "#endif  // !TARGET_OS_TV"
    } > "$tmp"
    mv "$tmp" "$filepath"
    echo "  Guarded $(basename $filepath)"
}

# --- Xcode 26+ SDK deprecation fixes (affects all platforms) ---

AUDIO_CONFIG="${SRC_DIR}/sdk/objc/components/audio/RTCAudioSessionConfiguration.m"
if [ -f "$AUDIO_CONFIG" ]; then
    sed -i '' 's/AVAudioSessionCategoryOptionAllowBluetooth;/AVAudioSessionCategoryOptionAllowBluetoothHFP;/' "$AUDIO_CONFIG"
    echo "  Fixed Bluetooth deprecation in RTCAudioSessionConfiguration.m"
fi

# --- tvOS guards: wrap ENTIRE files (headers + implementations) ---

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

# Camera capturer
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
