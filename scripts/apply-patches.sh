#!/bin/sh
# Applies all patches to the WebRTC source tree for tvOS compatibility.
# Run this after `gclient sync` and before `ninja` builds.
#
# The tvOS build uses target_os="ios" in GN, so WEBRTC_IOS is defined.
# We use TARGET_OS_TV (from <TargetConditionals.h>) to distinguish tvOS
# from real iOS at compile time. Two strategies are used:
#
# 1. guard_file: wraps ENTIRE file in #if !TARGET_OS_TV / #endif
#    Used for files that are completely iOS-only (audio session, camera, etc.)
#
# 2. Surgical sed patches for specific WEBRTC_IOS guards in files that
#    have both iOS-specific and cross-platform code.
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

# Helper: adds TargetConditionals.h include and patches ALL WEBRTC_IOS
# guards to also exclude TARGET_OS_TV. Only use for files where EVERY
# WEBRTC_IOS block is iOS-only (not needed on tvOS).
patch_all_webrtc_ios_guards() {
    local f="$1"
    [ ! -f "$f" ] && return
    grep -q "TARGET_OS_TV" "$f" && return
    # Add TargetConditionals.h include after the first #import or #include
    sed -i '' '1,/^#i[mn][cp][lo][ur][dt]/{
        /^#i[mn][cp][lo][ur][dt]/a\
#include <TargetConditionals.h>
    }' "$f"
    # Patch all WEBRTC_IOS conditionals
    sed -i '' 's/#if defined(WEBRTC_IOS)/#if defined(WEBRTC_IOS) \&\& !TARGET_OS_TV/g' "$f"
    sed -i '' 's/#ifdef WEBRTC_IOS/#if defined(WEBRTC_IOS) \&\& !TARGET_OS_TV/g' "$f"
    sed -i '' 's/#elif defined(WEBRTC_IOS)/#elif defined(WEBRTC_IOS) \&\& !TARGET_OS_TV/g' "$f"
    echo "  Patched WEBRTC_IOS guards in $(basename "$f")"
}

# --- Bluetooth deprecation fix (all platforms) ---
AUDIO_CFG="${SRC_DIR}/sdk/objc/components/audio/RTCAudioSessionConfiguration.m"
[ -f "$AUDIO_CFG" ] && sed -i '' 's/AVAudioSessionCategoryOptionAllowBluetooth;/AVAudioSessionCategoryOptionAllowBluetoothHFP;/' "$AUDIO_CFG" && echo "  Fixed Bluetooth deprecation"

# =====================================================================
# STRATEGY 1: Full-file guards for entirely iOS-only files
# These files have no useful code on tvOS — wrap them completely.
# =====================================================================

# Audio session (not available on tvOS)
guard_file "${SRC_DIR}/sdk/objc/components/audio/RTCAudioSessionConfiguration.h"
guard_file "${SRC_DIR}/sdk/objc/components/audio/RTCAudioSessionConfiguration.m"
guard_file "${SRC_DIR}/sdk/objc/components/audio/RTCAudioSession.h"
guard_file "${SRC_DIR}/sdk/objc/components/audio/RTCAudioSession+Private.h"
guard_file "${SRC_DIR}/sdk/objc/components/audio/RTCAudioSession.mm"
guard_file "${SRC_DIR}/sdk/objc/components/audio/RTCAudioSession+Configuration.mm"
guard_file "${SRC_DIR}/sdk/objc/components/audio/RTCNativeAudioSessionDelegateAdapter.h"
guard_file "${SRC_DIR}/sdk/objc/components/audio/RTCNativeAudioSessionDelegateAdapter.mm"

# Camera preview (no camera on tvOS)
guard_file "${SRC_DIR}/sdk/objc/helpers/RTCCameraPreviewView.h"
guard_file "${SRC_DIR}/sdk/objc/helpers/RTCCameraPreviewView.m"

# AVCapture helpers (no capture on tvOS)
guard_file "${SRC_DIR}/sdk/objc/helpers/AVCaptureSession+DevicePosition.h"
guard_file "${SRC_DIR}/sdk/objc/helpers/AVCaptureSession+DevicePosition.mm"

# Native audio device (iOS-specific audio unit)
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

# Camera capturer (no camera on tvOS)
guard_file "${SRC_DIR}/sdk/objc/components/capturer/RTCCameraVideoCapturer.h"
guard_file "${SRC_DIR}/sdk/objc/components/capturer/RTCCameraVideoCapturer.m"
guard_file "${SRC_DIR}/sdk/objc/components/capturer/RTCFileVideoCapturer.h"
guard_file "${SRC_DIR}/sdk/objc/components/capturer/RTCFileVideoCapturer.m"

# OpenGL renderer (EAGL not available on tvOS in same form)
guard_file "${SRC_DIR}/sdk/objc/components/renderer/opengl/RTCEAGLVideoView.h"
guard_file "${SRC_DIR}/sdk/objc/components/renderer/opengl/RTCEAGLVideoView.m"
guard_file "${SRC_DIR}/sdk/objc/components/renderer/opengl/RTCDisplayLinkTimer.h"
guard_file "${SRC_DIR}/sdk/objc/components/renderer/opengl/RTCDisplayLinkTimer.m"

# UIDevice helpers (device-specific profiles not relevant on tvOS)
guard_file "${SRC_DIR}/sdk/objc/components/video_codec/UIDevice+H264Profile.h"
guard_file "${SRC_DIR}/sdk/objc/components/video_codec/UIDevice+H264Profile.mm"
guard_file "${SRC_DIR}/sdk/objc/helpers/UIDevice+RTCDevice.h"
guard_file "${SRC_DIR}/sdk/objc/helpers/UIDevice+RTCDevice.mm"

# =====================================================================
# STRATEGY 2: Patch WEBRTC_IOS guards in mixed-use files
# These files have cross-platform code but use #if defined(WEBRTC_IOS)
# to conditionally include iOS-specific sections that reference guarded
# headers. Since the tvOS build defines WEBRTC_IOS (target_os="ios"),
# we add !TARGET_OS_TV to skip those sections on tvOS.
# =====================================================================

# --- H264 profile level ID ---
# References UIDevice+H264Profile.h (guarded) under WEBRTC_IOS.
# All WEBRTC_IOS blocks in this file are iOS-only (device profile detection).
patch_all_webrtc_ios_guards "${SRC_DIR}/sdk/objc/components/video_codec/RTCH264ProfileLevelId.mm"

# --- H264 encoder ---
# References UIDevice+RTCDevice.h (guarded) under WEBRTC_IOS.
# Has multiple WEBRTC_IOS blocks: device detection, pixel buffer compat,
# and encoder config. All are safe to skip on tvOS (uses defaults).
patch_all_webrtc_ios_guards "${SRC_DIR}/sdk/objc/components/video_codec/RTCVideoEncoderH264.mm"

# --- H264 decoder ---
# References UIDevice+RTCDevice.h (guarded) under WEBRTC_IOS.
# Has WEBRTC_IOS blocks for decoder re-init, pixel buffer compat, and
# session config. All safe to skip on tvOS.
patch_all_webrtc_ios_guards "${SRC_DIR}/sdk/objc/components/video_codec/RTCVideoDecoderH264.mm"

# --- PeerConnectionFactory ---
# Imports audio_device_module.h (guarded) under WEBRTC_IOS and calls
# CreateAudioDeviceModule(env) which is the iOS-native ADM factory.
# The cross-platform CreateAudioDeviceModule(env, audioDevice) overload
# (from objc_audio_device_module.h) remains available.
patch_all_webrtc_ios_guards "${SRC_DIR}/sdk/objc/api/peerconnection/RTCPeerConnectionFactory.mm"

# --- PeerConnectionFactoryBuilder+DefaultComponents ---
# Same pattern as RTCPeerConnectionFactory.mm.
patch_all_webrtc_ios_guards "${SRC_DIR}/sdk/objc/api/peerconnection/RTCPeerConnectionFactoryBuilder+DefaultComponents.mm"

# --- Network monitor factory ---
# Creates ObjCNetworkMonitorFactory under WEBRTC_IOS, returns nullptr otherwise.
# On tvOS, returning nullptr is fine (no network monitoring).
patch_all_webrtc_ios_guards "${SRC_DIR}/sdk/objc/native/api/network_monitor_factory.mm"

# --- Native I420 buffer & CVPixelBuffer ---
# Have WEBRTC_IOS debug code that imports UIKit for debugQuickLookObject.
# Safe to skip on tvOS (debug-only, guarded by !NDEBUG too).
patch_all_webrtc_ios_guards "${SRC_DIR}/sdk/objc/api/video_frame_buffer/RTCNativeI420Buffer.mm"
patch_all_webrtc_ios_guards "${SRC_DIR}/sdk/objc/components/video_frame_buffer/RTCCVPixelBuffer.mm"

# =====================================================================
# STRATEGY 3: Targeted patches for specific issues
# =====================================================================

# --- Metal renderer: TARGET_OS_IOS -> TARGET_OS_IPHONE ---
# tvOS is TARGET_OS_IPHONE but not TARGET_OS_IOS, so use the broader check
MTL_H="${SRC_DIR}/sdk/objc/components/renderer/metal/RTCMTLRenderer.h"
[ -f "$MTL_H" ] && sed -i '' 's/#if TARGET_OS_IOS/#if TARGET_OS_IPHONE/g' "$MTL_H" && echo "  Patched RTCMTLRenderer.h"

# --- Core C++ audio_device_impl.cc: skip iOS ADM on tvOS ---
# This file creates the platform-specific audio device. On tvOS we skip
# the iOS ADM (which uses guarded audio_device_ios.h) so the dummy ADM
# or a custom RTCAudioDevice-based ADM is used instead.
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
