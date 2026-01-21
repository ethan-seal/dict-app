#!/bin/bash
set -e

echo "=== Building Android Native Library ==="

# Configuration - use user's SDK directory
ANDROID_SDK="$HOME/android/sdk"
NDK_VERSION="26.1.10909125"

# Verify NDK installation
if [ ! -d "$ANDROID_SDK/ndk/$NDK_VERSION" ]; then
    echo "ERROR: NDK not found at $ANDROID_SDK/ndk/$NDK_VERSION"
    echo "Please install the NDK first"
    exit 1
fi

export ANDROID_NDK_HOME="$ANDROID_SDK/ndk/$NDK_VERSION"
export ANDROID_HOME="$ANDROID_SDK"
echo "Using NDK: $ANDROID_NDK_HOME"

# Step 2: Install cargo-ndk if not present
if ! command -v cargo-ndk &> /dev/null; then
    echo "Installing cargo-ndk..."
    cargo install cargo-ndk
fi

# Step 3: Add Rust Android targets
echo "Adding Rust Android targets..."
rustup target add aarch64-linux-android armv7-linux-androideabi x86_64-linux-android 2>/dev/null || true

# Step 4: Build the native library
echo "Building native library for Android..."
cd "$(dirname "$0")"

cargo ndk \
    -t arm64-v8a \
    -t armeabi-v7a \
    -t x86_64 \
    -o ./android/app/src/main/jniLibs \
    build --release -p dict-core

echo ""
echo "=== Build complete! ==="
echo "Libraries built:"
find ./android/app/src/main/jniLibs -name "*.so" -exec ls -lh {} \;
