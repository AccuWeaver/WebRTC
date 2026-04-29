#!/bin/sh
# Applies all patches to the WebRTC source tree.
# Run this after `gclient sync` and before `ninja` builds.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_DIR="${SCRIPT_DIR}/../src"

echo "Applying source patches..."

# Fix 1: AVAudioSessionCategoryOptionAllowBluetooth deprecated in Xcode 26+ SDK
# On iOS/macOS: replace with AVAudioSessionCategoryOptionAllowBluetoothHFP
# On tvOS: wrap the entire file in #if !TARGET_OS_TV since AVAudioSession
# configuration APIs (including BluetoothHFP) require tvOS 17.0+ and the
# deployment target is 15.0. tvOS receive-only streaming doesn't need
# audio session configuration.
AUDIO_CONFIG="${SRC_DIR}/sdk/objc/components/audio/RTCAudioSessionConfiguration.m"
if [ -f "$AUDIO_CONFIG" ]; then
    # First, fix the deprecated API for iOS/macOS
    sed -i '' 's/AVAudioSessionCategoryOptionAllowBluetooth;/AVAudioSessionCategoryOptionAllowBluetoothHFP;/' "$AUDIO_CONFIG"
    # Then wrap the whole file in #if !TARGET_OS_TV for tvOS builds
    if ! grep -q "TARGET_OS_TV" "$AUDIO_CONFIG"; then
        python3 - "$AUDIO_CONFIG" << 'PYEOF'
import sys
filepath = sys.argv[1]
with open(filepath, 'r') as f:
    content = f.read()
lines = content.split('\n')
last_import_idx = 0
for i, line in enumerate(lines):
    if line.startswith('#import') or line.startswith('#include'):
        last_import_idx = i
lines.insert(last_import_idx + 1, '')
lines.insert(last_import_idx + 2, '#include <TargetConditionals.h>')
lines.insert(last_import_idx + 3, '#if !TARGET_OS_TV')
lines.append('#endif  // !TARGET_OS_TV')
with open(filepath, 'w') as f:
    f.write('\n'.join(lines))
PYEOF
    fi
    echo "  Patched RTCAudioSessionConfiguration.m (Bluetooth fix + tvOS guard)"
else
    echo "  WARNING: RTCAudioSessionConfiguration.m not found, skipping"
fi

# Fix 2: RTCCameraPreviewView.m uses AVCaptureSession, UIDeviceOrientation,
# and AVCaptureVideoPreviewLayer which are unavailable or restricted on tvOS.
CAMERA_PREVIEW="${SRC_DIR}/sdk/objc/helpers/RTCCameraPreviewView.m"
if [ -f "$CAMERA_PREVIEW" ]; then
    if ! grep -q "TARGET_OS_TV" "$CAMERA_PREVIEW"; then
        python3 - "$CAMERA_PREVIEW" << 'PYEOF'
import sys
filepath = sys.argv[1]
with open(filepath, 'r') as f:
    content = f.read()
lines = content.split('\n')
last_import_idx = 0
for i, line in enumerate(lines):
    if line.startswith('#import') or line.startswith('#include'):
        last_import_idx = i
lines.insert(last_import_idx + 1, '')
lines.insert(last_import_idx + 2, '#include <TargetConditionals.h>')
lines.insert(last_import_idx + 3, '#if !TARGET_OS_TV')
lines.append('#endif  // !TARGET_OS_TV')
with open(filepath, 'w') as f:
    f.write('\n'.join(lines))
PYEOF
    fi
    echo "  Patched RTCCameraPreviewView.m (tvOS guard)"
else
    echo "  WARNING: RTCCameraPreviewView.m not found, skipping"
fi

# Fix 3: RTCAudioSession.m and RTCAudioSession+Configuration.m use
# AVAudioSession APIs that require tvOS 17.0+. Wrap in #if !TARGET_OS_TV.
for AUDIO_FILE in \
    "${SRC_DIR}/sdk/objc/components/audio/RTCAudioSession.mm" \
    "${SRC_DIR}/sdk/objc/components/audio/RTCAudioSession+Configuration.mm"
do
    if [ -f "$AUDIO_FILE" ]; then
        if ! grep -q "TARGET_OS_TV" "$AUDIO_FILE"; then
            python3 - "$AUDIO_FILE" << 'PYEOF'
import sys
filepath = sys.argv[1]
with open(filepath, 'r') as f:
    content = f.read()
lines = content.split('\n')
last_import_idx = 0
for i, line in enumerate(lines):
    if line.startswith('#import') or line.startswith('#include'):
        last_import_idx = i
lines.insert(last_import_idx + 1, '')
lines.insert(last_import_idx + 2, '#include <TargetConditionals.h>')
lines.insert(last_import_idx + 3, '#if !TARGET_OS_TV')
lines.append('#endif  // !TARGET_OS_TV')
with open(filepath, 'w') as f:
    f.write('\n'.join(lines))
PYEOF
            echo "  Patched $(basename $AUDIO_FILE) (tvOS guard)"
        fi
    fi
done

# Fix 4: AVCaptureSession+DevicePosition.mm uses AVCaptureSession which
# requires tvOS 17.0+. Wrap in #if !TARGET_OS_TV.
AVCAP_FILE="${SRC_DIR}/sdk/objc/helpers/AVCaptureSession+DevicePosition.mm"
if [ -f "$AVCAP_FILE" ]; then
    if ! grep -q "TARGET_OS_TV" "$AVCAP_FILE"; then
        python3 - "$AVCAP_FILE" << 'PYEOF'
import sys
filepath = sys.argv[1]
with open(filepath, 'r') as f:
    content = f.read()
lines = content.split('\n')
last_import_idx = 0
for i, line in enumerate(lines):
    if line.startswith('#import') or line.startswith('#include'):
        last_import_idx = i
lines.insert(last_import_idx + 1, '')
lines.insert(last_import_idx + 2, '#include <TargetConditionals.h>')
lines.insert(last_import_idx + 3, '#if !TARGET_OS_TV')
lines.append('#endif  // !TARGET_OS_TV')
with open(filepath, 'w') as f:
    f.write('\n'.join(lines))
PYEOF
        echo "  Patched AVCaptureSession+DevicePosition.mm (tvOS guard)"
    fi
fi

echo "All patches applied."
