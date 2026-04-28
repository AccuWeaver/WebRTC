#!/bin/sh
# Applies all patches to the WebRTC source tree.
# Run this after `gclient sync` and before `ninja` builds.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_DIR="${SCRIPT_DIR}/../src"

echo "Applying source patches..."

# Fix: AVAudioSessionCategoryOptionAllowBluetooth deprecated in Xcode 26+ SDK
# Replace with AVAudioSessionCategoryOptionAllowBluetoothHFP
if [ -f "${SRC_DIR}/sdk/objc/components/audio/RTCAudioSessionConfiguration.m" ]; then
    sed -i '' 's/AVAudioSessionCategoryOptionAllowBluetooth;/AVAudioSessionCategoryOptionAllowBluetoothHFP;/' \
        "${SRC_DIR}/sdk/objc/components/audio/RTCAudioSessionConfiguration.m"
    echo "  Patched RTCAudioSessionConfiguration.m (Bluetooth deprecation fix)"
else
    echo "  WARNING: RTCAudioSessionConfiguration.m not found, skipping Bluetooth patch"
fi

echo "All patches applied."
