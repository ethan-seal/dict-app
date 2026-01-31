#!/bin/bash
set -e

# run-android-tests.sh - Run Android integration tests with emulator/device management
#
# Usage:
#   ./run-android-tests.sh              # Headless emulator, keep running after tests
#   ./run-android-tests.sh --device     # Prefer physical device over emulator
#   ./run-android-tests.sh --gui        # Show emulator window
#   ./run-android-tests.sh --stop-emulator  # Stop emulator after tests
#   ./run-android-tests.sh --avd <name> # Use specific AVD
#   ./run-android-tests.sh --serial <id> # Use specific device/emulator serial

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default configuration
AVD_NAME="Medium_Phone_API_35"
HEADLESS=true
STOP_EMULATOR=false
BOOT_TIMEOUT=120
EMULATOR_STARTED_BY_US=false
PREFER_DEVICE=false
TARGET_SERIAL=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --device)
            PREFER_DEVICE=true
            shift
            ;;
        --serial)
            TARGET_SERIAL="$2"
            shift 2
            ;;
        --gui)
            HEADLESS=false
            shift
            ;;
        --stop-emulator)
            STOP_EMULATOR=true
            shift
            ;;
        --avd)
            AVD_NAME="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Run Android integration tests with automatic emulator/device management."
            echo ""
            echo "Options:"
            echo "  --device         Prefer physical device over emulator"
            echo "  --serial <id>    Use specific device/emulator serial"
            echo "  --gui            Show emulator window (default: headless)"
            echo "  --stop-emulator  Stop emulator after tests (default: keep running)"
            echo "  --avd <name>     Use specific AVD (default: Medium_Phone_API_35)"
            echo "  --help, -h       Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0 --device                  # Run on connected phone"
            echo "  $0 --serial 1A2B3C4D         # Run on specific device"
            echo "  $0                           # Run on emulator"
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Detect Android SDK
# Prefer user's home SDK (where AVDs typically live) over system SDK
if [ -d "$HOME/Android/Sdk" ]; then
    SDK_ROOT="$HOME/Android/Sdk"
elif [ -d "$HOME/android/sdk" ]; then
    SDK_ROOT="$HOME/android/sdk"
elif [ -n "$ANDROID_SDK_ROOT" ]; then
    SDK_ROOT="$ANDROID_SDK_ROOT"
elif [ -n "$ANDROID_HOME" ]; then
    SDK_ROOT="$ANDROID_HOME"
else
    echo -e "${RED}ERROR: Android SDK not found${NC}"
    echo "Set ANDROID_SDK_ROOT or ANDROID_HOME environment variable"
    exit 1
fi

# Export for emulator to find AVDs
export ANDROID_SDK_ROOT="$SDK_ROOT"
export ANDROID_HOME="$SDK_ROOT"

EMULATOR="$SDK_ROOT/emulator/emulator"
ADB="$SDK_ROOT/platform-tools/adb"

# Fall back to PATH if SDK tools not found
[ ! -x "$ADB" ] && ADB="adb"
[ ! -x "$EMULATOR" ] && EMULATOR="emulator"

echo "=== Android Integration Test Runner ==="
echo ""

# Check prerequisites
echo "Checking prerequisites..."

# Check native libraries
if [ ! -f "android/app/src/main/jniLibs/x86_64/libdict_core.so" ]; then
    echo -e "${RED}ERROR: Native libraries not found${NC}"
    echo "Run ./build-android-native.sh first"
    exit 1
fi
echo -e "  ${GREEN}✓${NC} Native libraries found"

# Check AVD exists
if ! "$EMULATOR" -list-avds 2>/dev/null | grep -q "^${AVD_NAME}$"; then
    echo -e "${RED}ERROR: AVD '$AVD_NAME' not found${NC}"
    echo "Available AVDs:"
    "$EMULATOR" -list-avds 2>/dev/null | sed 's/^/  /'
    exit 1
fi
echo -e "  ${GREEN}✓${NC} AVD '$AVD_NAME' exists"

# Get list of connected devices (physical devices, not emulators)
get_physical_devices() {
    "$ADB" devices 2>/dev/null | grep -v "emulator-" | grep -E "^\S+\s+device$" | cut -f1
}

# Get list of running emulators
get_emulator_serial() {
    "$ADB" devices 2>/dev/null | grep "emulator-" | grep -E "\s+device$" | head -1 | cut -f1
}

emulator_running() {
    [ -n "$(get_emulator_serial)" ]
}

# Determine which device/emulator to use
SELECTED_SERIAL=""
USE_EMULATOR=true

if [ -n "$TARGET_SERIAL" ]; then
    # User specified a serial
    echo "Using specified serial: $TARGET_SERIAL"
    SELECTED_SERIAL="$TARGET_SERIAL"
    if [[ "$TARGET_SERIAL" == emulator-* ]]; then
        USE_EMULATOR=true
    else
        USE_EMULATOR=false
    fi
elif [ "$PREFER_DEVICE" = true ]; then
    # Look for physical devices first
    DEVICES=$(get_physical_devices)
    if [ -n "$DEVICES" ]; then
        SELECTED_SERIAL=$(echo "$DEVICES" | head -1)
        USE_EMULATOR=false
        echo -e "  ${GREEN}✓${NC} Found physical device: $SELECTED_SERIAL"
    else
        echo -e "  ${YELLOW}!${NC} No physical device found, falling back to emulator"
    fi
fi

if [ -z "$SELECTED_SERIAL" ] && [ "$USE_EMULATOR" = true ]; then
    # Use emulator
    if emulator_running; then
        SELECTED_SERIAL=$(get_emulator_serial)
        echo -e "  ${GREEN}✓${NC} Emulator already running: $SELECTED_SERIAL"
    else
        echo -e "  ${YELLOW}→${NC} Starting emulator..."
        EMULATOR_STARTED_BY_US=true
        
        # Build emulator command
        EMU_ARGS="-avd $AVD_NAME -no-snapshot-save"
        if [ "$HEADLESS" = true ]; then
            EMU_ARGS="$EMU_ARGS -no-window -no-audio -gpu swiftshader_indirect"
        fi
        
        # Start emulator in background
        "$EMULATOR" $EMU_ARGS &>/dev/null &
        EMULATOR_PID=$!
        
        # Wait for emulator to appear
        echo "  Waiting for emulator to start..."
        for i in $(seq 1 $BOOT_TIMEOUT); do
            if emulator_running; then
                break
            fi
            sleep 1
        done
        
        if ! emulator_running; then
            echo -e "${RED}ERROR: Emulator failed to start${NC}"
            kill $EMULATOR_PID 2>/dev/null || true
            exit 1
        fi
        SELECTED_SERIAL=$(get_emulator_serial)
    fi
fi

if [ -z "$SELECTED_SERIAL" ]; then
    echo -e "${RED}ERROR: No device or emulator available${NC}"
    echo ""
    echo "Either:"
    echo "  1. Connect a physical device with USB debugging enabled"
    echo "  2. Let the script start an emulator (don't use --device)"
    exit 1
fi

# Set the target serial for gradle
export ANDROID_SERIAL="$SELECTED_SERIAL"
ADB_TARGET="$ADB -s $SELECTED_SERIAL"
echo -e "  ${GREEN}✓${NC} Using device: $SELECTED_SERIAL"

# Get device info for logging
DEVICE_MODEL=$($ADB_TARGET shell getprop ro.product.model 2>/dev/null | tr -d '\r' || echo "unknown")
DEVICE_ABI=$($ADB_TARGET shell getprop ro.product.cpu.abi 2>/dev/null | tr -d '\r' || echo "unknown")
echo -e "  ${BLUE}ℹ${NC} Device: $DEVICE_MODEL (ABI: $DEVICE_ABI)"

# Wait for device to be ready
echo "  Waiting for device to be ready (timeout: ${BOOT_TIMEOUT}s)..."
boot_completed=false
for i in $(seq 1 $BOOT_TIMEOUT); do
    if [ "$($ADB_TARGET shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ]; then
        boot_completed=true
        break
    fi
    sleep 1
    # Show progress every 10 seconds
    if [ $((i % 10)) -eq 0 ]; then
        echo "    ... ${i}s"
    fi
done

if [ "$boot_completed" = false ]; then
    echo -e "${RED}ERROR: Device boot timed out after ${BOOT_TIMEOUT}s${NC}"
    [ "$EMULATOR_STARTED_BY_US" = true ] && kill $EMULATOR_PID 2>/dev/null || true
    exit 1
fi

echo -e "  ${GREEN}✓${NC} Device ready"

# Give it a moment to settle (less time for physical devices)
if [ "$USE_EMULATOR" = true ]; then
    sleep 2
else
    sleep 1
fi

echo ""
echo "Running integration tests..."
echo ""

# Run the tests
cd android
TEST_EXIT_CODE=0
./gradlew connectedAndroidTest || TEST_EXIT_CODE=$?
cd ..

echo ""

# Report results
if [ $TEST_EXIT_CODE -eq 0 ]; then
    echo -e "${GREEN}=== Tests passed ===${NC}"
else
    echo -e "${RED}=== Tests failed (exit code: $TEST_EXIT_CODE) ===${NC}"
fi

# Show report location
REPORT_PATH="android/app/build/reports/androidTests/connected/index.html"
if [ -f "$REPORT_PATH" ]; then
    echo ""
    echo "Test report: file://$SCRIPT_DIR/$REPORT_PATH"
fi

# Cleanup
if [ "$STOP_EMULATOR" = true ] && [ "$EMULATOR_STARTED_BY_US" = true ] && [ "$USE_EMULATOR" = true ]; then
    echo ""
    echo "Stopping emulator..."
    $ADB_TARGET emu kill 2>/dev/null || true
fi

exit $TEST_EXIT_CODE
