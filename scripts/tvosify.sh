#!/bin/sh
# tvosify.sh — Patches GN-generated Ninja build files to target tvOS SDK
#
# WebRTC's GN build system does not natively support target_os="tvos".
# This script works around that by generating a build with target_os="ios"
# and then replacing all iOS SDK sysroot references with the equivalent
# tvOS SDK paths in the generated .ninja files.
#
# Usage: tvosify.sh <build_dir> <environment>
#   build_dir:   Path to the GN-generated output directory (e.g., out/tvos-arm64-device)
#   environment: "device" or "simulator"
#
# Requirements: 2.1, 2.2, 2.3, 2.4

set -e

BUILD_DIR="$1"
ENVIRONMENT="$2"

# Validate arguments
if [ -z "$BUILD_DIR" ]; then
    echo "Error: <build_dir> argument is required"
    echo "Usage: tvosify.sh <build_dir> <environment>"
    exit 1
fi

if [ -z "$ENVIRONMENT" ]; then
    echo "Error: <environment> argument is required (device or simulator)"
    echo "Usage: tvosify.sh <build_dir> <environment>"
    exit 1
fi

if [ "$ENVIRONMENT" != "device" ] && [ "$ENVIRONMENT" != "simulator" ]; then
    echo "Error: <environment> must be 'device' or 'simulator', got '$ENVIRONMENT'"
    exit 1
fi

if [ ! -d "$BUILD_DIR" ]; then
    echo "Error: Build directory does not exist: $BUILD_DIR"
    exit 1
fi

# Resolve SDK paths based on environment
if [ "$ENVIRONMENT" = "device" ]; then
    TVOS_SDK_PATH=$(xcrun --sdk appletvos --show-sdk-path)
    MIN_VERSION_FLAG="-mtvos-version-min=15.0"
else
    TVOS_SDK_PATH=$(xcrun --sdk appletvsimulator --show-sdk-path)
    MIN_VERSION_FLAG="-mtvos-simulator-version-min=15.0"
fi

# Resolve iOS SDK paths (these are what GN generates with target_os="ios")
IOS_SDK_PATH_DEVICE=$(xcrun --sdk iphoneos --show-sdk-path)
IOS_SDK_PATH_SIM=$(xcrun --sdk iphonesimulator --show-sdk-path)

echo "tvosify: Patching build directory '$BUILD_DIR' for tvOS $ENVIRONMENT"
echo "  tvOS SDK:          $TVOS_SDK_PATH"
echo "  iOS device SDK:    $IOS_SDK_PATH_DEVICE"
echo "  iOS simulator SDK: $IOS_SDK_PATH_SIM"
echo "  Min version flag:  $MIN_VERSION_FLAG"

# Replace iOS SDK sysroot paths with tvOS SDK sysroot in all .ninja files
# Also replace iOS min-version deployment target flags with tvOS equivalents
find "$BUILD_DIR" -name "*.ninja" -exec sed -i '' \
    -e "s|${IOS_SDK_PATH_DEVICE}|${TVOS_SDK_PATH}|g" \
    -e "s|${IOS_SDK_PATH_SIM}|${TVOS_SDK_PATH}|g" \
    -e "s|-miphoneos-version-min=[0-9.]*|${MIN_VERSION_FLAG}|g" \
    -e "s|-mios-simulator-version-min=[0-9.]*|${MIN_VERSION_FLAG}|g" \
    {} +

echo "tvosify: Done. Build directory patched for tvOS $ENVIRONMENT."
