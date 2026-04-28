#!/bin/sh
# Applies all patches to the WebRTC source tree.
# Run this after `gclient sync` and before `ninja` builds.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_DIR="${SCRIPT_DIR}/../src"

echo "Applying source patches..."

# Fix 1: AVAudioSessionCategoryOptionAllowBluetooth deprecated in Xcode 26+ SDK
# Replace with AVAudioSessionCategoryOptionAllowBluetoothHFP
if [ -f "${SRC_DIR}/sdk/objc/components/audio/RTCAudioSessionConfiguration.m" ]; then
    sed -i '' 's/AVAudioSessionCategoryOptionAllowBluetooth;/AVAudioSessionCategoryOptionAllowBluetoothHFP;/' \
        "${SRC_DIR}/sdk/objc/components/audio/RTCAudioSessionConfiguration.m"
    echo "  Patched RTCAudioSessionConfiguration.m (Bluetooth deprecation fix)"
else
    echo "  WARNING: RTCAudioSessionConfiguration.m not found, skipping Bluetooth patch"
fi

# Fix 2: RTCCameraPreviewView.m uses AVCaptureSession, UIDeviceOrientation,
# and AVCaptureVideoPreviewLayer which are unavailable or restricted on tvOS.
# Wrap the entire implementation in #if !TARGET_OS_TV so it compiles as a
# no-op stub on tvOS while remaining unchanged on iOS/macOS.
CAMERA_PREVIEW="${SRC_DIR}/sdk/objc/helpers/RTCCameraPreviewView.m"
if [ -f "$CAMERA_PREVIEW" ]; then
    # Only patch if not already patched
    if ! grep -q "TARGET_OS_TV" "$CAMERA_PREVIEW"; then
        # Insert #if !TARGET_OS_TV after the imports, wrap implementation, close with #endif
        # Strategy: add #include <TargetConditionals.h> and #if !TARGET_OS_TV after the last #import,
        # and #endif at the very end of the file
        python3 - "$CAMERA_PREVIEW" << 'PYEOF'
import sys

filepath = sys.argv[1]
with open(filepath, 'r') as f:
    content = f.read()

lines = content.split('\n')
# Find the last #import or #include line
last_import_idx = 0
for i, line in enumerate(lines):
    if line.startswith('#import') or line.startswith('#include'):
        last_import_idx = i

# Insert after last import
lines.insert(last_import_idx + 1, '')
lines.insert(last_import_idx + 2, '#include <TargetConditionals.h>')
lines.insert(last_import_idx + 3, '#if !TARGET_OS_TV')

# Add #endif at the end
lines.append('#endif  // !TARGET_OS_TV')

with open(filepath, 'w') as f:
    f.write('\n'.join(lines))
PYEOF
        echo "  Patched RTCCameraPreviewView.m (wrapped in #if !TARGET_OS_TV)"
    else
        echo "  RTCCameraPreviewView.m already patched, skipping"
    fi
else
    echo "  WARNING: RTCCameraPreviewView.m not found, skipping tvOS guard patch"
fi

echo "All patches applied."
