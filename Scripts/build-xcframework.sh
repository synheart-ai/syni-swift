#!/bin/bash
#
# Build SyniRuntime.xcframework from syni-runtime Rust library
#
# This script:
# 1. Builds syni-runtime for all Apple targets
# 2. Creates a universal static library for each platform
# 3. Packages everything into an XCFramework
#
# Prerequisites:
# - Rust with Apple targets installed
# - Xcode command line tools
#
# Usage:
#   ./Scripts/build-xcframework.sh
#
# Output:
#   Frameworks/SyniRuntime.xcframework

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
RUNTIME_DIR="${PROJECT_DIR}/../syni-runtime"
OUTPUT_DIR="${PROJECT_DIR}/Frameworks"
FRAMEWORK_NAME="SyniRuntime"
BUILD_DIR="${PROJECT_DIR}/.build/xcframework"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Log helpers write to stderr so command substitutions
# (e.g. `path=$(create_framework ...)`) don't pick them up alongside
# the intended return value.
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1" >&2
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# Rust targets for Apple platforms
TARGETS_IOS_DEVICE="aarch64-apple-ios"
TARGETS_IOS_SIMULATOR="aarch64-apple-ios-sim x86_64-apple-ios"
TARGETS_MACOS="aarch64-apple-darwin x86_64-apple-darwin"

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    if ! command -v rustc &> /dev/null; then
        log_error "Rust is not installed. Install from https://rustup.rs"
        exit 1
    fi

    if ! command -v xcrun &> /dev/null; then
        log_error "Xcode command line tools not found. Run: xcode-select --install"
        exit 1
    fi

    if [[ ! -d "$RUNTIME_DIR" ]]; then
        log_error "syni-runtime not found at: $RUNTIME_DIR"
        exit 1
    fi

    # Install required Rust targets
    log_info "Installing Rust targets..."
    rustup target add $TARGETS_IOS_DEVICE $TARGETS_IOS_SIMULATOR $TARGETS_MACOS 2>/dev/null || true
}

# Build for a specific target
build_target() {
    local target=$1
    log_info "Building for target: $target"

    # Pin deployment targets so cargo's linker doesn't emit older-iOS
    # min versions that miss intrinsics (e.g. ___chkstk_darwin) used by
    # transitive Rust deps. Values match the Info.plist below.
    local ios_target="16.0"
    local macos_target="13.0"

    cd "$RUNTIME_DIR"
    case "$target" in
        *-apple-ios|*-apple-ios-sim)
            IPHONEOS_DEPLOYMENT_TARGET="$ios_target" \
                cargo build --release --target "$target" -p syni_ffi
            ;;
        *-apple-darwin)
            MACOSX_DEPLOYMENT_TARGET="$macos_target" \
                cargo build --release --target "$target" -p syni_ffi
            ;;
        *)
            cargo build --release --target "$target" -p syni_ffi
            ;;
    esac
}

# Create universal library from multiple architectures
create_universal_lib() {
    local output_lib=$1
    shift
    local input_libs=("$@")

    log_info "Creating universal library: $output_lib"

    if [[ ${#input_libs[@]} -eq 1 ]]; then
        cp "${input_libs[0]}" "$output_lib"
    else
        lipo -create "${input_libs[@]}" -output "$output_lib"
    fi
}

# Create a framework bundle for a platform
create_framework() {
    local platform=$1
    local lib_path=$2
    local framework_dir="${BUILD_DIR}/${platform}/${FRAMEWORK_NAME}.framework"

    log_info "Creating framework for platform: $platform"

    mkdir -p "$framework_dir/Headers"

    # Copy the static library
    cp "$lib_path" "$framework_dir/${FRAMEWORK_NAME}"

    # Copy headers
    cp "${RUNTIME_DIR}/ffi/c_api.h" "$framework_dir/Headers/syni_runtime.h"

    # Create umbrella header
    cat > "$framework_dir/Headers/${FRAMEWORK_NAME}.h" << EOF
//
// ${FRAMEWORK_NAME}.h
// Syni Runtime - Cross-platform LLM inference engine
//

#ifndef ${FRAMEWORK_NAME}_h
#define ${FRAMEWORK_NAME}_h

#include "syni_runtime.h"

#endif /* ${FRAMEWORK_NAME}_h */
EOF

    # Create module map
    mkdir -p "$framework_dir/Modules"
    # Frameworks referenced by transitive Rust deps:
    # - SystemConfiguration: proxy / reachability symbols pulled in by reqwest
    # - Security: TLS via the system Security framework
    # - CFNetwork: networking primitives used by reqwest's URL parser
    # libc++ is required because syni-core links candle's C++ tokenizer.
    cat > "$framework_dir/Modules/module.modulemap" << EOF
framework module ${FRAMEWORK_NAME} {
    umbrella header "${FRAMEWORK_NAME}.h"
    export *
    module * { export * }

    link "c++"
    link framework "SystemConfiguration"
    link framework "Security"
    link framework "CFNetwork"
}
EOF

    # Create Info.plist
    local min_version="16.0"
    local platform_name="iPhoneOS"
    case "$platform" in
        ios-arm64)
            platform_name="iPhoneOS"
            ;;
        ios-arm64_x86_64-simulator)
            platform_name="iPhoneSimulator"
            ;;
        macos-arm64_x86_64)
            platform_name="MacOSX"
            min_version="13.0"
            ;;
    esac

    cat > "$framework_dir/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>${FRAMEWORK_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>com.synheart.syni-runtime</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${FRAMEWORK_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>FMWK</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>MinimumOSVersion</key>
    <string>${min_version}</string>
    <key>CFBundleSupportedPlatforms</key>
    <array>
        <string>${platform_name}</string>
    </array>
</dict>
</plist>
EOF

    echo "$framework_dir"
}

# Main build process
main() {
    log_info "Building ${FRAMEWORK_NAME}.xcframework"
    log_info "Runtime directory: $RUNTIME_DIR"
    log_info "Output directory: $OUTPUT_DIR"

    check_prerequisites

    # Clean build directory
    rm -rf "$BUILD_DIR"
    mkdir -p "$BUILD_DIR"

    # Build all targets
    log_info "Building for all Apple targets..."
    for target in $TARGETS_IOS_DEVICE $TARGETS_IOS_SIMULATOR $TARGETS_MACOS; do
        build_target "$target"
    done

    # Create platform-specific libraries
    local target_dir="${RUNTIME_DIR}/target"

    # iOS Device (arm64 only)
    mkdir -p "${BUILD_DIR}/libs/ios-device"
    cp "${target_dir}/aarch64-apple-ios/release/libsyni_ffi.a" \
       "${BUILD_DIR}/libs/ios-device/libsyni_ffi.a"

    # iOS Simulator (arm64 + x86_64 universal)
    mkdir -p "${BUILD_DIR}/libs/ios-simulator"
    create_universal_lib \
        "${BUILD_DIR}/libs/ios-simulator/libsyni_ffi.a" \
        "${target_dir}/aarch64-apple-ios-sim/release/libsyni_ffi.a" \
        "${target_dir}/x86_64-apple-ios/release/libsyni_ffi.a"

    # macOS (arm64 + x86_64 universal)
    mkdir -p "${BUILD_DIR}/libs/macos"
    create_universal_lib \
        "${BUILD_DIR}/libs/macos/libsyni_ffi.a" \
        "${target_dir}/aarch64-apple-darwin/release/libsyni_ffi.a" \
        "${target_dir}/x86_64-apple-darwin/release/libsyni_ffi.a"

    # Create framework bundles
    ios_device_framework=$(create_framework "ios-arm64" "${BUILD_DIR}/libs/ios-device/libsyni_ffi.a")
    ios_sim_framework=$(create_framework "ios-arm64_x86_64-simulator" "${BUILD_DIR}/libs/ios-simulator/libsyni_ffi.a")
    macos_framework=$(create_framework "macos-arm64_x86_64" "${BUILD_DIR}/libs/macos/libsyni_ffi.a")

    # Create XCFramework
    log_info "Creating XCFramework..."
    rm -rf "${OUTPUT_DIR}/${FRAMEWORK_NAME}.xcframework"

    xcodebuild -create-xcframework \
        -framework "$ios_device_framework" \
        -framework "$ios_sim_framework" \
        -framework "$macos_framework" \
        -output "${OUTPUT_DIR}/${FRAMEWORK_NAME}.xcframework"

    # Clean up
    rm -rf "$BUILD_DIR"

    log_info "Successfully created: ${OUTPUT_DIR}/${FRAMEWORK_NAME}.xcframework"

    # Print framework info
    echo ""
    log_info "Framework contents:"
    ls -la "${OUTPUT_DIR}/${FRAMEWORK_NAME}.xcframework/"

    echo ""
    log_info "To use in Xcode:"
    echo "  1. Drag ${FRAMEWORK_NAME}.xcframework into your project"
    echo "  2. Select 'Embed & Sign' in Frameworks, Libraries, and Embedded Content"
    echo "  3. Import with: import ${FRAMEWORK_NAME}"
}

main "$@"
