#!/bin/sh

## Validates that the WebRTC.xcframework links correctly on tvOS
## Usage: validate_tvos.sh <xcframework_path>
## Exits non-zero if compilation fails for either tvOS device or simulator.

set -e

XCFRAMEWORK_PATH=$1

if [ -z "$XCFRAMEWORK_PATH" ]; then
    echo "Error: xcframework path argument is required"
    echo "Usage: validate_tvos.sh <xcframework_path>"
    exit 1
fi

if [ ! -d "$XCFRAMEWORK_PATH" ]; then
    echo "Error: xcframework not found at: $XCFRAMEWORK_PATH"
    exit 1
fi

TEMP_DIR=$(mktemp -d)
SWIFT_FILE="${TEMP_DIR}/webrtc_tvos_validate.swift"

# Create a minimal Swift file that imports WebRTC and instantiates RTCPeerConnectionFactory
cat > "$SWIFT_FILE" << 'EOF'
import WebRTC
let factory = RTCPeerConnectionFactory()
print("RTCPeerConnectionFactory created: \(factory)")
EOF

echo "Validating tvOS device (arm64-apple-tvos15.0)..."
xcrun swiftc -target arm64-apple-tvos15.0 \
    -F "${XCFRAMEWORK_PATH}/tvos-arm64" \
    -framework WebRTC \
    "$SWIFT_FILE" -o /dev/null

echo "✅ tvOS device validation passed"

echo "Validating tvOS simulator (arm64-apple-tvos15.0-simulator)..."
xcrun swiftc -target arm64-apple-tvos15.0-simulator \
    -F "${XCFRAMEWORK_PATH}/tvos-arm64-simulator" \
    -framework WebRTC \
    "$SWIFT_FILE" -o /dev/null

echo "✅ tvOS simulator validation passed"

# Cleanup
rm -rf "$TEMP_DIR"

echo "✅ All tvOS validations passed"
