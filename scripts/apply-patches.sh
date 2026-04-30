
# --- Core C++ audio device impl: guard iOS ADM for tvOS ---
# modules/audio_device/audio_device_impl.cc has #if defined(WEBRTC_IOS) blocks
# that include audio_device_ios.h and create ios_adm::AudioDeviceIOS.
# Since we guard out those iOS audio files on tvOS, we need to also guard
# the references in this core C++ file. On tvOS, the dummy ADM will be used.
ADM_IMPL="${SRC_DIR}/modules/audio_device/audio_device_impl.cc"
if [ -f "$ADM_IMPL" ]; then
    if ! grep -q "TARGET_OS_TV" "$ADM_IMPL"; then
        # Add TargetConditionals.h include near the top (after the first #include)
        sed -i '' '/#include "modules\/audio_device\/audio_device_impl.h"/a\
#include <TargetConditionals.h>' "$ADM_IMPL"
        # Guard the iOS-specific include
        sed -i '' 's/^#elif defined(WEBRTC_IOS)$/#elif defined(WEBRTC_IOS) \&\& !TARGET_OS_TV/' "$ADM_IMPL"
        # Guard all #if defined(WEBRTC_IOS) blocks
        sed -i '' 's/^#if defined(WEBRTC_IOS)$/#if defined(WEBRTC_IOS) \&\&        sed -i '' 's/^#if defined(WEBRcho        sed -i '' 's/^#if defined(WEBRTC_IOS)$/#if defined("
    fi
fi

echo "All patches applied."
