#!/bin/bash

# collect-device-logs.sh - Collect diagnostic logs from a connected device
#
# Usage:
#   ./collect-device-logs.sh                    # Start collecting logs in foreground
#   ./collect-device-logs.sh --run-tests        # Clear logs, run tests, then collect
#   ./collect-device-logs.sh --clear            # Just clear logs
#   ./collect-device-logs.sh --file output.log  # Save to file

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Detect SDK
if [ -d "$HOME/Android/Sdk" ]; then
    SDK_ROOT="$HOME/Android/Sdk"
elif [ -n "$ANDROID_SDK_ROOT" ]; then
    SDK_ROOT="$ANDROID_SDK_ROOT"
elif [ -n "$ANDROID_HOME" ]; then
    SDK_ROOT="$ANDROID_HOME"
else
    echo -e "${RED}ERROR: Android SDK not found${NC}"
    exit 1
fi

ADB="$SDK_ROOT/platform-tools/adb"
[ ! -x "$ADB" ] && ADB="adb"

# Default options
CLEAR_LOGS=false
RUN_TESTS=false
OUTPUT_FILE=""
FILTER_TAGS="DeviceDiagnostic:D DictCore:D DictViewModel:D"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --clear)
            CLEAR_LOGS=true
            shift
            ;;
        --run-tests)
            RUN_TESTS=true
            CLEAR_LOGS=true
            shift
            ;;
        --file)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        --all)
            FILTER_TAGS=""
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Collect diagnostic logs from a connected Android device."
            echo ""
            echo "Options:"
            echo "  --clear       Clear existing logs before collecting"
            echo "  --run-tests   Clear logs, run diagnostic tests, then collect"
            echo "  --file <path> Save logs to file instead of stdout"
            echo "  --all         Show all logs (not just dict-app tags)"
            echo "  --help        Show this help"
            echo ""
            echo "Default tags: $FILTER_TAGS"
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            exit 1
            ;;
    esac
done

# Check for connected device
DEVICE=$($ADB devices | grep -E "^\S+\s+device$" | head -1 | cut -f1)
if [ -z "$DEVICE" ]; then
    echo -e "${RED}ERROR: No device connected${NC}"
    echo ""
    echo "Connect a device with USB debugging enabled, then retry."
    exit 1
fi

echo -e "${GREEN}Connected device: $DEVICE${NC}"
DEVICE_MODEL=$($ADB -s "$DEVICE" shell getprop ro.product.model 2>/dev/null | tr -d '\r')
DEVICE_ABI=$($ADB -s "$DEVICE" shell getprop ro.product.cpu.abi 2>/dev/null | tr -d '\r')
echo -e "${BLUE}Model: $DEVICE_MODEL, ABI: $DEVICE_ABI${NC}"

# Clear logs if requested
if [ "$CLEAR_LOGS" = true ]; then
    echo -e "${YELLOW}Clearing logs...${NC}"
    $ADB -s "$DEVICE" logcat -c
fi

# Run tests if requested
if [ "$RUN_TESTS" = true ]; then
    echo ""
    echo -e "${YELLOW}Running diagnostic tests...${NC}"
    cd android
    ./gradlew connectedAndroidTest -Pandroid.testInstrumentationRunnerArguments.class=org.example.dictapp.DeviceDiagnosticTest || true
    cd ..
    echo ""
    echo -e "${GREEN}Tests complete. Collecting logs...${NC}"
    echo ""
fi

# Collect logs
if [ -n "$OUTPUT_FILE" ]; then
    echo -e "${YELLOW}Saving logs to: $OUTPUT_FILE${NC}"
    if [ -n "$FILTER_TAGS" ]; then
        $ADB -s "$DEVICE" logcat -d $FILTER_TAGS '*:S' > "$OUTPUT_FILE"
    else
        $ADB -s "$DEVICE" logcat -d > "$OUTPUT_FILE"
    fi
    echo -e "${GREEN}Done. View with: less $OUTPUT_FILE${NC}"
else
    echo -e "${YELLOW}Streaming logs (Ctrl+C to stop)...${NC}"
    echo "==========================================="
    if [ -n "$FILTER_TAGS" ]; then
        $ADB -s "$DEVICE" logcat $FILTER_TAGS '*:S'
    else
        $ADB -s "$DEVICE" logcat
    fi
fi
