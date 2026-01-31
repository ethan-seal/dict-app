#!/bin/bash
set -e

# run-e2e.sh - End-to-end testing and capture script for Android app
#
# Usage:
#   ./run-e2e.sh <command> --target device|emulator [OPTIONS]
#
# Commands:
#   build     Build native libraries and APKs
#   install   Install app on target
#   logs      Collect logs from target
#   capture   Capture screenshots and video
#   test      Run tests
#   clean     Clean build artifacts
#
# Examples:
#   ./run-e2e.sh build --target emulator
#   ./run-e2e.sh install --target device
#   ./run-e2e.sh capture --target emulator --no-video
#   ./run-e2e.sh test --target device --class DeviceDiagnosticTest

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# Source backend library
source "$SCRIPT_DIR/lib/android-backend.sh"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Default configuration
TARGET=""
SERIAL=""
SKIP_BUILD=false
CAPTURE_VIDEO=true
SKIP_DARK=false
TEST_CLASS=""

# Print usage
usage() {
    cat << EOF
Usage: $0 <command> --target device|emulator [OPTIONS]

Commands:
  build       Build native libraries and APKs
  install     Install app on target
  logs        Collect logs from target
  capture     Capture screenshots and video
  test        Run tests
  clean       Clean build artifacts

Global Options:
  --target device|emulator    Target device type (REQUIRED)
  --serial <id>              Use specific device/emulator
  --help, -h                 Show this help

Build Options:
  --native-only              Build only native libraries
  --apk-only                 Build only APKs

Install Options:
  --app-only                 Install only app APK
  --test-only                Install only test APK

Capture Options:
  --no-video                 Skip video recording
  --skip-dark                Skip dark mode captures
  --skip-build               Skip build/install (use existing APKs)

Test Options:
  --class <name>             Run specific test class

Logs Options:
  --clear                    Clear logcat before collecting
  --filter <tags>            Logcat filter (e.g., "DictCore:D *:S")

Examples:
  $0 build --target emulator
  $0 install --target device --serial 46211FDJH001Q2
  $0 capture --target emulator --no-video
  $0 test --target device --class DeviceDiagnosticTest
  $0 logs --target device --filter "DictCore:D DictViewModel:D *:S"

EOF
    exit 0
}

# Check for help first
for arg in "$@"; do
    if [[ "$arg" == "--help" ]] || [[ "$arg" == "-h" ]]; then
        usage
    fi
done

# Parse global options
COMMAND=""
if [[ $# -gt 0 ]]; then
    COMMAND="$1"
    shift
fi

# Additional command-specific options
NATIVE_ONLY=false
APK_ONLY=false
APP_ONLY=false
TEST_ONLY=false
CLEAR_LOGS=false
LOG_FILTER=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --target)
            TARGET="$2"
            shift 2
            ;;
        --serial)
            SERIAL="$2"
            shift 2
            ;;
        --skip-build)
            SKIP_BUILD=true
            shift
            ;;
        --no-video)
            CAPTURE_VIDEO=false
            shift
            ;;
        --skip-dark)
            SKIP_DARK=true
            shift
            ;;
        --native-only)
            NATIVE_ONLY=true
            shift
            ;;
        --apk-only)
            APK_ONLY=true
            shift
            ;;
        --app-only)
            APP_ONLY=true
            shift
            ;;
        --test-only)
            TEST_ONLY=true
            shift
            ;;
        --class)
            TEST_CLASS="$2"
            shift 2
            ;;
        --clear)
            CLEAR_LOGS=true
            shift
            ;;
        --filter)
            LOG_FILTER="$2"
            shift 2
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            echo "Run with --help for usage"
            exit 1
            ;;
    esac
done

# Validate command
if [ -z "$COMMAND" ]; then
    echo -e "${RED}ERROR: No command specified${NC}"
    usage
fi

# Validate target for commands that need it
case "$COMMAND" in
    build|clean)
        # These don't need a target
        ;;
    *)
        if [ -z "$TARGET" ]; then
            echo -e "${RED}ERROR: --target is required for '$COMMAND' command${NC}"
            usage
        fi
        
        if [[ "$TARGET" != "device" && "$TARGET" != "emulator" ]]; then
            echo -e "${RED}ERROR: --target must be 'device' or 'emulator'${NC}"
            exit 1
        fi
        ;;
esac

# Find Android SDK
find_android_sdk() {
    if [ -d "$HOME/Android/Sdk" ]; then
        export ANDROID_SDK_ROOT="$HOME/Android/Sdk"
    elif [ -d "$HOME/android/sdk" ]; then
        export ANDROID_SDK_ROOT="$HOME/android/sdk"
    elif [ -n "$ANDROID_SDK_ROOT" ]; then
        : # Already set
    elif [ -n "$ANDROID_HOME" ]; then
        export ANDROID_SDK_ROOT="$ANDROID_HOME"
    else
        echo -e "${RED}ERROR: Android SDK not found${NC}"
        exit 1
    fi
    export ANDROID_HOME="$ANDROID_SDK_ROOT"
}

# ============================================================
# Command: build
# ============================================================
cmd_build() {
    echo -e "${BLUE}=== Building ===${NC}"
    echo ""
    
    # Build native libraries
    if [ "$APK_ONLY" = false ]; then
        echo -e "${BLUE}Building native libraries...${NC}"
        ./build-android-native.sh
        echo -e "  ${GREEN}✓${NC} Native libraries built"
        echo ""
    fi
    
    # Build APKs
    if [ "$NATIVE_ONLY" = false ]; then
        echo -e "${BLUE}Building APKs...${NC}"
        cd android
        ./gradlew assembleDebug assembleDebugAndroidTest --quiet
        cd ..
        echo -e "  ${GREEN}✓${NC} APKs built"
        echo ""
    fi
    
    echo -e "${GREEN}Build complete!${NC}"
}

# ============================================================
# Command: install
# ============================================================
cmd_install() {
    echo -e "${BLUE}=== Installing ===${NC}"
    echo ""
    
    # Initialize backend
    local backend_args="--target $TARGET"
    [ -n "$SERIAL" ] && backend_args="$backend_args --serial $SERIAL"
    backend_init $backend_args || exit $?
    
    local info
    info=$(backend_get_info)
    local model=$(echo "$info" | grep "^model=" | cut -d= -f2)
    local serial=$(echo "$info" | grep "^serial=" | cut -d= -f2)
    
    echo -e "Target: ${GREEN}$model${NC} ($serial)"
    echo ""
    
    # APK paths
    local app_apk="$SCRIPT_DIR/android/app/build/outputs/apk/debug/app-debug.apk"
    local test_apk="$SCRIPT_DIR/android/app/build/outputs/apk/androidTest/debug/app-debug-androidTest.apk"
    
    # Install app
    if [ "$TEST_ONLY" = false ]; then
        if [ ! -f "$app_apk" ]; then
            echo -e "${RED}ERROR: App APK not found${NC}"
            echo "Run: $0 build first"
            exit 1
        fi
        
        echo -e "${BLUE}Installing app...${NC}"
        backend_install_apk "$app_apk" | grep -v "^Performing" || true
        echo -e "  ${GREEN}✓${NC} App installed"
    fi
    
    # Install test APK
    if [ "$APP_ONLY" = false ]; then
        if [ ! -f "$test_apk" ]; then
            echo -e "${YELLOW}Note: Test APK not found (run 'build' to create)${NC}"
        else
            echo -e "${BLUE}Installing test APK...${NC}"
            backend_install_apk "$test_apk" | grep -v "^Performing" || true
            echo -e "  ${GREEN}✓${NC} Test APK installed"
        fi
    fi
    
    echo ""
    echo -e "${GREEN}Installation complete!${NC}"
    
    backend_cleanup
}

# ============================================================
# Command: logs
# ============================================================
cmd_logs() {
    echo -e "${BLUE}=== Collecting Logs ===${NC}"
    echo ""
    
    # Initialize backend
    local backend_args="--target $TARGET"
    [ -n "$SERIAL" ] && backend_args="$backend_args --serial $SERIAL"
    backend_init $backend_args || exit $?
    
    local info
    info=$(backend_get_info)
    local model=$(echo "$info" | grep "^model=" | cut -d= -f2)
    local serial=$(echo "$info" | grep "^serial=" | cut -d= -f2)
    
    echo -e "Target: ${GREEN}$model${NC} ($serial)"
    echo ""
    
    # Clear logs if requested
    if [ "$CLEAR_LOGS" = true ]; then
        echo -e "${YELLOW}Clearing logcat...${NC}"
        backend_logcat_clear
        echo ""
    fi
    
    # Setup filter
    local filter_args=""
    if [ -n "$LOG_FILTER" ]; then
        filter_args="-s $LOG_FILTER"
    fi
    
    # Collect logs
    echo -e "${BLUE}Logcat output:${NC}"
    echo -e "${CYAN}─────────────────────────────────────────${NC}"
    backend_logcat -d $filter_args
    
    backend_cleanup
}

# ============================================================
# Command: capture
# ============================================================
cmd_capture() {
    echo -e "${BLUE}=== Capturing Screenshots ===${NC}"
    echo ""
    
    # Need Android SDK if building
    if [ "$SKIP_BUILD" = false ]; then
        find_android_sdk
    fi
    
    # Initialize backend
    local backend_args="--target $TARGET"
    [ -n "$SERIAL" ] && backend_args="$backend_args --serial $SERIAL"
    backend_init $backend_args || exit $?
    
    local info
    info=$(backend_get_info)
    local model=$(echo "$info" | grep "^model=" | cut -d= -f2)
    local serial=$(echo "$info" | grep "^serial=" | cut -d= -f2)
    
    echo -e "Target: ${GREEN}$model${NC} ($serial)"
    echo ""
    
    # Create output directory
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local output_dir="$SCRIPT_DIR/captures/$timestamp"
    local light_dir="$output_dir/screenshots"
    local dark_dir="$output_dir/screenshots-dark"
    mkdir -p "$light_dir" "$dark_dir"
    
    echo "Output: $output_dir"
    echo ""
    
    # Build and install (unless --skip-build)
    if [ "$SKIP_BUILD" = false ]; then
        # Build
        echo -e "${BLUE}Building APKs...${NC}"
        cd android
        ./gradlew assembleDebug assembleDebugAndroidTest --quiet
        cd ..
        echo -e "  ${GREEN}✓${NC} APKs built"
        echo ""
        
        # Install
        local app_apk="$SCRIPT_DIR/android/app/build/outputs/apk/debug/app-debug.apk"
        local test_apk="$SCRIPT_DIR/android/app/build/outputs/apk/androidTest/debug/app-debug-androidTest.apk"
        
        if [ ! -f "$app_apk" ]; then
            echo -e "${RED}ERROR: App APK not found after build${NC}"
            exit 1
        fi
        
        echo -e "${BLUE}Installing APKs...${NC}"
        backend_install_apk "$app_apk" | grep -v "^Performing" || true
        echo -e "  ${GREEN}✓${NC} App installed"
        
        if [ -f "$test_apk" ]; then
            backend_install_apk "$test_apk" | grep -v "^Performing" || true
            echo -e "  ${GREEN}✓${NC} Test APK installed"
        fi
        echo ""
    else
        echo -e "${YELLOW}Skipping build (--skip-build)${NC}"
        echo ""
        
        # Verify app is installed
        if ! backend_app_installed; then
            echo -e "${RED}ERROR: App not installed${NC}"
            echo "Run without --skip-build, or install manually first"
            exit 1
        fi
    fi
    
    # Run capture flow
    local count=0
    
    run_capture_flow() {
        local mode="$1"
        local output_dir="$2"
        
        echo ""
        echo -e "${BLUE}=== $mode Mode: Main Flow ===${NC}"
        
        # Restart app
        echo -e "  ${YELLOW}Restarting app...${NC}"
        backend_restart_app
        
        # Screenshot 01: Empty search
        count=$((count + 1))
        echo -ne "  📸 ${CYAN}$(printf '%02d' $count)_initial_state.png${NC}... "
        backend_screenshot "initial_state" "$output_dir/$(printf '%02d' $count)_initial_state.png"
        echo -e "${GREEN}done${NC}"
        
        # Screenshot 02: Search "hello" + results
        echo -e "  ${YELLOW}Searching 'hello'...${NC}"
        backend_tap_search
        backend_wait 0.3
        backend_type "hello"
        backend_wait 1.5
        backend_key KEYCODE_ESCAPE 2>/dev/null || backend_key KEYCODE_BACK
        backend_wait 0.8
        
        count=$((count + 1))
        echo -ne "  📸 ${CYAN}$(printf '%02d' $count)_search_results.png${NC}... "
        backend_screenshot "search_results" "$output_dir/$(printf '%02d' $count)_search_results.png"
        echo -e "${GREEN}done${NC}"
        
        # Screenshot 03: View hello definition
        echo -e "  ${YELLOW}Opening hello definition...${NC}"
        backend_tap_first_result
        backend_wait 2
        
        count=$((count + 1))
        echo -ne "  📸 ${CYAN}$(printf '%02d' $count)_definition_hello.png${NC}... "
        backend_screenshot "definition_hello" "$output_dir/$(printf '%02d' $count)_definition_hello.png"
        echo -e "${GREEN}done${NC}"
        
        # Screenshot 03b: Scroll to show definitions with examples
        echo -e "  ${YELLOW}Scrolling to definitions...${NC}"
        backend_swipe_up
        backend_wait 0.5
        
        count=$((count + 1))
        echo -ne "  📸 ${CYAN}$(printf '%02d' $count)b_hello_definitions.png${NC}... "
        backend_screenshot "hello_definitions" "$output_dir/$(printf '%02d' $count)b_hello_definitions.png"
        echo -e "${GREEN}done${NC}"
        
        # Screenshot 04: Navigate back
        echo -e "  ${YELLOW}Going back...${NC}"
        backend_back
        backend_wait 0.8
        
        count=$((count + 1))
        echo -ne "  📸 ${CYAN}$(printf '%02d' $count)_back_to_results.png${NC}... "
        backend_screenshot "back_to_results" "$output_dir/$(printf '%02d' $count)_back_to_results.png"
        echo -e "${GREEN}done${NC}"
        
        # Screenshot 05: Search for "apple"
        echo -e "  ${YELLOW}Searching 'apple'...${NC}"
        backend_tap_search
        backend_wait 0.5
        backend_clear_text
        backend_type "apple"
        backend_wait 1.5
        backend_key KEYCODE_ESCAPE 2>/dev/null || backend_key KEYCODE_BACK
        backend_wait 0.8
        
        count=$((count + 1))
        echo -ne "  📸 ${CYAN}$(printf '%02d' $count)_search_apple.png${NC}... "
        backend_screenshot "search_apple" "$output_dir/$(printf '%02d' $count)_search_apple.png"
        echo -e "${GREEN}done${NC}"
        
        # Screenshot 06: View apple definition
        echo -e "  ${YELLOW}Opening apple definition...${NC}"
        backend_tap_first_result
        backend_wait 2
        
        count=$((count + 1))
        echo -ne "  📸 ${CYAN}$(printf '%02d' $count)_definition_apple.png${NC}... "
        backend_screenshot "definition_apple" "$output_dir/$(printf '%02d' $count)_definition_apple.png"
        echo -e "${GREEN}done${NC}"
        
        # Screenshot 06b: Scroll to show definitions
        echo -e "  ${YELLOW}Scrolling to definitions...${NC}"
        backend_swipe_up
        backend_wait 0.5
        
        count=$((count + 1))
        echo -ne "  📸 ${CYAN}$(printf '%02d' $count)b_apple_definitions.png${NC}... "
        backend_screenshot "apple_definitions" "$output_dir/$(printf '%02d' $count)b_apple_definitions.png"
        echo -e "${GREEN}done${NC}"
        
        # Screenshot 06c: Scroll to show translations (if present)
        echo -e "  ${YELLOW}Scrolling to translations...${NC}"
        backend_swipe_up
        backend_wait 0.5
        
        count=$((count + 1))
        echo -ne "  📸 ${CYAN}$(printf '%02d' $count)c_apple_translations.png${NC}... "
        backend_screenshot "apple_translations" "$output_dir/$(printf '%02d' $count)c_apple_translations.png"
        echo -e "${GREEN}done${NC}"
        
        # Screenshot 07: Show no results case
        echo -e "  ${YELLOW}Testing no results...${NC}"
        backend_back
        backend_wait 0.8
        backend_tap_search
        backend_wait 0.5
        backend_clear_text
        backend_type "xyznotfound"
        backend_wait 1.5
        
        count=$((count + 1))
        echo -ne "  📸 ${CYAN}$(printf '%02d' $count)_no_results.png${NC}... "
        backend_screenshot "no_results" "$output_dir/$(printf '%02d' $count)_no_results.png"
        echo -e "${GREEN}done${NC}"
        
        echo -e "  ${GREEN}Main flow: $count screenshots${NC}"
        
        # === OUTLIER CASES ===
        echo ""
        echo -e "${BLUE}=== $mode Mode: Edge Cases ===${NC}"
        
        # Outlier 01: Long etymology (blizzard)
        echo -e "  ${YELLOW}Testing long etymology (blizzard)...${NC}"
        backend_tap_search
        backend_wait 0.5
        backend_clear_text
        backend_type "blizzard"
        backend_wait 1.5
        backend_key KEYCODE_ESCAPE 2>/dev/null || backend_key KEYCODE_BACK
        backend_wait 0.8
        backend_tap_first_result
        backend_wait 2
        
        count=$((count + 1))
        echo -ne "  📸 ${CYAN}outlier_$(printf '%02d' $count)_long_etymology.png${NC}... "
        backend_screenshot "long_etymology" "$output_dir/outlier_$(printf '%02d' $count)_long_etymology.png"
        echo -e "${GREEN}done${NC}"
        
        backend_swipe_up
        backend_wait 0.5
        count=$((count + 1))
        echo -ne "  📸 ${CYAN}outlier_$(printf '%02d' $count)_definitions.png${NC}... "
        backend_screenshot "blizzard_definitions" "$output_dir/outlier_$(printf '%02d' $count)_definitions.png"
        echo -e "${GREEN}done${NC}"
        
        # Outlier 03: Many definitions (draw)
        echo -e "  ${YELLOW}Testing many definitions (draw)...${NC}"
        backend_back
        backend_wait 0.8
        backend_tap_search
        backend_wait 0.5
        backend_clear_text
        backend_type "draw"
        backend_wait 1.5
        backend_key KEYCODE_ESCAPE 2>/dev/null || backend_key KEYCODE_BACK
        backend_wait 0.8
        backend_tap_first_result
        backend_wait 2
        
        count=$((count + 1))
        echo -ne "  📸 ${CYAN}outlier_$(printf '%02d' $count)_many_definitions.png${NC}... "
        backend_screenshot "many_definitions" "$output_dir/outlier_$(printf '%02d' $count)_many_definitions.png"
        echo -e "${GREEN}done${NC}"
        
        backend_swipe_up
        backend_wait 0.5
        count=$((count + 1))
        echo -ne "  📸 ${CYAN}outlier_$(printf '%02d' $count)_draw_mid.png${NC}... "
        backend_screenshot "draw_definitions_mid" "$output_dir/outlier_$(printf '%02d' $count)_draw_mid.png"
        echo -e "${GREEN}done${NC}"
        
        backend_swipe_up
        backend_wait 0.5
        count=$((count + 1))
        echo -ne "  📸 ${CYAN}outlier_$(printf '%02d' $count)_draw_end.png${NC}... "
        backend_screenshot "draw_definitions_end" "$output_dir/outlier_$(printf '%02d' $count)_draw_end.png"
        echo -e "${GREEN}done${NC}"
        
        # Outlier 04: Long definition text (parados)
        echo -e "  ${YELLOW}Testing long definition (parados)...${NC}"
        backend_back
        backend_wait 0.8
        backend_tap_search
        backend_wait 0.5
        backend_clear_text
        backend_type "parados"
        backend_wait 1.5
        backend_key KEYCODE_ESCAPE 2>/dev/null || backend_key KEYCODE_BACK
        backend_wait 0.8
        backend_tap_first_result
        backend_wait 2
        
        count=$((count + 1))
        echo -ne "  📸 ${CYAN}outlier_$(printf '%02d' $count)_long_definition.png${NC}... "
        backend_screenshot "long_definition" "$output_dir/outlier_$(printf '%02d' $count)_long_definition.png"
        echo -e "${GREEN}done${NC}"
        
        backend_swipe_up
        backend_wait 0.5
        count=$((count + 1))
        echo -ne "  📸 ${CYAN}outlier_$(printf '%02d' $count)_scrolled.png${NC}... "
        backend_screenshot "long_definition_scrolled" "$output_dir/outlier_$(printf '%02d' $count)_scrolled.png"
        echo -e "${GREEN}done${NC}"
        
        echo -e "  ${GREEN}Total screenshots: $count${NC}"
    }
    
    # Light mode
    backend_dark_mode no
    count=0
    run_capture_flow "Light" "$light_dir"
    
    # Dark mode
    if [ "$SKIP_DARK" = false ]; then
        backend_dark_mode yes
        backend_wait 2
        count=0
        run_capture_flow "Dark" "$dark_dir"
        
        # Restore light mode
        backend_dark_mode no
    fi
    
    # Generate HTML viewer (reuse from capture-device-auto.sh)
    echo ""
    echo -e "${BLUE}Generating HTML viewer...${NC}"
    generate_html_viewer "$output_dir" "$light_dir" "$dark_dir" "$model" "$timestamp"
    
    # Create symlink to latest
    rm -f "$SCRIPT_DIR/captures/latest" 2>/dev/null || true
    ln -sf "$(basename "$output_dir")" "$SCRIPT_DIR/captures/latest"
    
    echo ""
    echo -e "${GREEN}=== Capture Complete ===${NC}"
    echo ""
    echo "Screenshots saved to: $output_dir"
    echo ""
    ls -la "$light_dir"/*.png 2>/dev/null | wc -l | xargs -I {} echo "Light mode: {} screenshots"
    if [ "$SKIP_DARK" = false ]; then
        ls -la "$dark_dir"/*.png 2>/dev/null | wc -l | xargs -I {} echo "Dark mode:  {} screenshots"
    fi
    echo ""
    echo -e "View: ${CYAN}file://$output_dir/index.html${NC}"
    
    backend_cleanup
}

# Generate HTML viewer (simplified version from capture-device-auto.sh)
generate_html_viewer() {
    local output_dir="$1"
    local light_dir="$2"
    local dark_dir="$3"
    local device_model="$4"
    local timestamp="$5"
    
    local html_file="$output_dir/index.html"
    local has_video="false"
    [ -f "$output_dir/app-flow.mp4" ] && has_video="true"
    
    # Get device info for display
    local device_html=""
    if [ -n "$device_model" ] && [ "$device_model" != "unknown" ]; then
        device_html="<div class=\"device\">$device_model</div>"
    fi
    
    # Get git commit info
    local commit_hash=""
    local commit_html=""
    if git rev-parse --git-dir > /dev/null 2>&1; then
        commit_hash=$(git rev-parse --short HEAD 2>/dev/null || echo "")
        if [ -n "$commit_hash" ]; then
            # Check for dirty state (uncommitted changes)
            if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
                commit_hash="${commit_hash}+"
            fi
            
            # Try to get GitHub URL for linking
            local remote_url=$(git remote get-url origin 2>/dev/null || echo "")
            local github_url=""
            if echo "$remote_url" | grep -qE 'github\.com[:/]'; then
                # Extract owner/repo using sed (more portable than bash regex)
                local owner_repo=$(echo "$remote_url" | sed -E 's|.*github\.com[:/]([^/]+)/([^/]+).*|\1/\2|' | sed 's/\.git$//')
                local owner="${owner_repo%%/*}"
                local repo="${owner_repo##*/}"
                github_url="https://github.com/$owner/$repo/commit/${commit_hash%+}"
            fi
            
            if [ -n "$github_url" ]; then
                commit_html="<div class=\"commit\"><a href=\"$github_url\" target=\"_blank\" rel=\"noopener\">commit: $commit_hash</a></div>"
            else
                commit_html="<div class=\"commit\">commit: $commit_hash</div>"
            fi
        fi
    fi
    
    # Format timestamp for display (e.g., "Jan 21, 2026 at 1:32 PM")
    # TIMESTAMP format: YYYYMMDD_HHMMSS
    local year=${TIMESTAMP:0:4}
    local month=${TIMESTAMP:4:2}
    local day=${TIMESTAMP:6:2}
    local hour=${TIMESTAMP:9:2}
    local min=${TIMESTAMP:11:2}
    
    # Convert month number to name
    local month_name
    case "$month" in
        01) month_name="Jan" ;; 02) month_name="Feb" ;; 03) month_name="Mar" ;;
        04) month_name="Apr" ;; 05) month_name="May" ;; 06) month_name="Jun" ;;
        07) month_name="Jul" ;; 08) month_name="Aug" ;; 09) month_name="Sep" ;;
        10) month_name="Oct" ;; 11) month_name="Nov" ;; 12) month_name="Dec" ;;
    esac
    
    # Convert to 12-hour format with AM/PM
    local hour_num=$((10#$hour))
    local ampm="AM"
    if [ $hour_num -ge 12 ]; then
        ampm="PM"
        [ $hour_num -gt 12 ] && hour_num=$((hour_num - 12))
    fi
    [ $hour_num -eq 0 ] && hour_num=12
    
    # Remove leading zero from day
    local day_num=$((10#$day))
    
    local display_ts="$month_name $day_num, $year at $hour_num:$min $ampm"
    
    # Check if dark screenshots exist
    local has_dark="false"
    if [ -d "$light_dir_DARK" ] && ls "$light_dir_DARK"/*.png &>/dev/null; then
        has_dark="true"
    fi

    # Determine which sections have content
    local has_search=false
    local has_definition=false
    local has_edge_long=false
    local has_edge_many=false
    local has_edge_missing=false
    if [ -d "$light_dir" ]; then
        for img in $(ls -1 "$light_dir"/*.png 2>/dev/null); do
            local fname=$(basename "$img" .png)
            case "$fname" in
                01_*|02_*|04_*|05_*|07_*) has_search=true ;;
                03_*|03b_*|06_*|06b_*|06c_*) has_definition=true ;;
                outlier_01*|outlier_03*|outlier_04*) has_edge_long=true ;;
                outlier_02*) has_edge_many=true ;;
                outlier_05*|outlier_06*) has_edge_missing=true ;;
            esac
        done
    fi

    # Start HTML
    cat > "$html_file" << HTMLHEAD
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>App Capture - $display_ts</title>
    <style>
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: #1a1a2e;
            color: #eee;
            min-height: 100vh;
        }

        /* Sidebar */
        .sidebar {
            position: fixed;
            top: 0;
            left: 0;
            width: 220px;
            height: 100vh;
            background: #151528;
            border-right: 1px solid #2a2a4a;
            padding: 1.5rem 1rem;
            display: flex;
            flex-direction: column;
            gap: 1.5rem;
            z-index: 100;
            overflow-y: auto;
        }
        .sidebar-header {
            text-align: center;
            padding-bottom: 1rem;
            border-bottom: 1px solid #2a2a4a;
        }
        .sidebar-header h1 {
            font-size: 1rem;
            font-weight: 600;
            margin-bottom: 0.25rem;
        }
        .sidebar-header .timestamp {
            color: #888;
            font-size: 0.75rem;
        }
        .sidebar-header .commit {
            color: #666;
            font-size: 0.7rem;
            font-family: monospace;
            margin-top: 0.2rem;
        }
        .sidebar-header .commit a {
            color: #6a9fb5;
            text-decoration: none;
        }
        .sidebar-header .commit a:hover { text-decoration: underline; }
        .sidebar-header .device {
            color: #6a9fb5;
            font-size: 0.75rem;
            margin-top: 0.3rem;
        }

        /* Theme toggle in sidebar */
        .theme-toggle {
            display: flex;
            align-items: center;
            justify-content: center;
            gap: 0.5rem;
            padding: 0.75rem 0;
            border-bottom: 1px solid #2a2a4a;
        }
        .theme-toggle .toggle-label {
            font-size: 0.7rem;
            color: #888;
            text-transform: uppercase;
            letter-spacing: 0.05em;
        }
        .theme-toggle .toggle-label.active { color: #eee; }
        .toggle-switch {
            position: relative;
            width: 40px;
            height: 22px;
            background: #333;
            border-radius: 11px;
            cursor: pointer;
            transition: background 0.2s;
        }
        .toggle-switch.dark { background: #555; }
        .toggle-switch::after {
            content: '';
            position: absolute;
            top: 3px;
            left: 3px;
            width: 16px;
            height: 16px;
            background: #fff;
            border-radius: 50%;
            transition: transform 0.2s;
        }
        .toggle-switch.dark::after { transform: translateX(18px); }

        /* Sidebar navigation */
        .sidebar-nav {
            display: flex;
            flex-direction: column;
            gap: 0.25rem;
        }
        .sidebar-nav a {
            display: block;
            padding: 0.5rem 0.75rem;
            color: #aaa;
            text-decoration: none;
            font-size: 0.8rem;
            border-radius: 6px;
            transition: background 0.15s, color 0.15s;
        }
        .sidebar-nav a:hover {
            background: #252542;
            color: #eee;
        }
        .sidebar-nav a.active {
            background: #2a2a5a;
            color: #fff;
        }

        /* Main content */
        .main-content {
            margin-left: 220px;
            padding: 2rem;
            min-height: 100vh;
        }

        /* Sections */
        .capture-section {
            margin-bottom: 3rem;
            scroll-margin-top: 1.5rem;
        }
        .capture-section h2 {
            font-size: 1.1rem;
            font-weight: 500;
            margin-bottom: 1rem;
            color: #ccc;
            padding-bottom: 0.5rem;
            border-bottom: 1px solid #2a2a4a;
        }

        /* Gallery grid */
        .gallery {
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(200px, 1fr));
            gap: 1.5rem;
        }
        .screenshot-card {
            background: #252542;
            border-radius: 12px;
            overflow: hidden;
            cursor: pointer;
            transition: transform 0.2s, box-shadow 0.2s;
        }
        .screenshot-card:hover {
            transform: translateY(-4px);
            box-shadow: 0 8px 25px rgba(0,0,0,0.4);
        }
        .screenshot-card img { width: 100%; height: auto; display: block; }
        .screenshot-card img.img-dark { display: none; }
        body.mode-dark .screenshot-card img.img-light { display: none; }
        body.mode-dark .screenshot-card img.img-dark { display: block; }
        .screenshot-card .label {
            padding: 0.75rem;
            font-size: 0.8rem;
            color: #aaa;
            text-align: center;
            background: #1e1e36;
        }

        /* Video section */
        .video-section { text-align: center; }
        .video-section h2 {
            font-size: 1.1rem;
            font-weight: 500;
            margin-bottom: 1rem;
            color: #ccc;
            padding-bottom: 0.5rem;
            border-bottom: 1px solid #2a2a4a;
        }
        video {
            max-width: 400px;
            width: 100%;
            border-radius: 12px;
            box-shadow: 0 4px 20px rgba(0,0,0,0.4);
        }

        /* Lightbox */
        .lightbox {
            display: none;
            position: fixed;
            inset: 0;
            background: rgba(0,0,0,0.95);
            z-index: 1000;
            justify-content: center;
            align-items: center;
            padding: 2rem;
        }
        .lightbox.active { display: flex; }
        .lightbox img {
            max-width: 90vw;
            max-height: 90vh;
            border-radius: 8px;
            box-shadow: 0 0 40px rgba(0,0,0,0.5);
        }
        .lightbox .close {
            position: absolute;
            top: 1rem;
            right: 1.5rem;
            font-size: 2rem;
            color: #888;
            cursor: pointer;
        }
        .lightbox .close:hover { color: #fff; }
        .lightbox .nav {
            position: absolute;
            top: 50%;
            transform: translateY(-50%);
            font-size: 2rem;
            color: #888;
            cursor: pointer;
            padding: 1rem;
            user-select: none;
        }
        .lightbox .nav:hover { color: #fff; }
        .lightbox .nav.prev { left: 1rem; }
        .lightbox .nav.next { right: 1rem; }
        .lightbox .caption {
            position: absolute;
            bottom: 1.5rem;
            left: 50%;
            transform: translateX(-50%);
            color: #888;
            font-size: 0.9rem;
        }

        .no-content { text-align: center; padding: 3rem; color: #666; }

        @media (max-width: 768px) {
            .sidebar {
                position: fixed;
                width: 180px;
                transform: translateX(-100%);
                transition: transform 0.3s;
            }
            .sidebar.open { transform: translateX(0); }
            .main-content { margin-left: 0; padding: 1rem; }
            .gallery { grid-template-columns: repeat(2, 1fr); gap: 1rem; }
            .menu-toggle {
                display: flex !important;
            }
        }
        .menu-toggle {
            display: none;
            position: fixed;
            top: 1rem;
            left: 1rem;
            z-index: 101;
            background: #252542;
            border: 1px solid #2a2a4a;
            color: #eee;
            width: 36px;
            height: 36px;
            border-radius: 8px;
            align-items: center;
            justify-content: center;
            cursor: pointer;
            font-size: 1.2rem;
        }
    </style>
</head>
<body>
    <button class="menu-toggle" onclick="document.querySelector('.sidebar').classList.toggle('open')">&#9776;</button>
    <aside class="sidebar">
        <div class="sidebar-header">
            <h1>Dict App</h1>
            <div class="timestamp">$display_ts</div>
            $device_html
            $commit_html
        </div>
HTMLHEAD

    # Add theme toggle if dark screenshots exist
    if [ "$has_dark" = "true" ]; then
        cat >> "$html_file" << 'HTMLTOGGLE'
        <div class="theme-toggle">
            <span class="toggle-label active" id="label-light">Light</span>
            <div class="toggle-switch" id="theme-switch" onclick="toggleTheme()"></div>
            <span class="toggle-label" id="label-dark">Dark</span>
        </div>
HTMLTOGGLE
    fi

    # Add sidebar navigation
    echo '        <nav class="sidebar-nav">' >> "$html_file"
    [ "$has_search" = true ] && echo '            <a href="#search">Search</a>' >> "$html_file"
    [ "$has_definition" = true ] && echo '            <a href="#definition-view">Definition View</a>' >> "$html_file"
    [ "$has_edge_long" = true ] && echo '            <a href="#edge-long-content">Edge: Long Content</a>' >> "$html_file"
    [ "$has_edge_many" = true ] && echo '            <a href="#edge-many-items">Edge: Many Items</a>' >> "$html_file"
    [ "$has_edge_missing" = true ] && echo '            <a href="#edge-missing-sections">Edge: Missing Sections</a>' >> "$html_file"
    [ "$has_video" = true ] && echo '            <a href="#video">Video</a>' >> "$html_file"
    cat >> "$html_file" << 'HTMLNAVEND'
        </nav>
    </aside>
    <main class="main-content">
HTMLNAVEND

    # Helper: emit a screenshot card
    # Usage: emit_card <filename> <label>
    emit_card() {
        local filename="$1"
        local label="$2"
        local dark_img=""
        if [ -f "$light_dir_DARK/$filename" ]; then
            dark_img="<img class=\"img-dark\" src=\"screenshots-dark/$filename\" alt=\"$label\">"
        fi
        cat >> "$html_file" << HTMLCARD
                <div class="screenshot-card" onclick="openLightbox(this)">
                    <img class="img-light" src="screenshots/$filename" alt="$label">
                    $dark_img
                    <div class="label">$label</div>
                </div>
HTMLCARD
    }

    # Categorize screenshots into sections
    local found_screenshots=false

    # Build arrays of (filename, label) per section
    declare -a search_files=() definition_files=() edge_long_files=() edge_many_files=() edge_missing_files=()

    if [ -d "$light_dir" ]; then
        for img in $(ls -1 "$light_dir"/*.png 2>/dev/null | sort); do
            found_screenshots=true
            local filename=$(basename "$img")
            local fname=$(basename "$img" .png)
            local label=$(echo "$fname" | sed 's/^outlier_[0-9]*[a-z]*_//;s/^[0-9]*[a-z]*_//;s/_/ /g')

            case "$fname" in
                # Main flow - Search section
                01_*|02_*|05_*|06_*|10_*)
                    search_files+=("$filename|$label") ;;
                # Main flow - Definition view section
                03_*|04b_*|07_*|08b_*|09c_*)
                    definition_files+=("$filename|$label") ;;
                # Edge cases - Long content (etymology, definitions)
                outlier_11*|outlier_12*|outlier_16*)
                    edge_long_files+=("$filename|$label") ;;
                # Edge cases - Many items (many definitions with scroll)
                outlier_13*|outlier_14*|outlier_15*)
                    edge_many_files+=("$filename|$label") ;;
                # Legacy patterns for backward compatibility
                outlier_01*|outlier_03*|outlier_04*)
                    edge_long_files+=("$filename|$label") ;;
                outlier_02*)
                    edge_many_files+=("$filename|$label") ;;
                outlier_05*|outlier_06*)
                    edge_missing_files+=("$filename|$label") ;;
                *)
                    # Fallback: put uncategorized in search section
                    search_files+=("$filename|$label") ;;
            esac
        done
    fi

    # Emit each section
    if [ ${#search_files[@]} -gt 0 ]; then
        cat >> "$html_file" << 'HTMLSEC'
        <section class="capture-section" id="search">
            <h2>Search</h2>
            <div class="gallery">
HTMLSEC
        for entry in "${search_files[@]}"; do
            IFS='|' read -r f l <<< "$entry"
            emit_card "$f" "$l"
        done
        echo '            </div>' >> "$html_file"
        echo '        </section>' >> "$html_file"
    fi

    if [ ${#definition_files[@]} -gt 0 ]; then
        cat >> "$html_file" << 'HTMLSEC'
        <section class="capture-section" id="definition-view">
            <h2>Definition View</h2>
            <div class="gallery">
HTMLSEC
        for entry in "${definition_files[@]}"; do
            IFS='|' read -r f l <<< "$entry"
            emit_card "$f" "$l"
        done
        echo '            </div>' >> "$html_file"
        echo '        </section>' >> "$html_file"
    fi

    if [ ${#edge_long_files[@]} -gt 0 ]; then
        cat >> "$html_file" << 'HTMLSEC'
        <section class="capture-section" id="edge-long-content">
            <h2>Edge Cases: Long Content</h2>
            <div class="gallery">
HTMLSEC
        for entry in "${edge_long_files[@]}"; do
            IFS='|' read -r f l <<< "$entry"
            emit_card "$f" "$l"
        done
        echo '            </div>' >> "$html_file"
        echo '        </section>' >> "$html_file"
    fi

    if [ ${#edge_many_files[@]} -gt 0 ]; then
        cat >> "$html_file" << 'HTMLSEC'
        <section class="capture-section" id="edge-many-items">
            <h2>Edge Cases: Many Items</h2>
            <div class="gallery">
HTMLSEC
        for entry in "${edge_many_files[@]}"; do
            IFS='|' read -r f l <<< "$entry"
            emit_card "$f" "$l"
        done
        echo '            </div>' >> "$html_file"
        echo '        </section>' >> "$html_file"
    fi

    if [ ${#edge_missing_files[@]} -gt 0 ]; then
        cat >> "$html_file" << 'HTMLSEC'
        <section class="capture-section" id="edge-missing-sections">
            <h2>Edge Cases: Missing Sections</h2>
            <div class="gallery">
HTMLSEC
        for entry in "${edge_missing_files[@]}"; do
            IFS='|' read -r f l <<< "$entry"
            emit_card "$f" "$l"
        done
        echo '            </div>' >> "$html_file"
        echo '        </section>' >> "$html_file"
    fi

    if [ "$found_screenshots" = false ]; then
        echo '        <div class="no-content">No screenshots captured</div>' >> "$html_file"
    fi

    # Add video section at the bottom if video exists
    if [ "$has_video" = "true" ]; then
        cat >> "$html_file" << 'HTMLVIDEO'
        <section class="capture-section video-section" id="video">
            <h2>App Flow Video</h2>
            <video controls>
                <source src="app-flow.mp4" type="video/mp4">
                Your browser does not support video playback.
            </video>
        </section>
HTMLVIDEO
    fi

    # Close main content and add lightbox + script
    cat >> "$html_file" << 'HTMLEND'
    </main>
    
    <div class="lightbox" id="lightbox">
        <span class="close" onclick="closeLightbox()">&times;</span>
        <span class="nav prev" onclick="navigate(-1)">&#10094;</span>
        <span class="nav next" onclick="navigate(1)">&#10095;</span>
        <img id="lightbox-img" src="" alt="">
        <div class="caption" id="lightbox-caption"></div>
    </div>
    
    <script>
        let darkMode = false;
        let currentIndex = 0;

        function getVisibleImages() {
            const cls = darkMode ? 'img-dark' : 'img-light';
            return Array.from(document.querySelectorAll('.screenshot-card img.' + cls));
        }

        function toggleTheme() {
            darkMode = !darkMode;
            document.body.classList.toggle('mode-dark', darkMode);
            const sw = document.getElementById('theme-switch');
            sw.classList.toggle('dark', darkMode);
            document.getElementById('label-light').classList.toggle('active', !darkMode);
            document.getElementById('label-dark').classList.toggle('active', darkMode);
            // Update lightbox if open
            if (document.getElementById('lightbox').classList.contains('active')) {
                updateLightbox();
            }
        }
        
        function openLightbox(card) {
            const images = getVisibleImages();
            const cls = darkMode ? 'img-dark' : 'img-light';
            const clickedImg = card.querySelector('img.' + cls);
            currentIndex = images.indexOf(clickedImg);
            updateLightbox();
            document.getElementById('lightbox').classList.add('active');
            document.body.style.overflow = 'hidden';
        }
        
        function closeLightbox() {
            document.getElementById('lightbox').classList.remove('active');
            document.body.style.overflow = '';
        }
        
        function navigate(dir) {
            const images = getVisibleImages();
            currentIndex = (currentIndex + dir + images.length) % images.length;
            updateLightbox();
        }
        
        function updateLightbox() {
            const images = getVisibleImages();
            if (images[currentIndex]) {
                document.getElementById('lightbox-img').src = images[currentIndex].src;
                document.getElementById('lightbox-caption').textContent = images[currentIndex].alt;
            }
        }

        // Highlight active sidebar link on scroll
        const sections = document.querySelectorAll('.capture-section');
        const navLinks = document.querySelectorAll('.sidebar-nav a');
        
        function updateActiveNav() {
            let current = '';
            sections.forEach(section => {
                const rect = section.getBoundingClientRect();
                if (rect.top <= 100) {
                    current = section.id;
                }
            });
            navLinks.forEach(link => {
                link.classList.toggle('active', link.getAttribute('href') === '#' + current);
            });
        }
        
        window.addEventListener('scroll', updateActiveNav);
        updateActiveNav();
        
        document.addEventListener('keydown', (e) => {
            if (!document.getElementById('lightbox').classList.contains('active')) return;
            if (e.key === 'Escape') closeLightbox();
            if (e.key === 'ArrowLeft') navigate(-1);
            if (e.key === 'ArrowRight') navigate(1);
        });
        
        document.getElementById('lightbox').addEventListener('click', (e) => {
            if (e.target.id === 'lightbox') closeLightbox();
        });

        // Close mobile sidebar when a nav link is clicked
        document.querySelectorAll('.sidebar-nav a').forEach(link => {
            link.addEventListener('click', () => {
                document.querySelector('.sidebar').classList.remove('open');
            });
        });
    </script>
</body>
</html>
HTMLEND

    echo -e "  ${GREEN}✓${NC} HTML viewer generated"
}
# ============================================================
# Command: test
# ============================================================
cmd_test() {
    echo -e "${BLUE}=== Running Tests ===${NC}"
    echo ""
    
    # Initialize backend
    local backend_args="--target $TARGET"
    [ -n "$SERIAL" ] && backend_args="$backend_args --serial $SERIAL"
    backend_init $backend_args || exit $?
    
    local info
    info=$(backend_get_info)
    local model=$(echo "$info" | grep "^model=" | cut -d= -f2)
    local serial=$(echo "$info" | grep "^serial=" | cut -d= -f2)
    
    echo -e "Target: ${GREEN}$model${NC} ($serial)"
    echo ""
    
    # Check if test APK is installed
    if ! backend_app_installed "org.example.dictapp.test"; then
        echo -e "${RED}ERROR: Test APK not installed${NC}"
        echo "Run: $0 install --target $TARGET"
        exit 1
    fi
    
    # Determine test to run
    local test_arg=""
    if [ -n "$TEST_CLASS" ]; then
        test_arg="-e class org.example.dictapp.$TEST_CLASS"
    fi
    
    # Run tests via adb
    echo -e "${BLUE}Running instrumentation tests...${NC}"
    echo ""
    backend_logcat_clear
    
    $BACKEND_ADB -s "$BACKEND_SERIAL" shell am instrument -w $test_arg \
        org.example.dictapp.test/androidx.test.runner.AndroidJUnitRunner
    
    backend_cleanup
}

# ============================================================
# Command: clean
# ============================================================
cmd_clean() {
    echo -e "${BLUE}=== Cleaning ===${NC}"
    echo ""
    
    echo -e "${BLUE}Cleaning Android build...${NC}"
    cd android
    ./gradlew clean --quiet
    cd ..
    echo -e "  ${GREEN}✓${NC} Android build cleaned"
    
    echo -e "${BLUE}Cleaning native build...${NC}"
    cd core
    cargo clean --quiet
    cd ..
    echo -e "  ${GREEN}✓${NC} Native build cleaned"
    
    echo -e "${BLUE}Removing jniLibs...${NC}"
    rm -rf android/app/src/main/jniLibs
    echo -e "  ${GREEN}✓${NC} jniLibs removed"
    
    echo ""
    echo -e "${GREEN}Clean complete!${NC}"
}

# ============================================================
# Main
# ============================================================

# Find SDK for commands that need it
case "$COMMAND" in
    build|install|test)
        find_android_sdk
        ;;
esac

# Execute command
case "$COMMAND" in
    build)
        cmd_build
        ;;
    install)
        cmd_install
        ;;
    logs)
        cmd_logs
        ;;
    capture)
        cmd_capture
        ;;
    test)
        cmd_test
        ;;
    clean)
        cmd_clean
        ;;
    *)
        echo -e "${RED}ERROR: Unknown command '$COMMAND'${NC}"
        usage
        ;;
esac
