#!/bin/bash
set -e

# run-android-tests.sh - Run Android integration tests with emulator management
#
# Usage:
#   ./run-android-tests.sh              # Headless, keep emulator running
#   ./run-android-tests.sh --gui        # Show emulator window
#   ./run-android-tests.sh --stop-emulator  # Stop emulator after tests
#   ./run-android-tests.sh --avd <name> # Use specific AVD

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default configuration
AVD_NAME="Medium_Phone_API_35"
HEADLESS=true
STOP_EMULATOR=false
BOOT_TIMEOUT=120
EMULATOR_STARTED_BY_US=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
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
            echo "Run Android integration tests with automatic emulator management."
            echo ""
            echo "Options:"
            echo "  --gui            Show emulator window (default: headless)"
            echo "  --stop-emulator  Stop emulator after tests (default: keep running)"
            echo "  --avd <name>     Use specific AVD (default: Medium_Phone_API_35)"
            echo "  --help, -h       Show this help message"
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

# Check if emulator is already running
get_emulator_serial() {
    "$ADB" devices 2>/dev/null | grep "emulator-" | head -1 | cut -f1
}

emulator_running() {
    [ -n "$(get_emulator_serial)" ]
}

if emulator_running; then
    echo -e "  ${GREEN}✓${NC} Emulator already running"
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
fi

# Get emulator serial for targeted commands
EMU_SERIAL=$(get_emulator_serial)
ADB_EMU="$ADB -s $EMU_SERIAL"
echo -e "  ${GREEN}✓${NC} Using emulator: $EMU_SERIAL"

# Wait for boot to complete
echo "  Waiting for boot to complete (timeout: ${BOOT_TIMEOUT}s)..."
boot_completed=false
for i in $(seq 1 $BOOT_TIMEOUT); do
    if [ "$($ADB_EMU shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ]; then
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
    echo -e "${RED}ERROR: Emulator boot timed out after ${BOOT_TIMEOUT}s${NC}"
    [ "$EMULATOR_STARTED_BY_US" = true ] && kill $EMULATOR_PID 2>/dev/null || true
    exit 1
fi

echo -e "  ${GREEN}✓${NC} Emulator booted successfully"

# Give it a moment to settle
sleep 2

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
if [ "$STOP_EMULATOR" = true ] && [ "$EMULATOR_STARTED_BY_US" = true ]; then
    echo ""
    echo "Stopping emulator..."
    $ADB_EMU emu kill 2>/dev/null || true
fi

exit $TEST_EXIT_CODE
