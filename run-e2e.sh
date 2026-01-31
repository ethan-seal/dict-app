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
        echo -e "${BLUE}=== $mode Mode ===${NC}"
        
        # Restart app
        echo -e "  ${YELLOW}Restarting app...${NC}"
        backend_restart_app
        
        # Screenshot 01: Empty search
        count=$((count + 1))
        echo -ne "  📸 ${CYAN}$(printf '%02d' $count)_search_empty.png${NC}... "
        backend_screenshot "search_empty" "$output_dir/$(printf '%02d' $count)_search_empty.png"
        echo -e "${GREEN}done${NC}"
        
        # Screenshot 02: Type query
        echo -e "  ${YELLOW}Typing 'hello'...${NC}"
        backend_tap_search
        backend_wait 0.3
        backend_type "hello"
        backend_wait 1
        
        count=$((count + 1))
        echo -ne "  📸 ${CYAN}$(printf '%02d' $count)_search_typing.png${NC}... "
        backend_screenshot "search_typing" "$output_dir/$(printf '%02d' $count)_search_typing.png"
        echo -e "${GREEN}done${NC}"
        
        # Screenshot 03: Results
        echo -e "  ${YELLOW}Dismissing keyboard...${NC}"
        backend_key KEYCODE_ESCAPE 2>/dev/null || backend_key KEYCODE_BACK
        backend_wait 0.8
        
        count=$((count + 1))
        echo -ne "  📸 ${CYAN}$(printf '%02d' $count)_search_results.png${NC}... "
        backend_screenshot "search_results" "$output_dir/$(printf '%02d' $count)_search_results.png"
        echo -e "${GREEN}done${NC}"
        
        # Screenshot 04: Definition
        echo -e "  ${YELLOW}Opening definition...${NC}"
        backend_tap_first_result
        backend_wait 2
        
        count=$((count + 1))
        echo -ne "  📸 ${CYAN}$(printf '%02d' $count)_definition_top.png${NC}... "
        backend_screenshot "definition_top" "$output_dir/$(printf '%02d' $count)_definition_top.png"
        echo -e "${GREEN}done${NC}"
        
        # Screenshot 05: Scrolled definition
        echo -e "  ${YELLOW}Scrolling...${NC}"
        backend_swipe_up
        backend_wait 0.5
        
        count=$((count + 1))
        echo -ne "  📸 ${CYAN}$(printf '%02d' $count)_definition_scrolled.png${NC}... "
        backend_screenshot "definition_scrolled" "$output_dir/$(printf '%02d' $count)_definition_scrolled.png"
        echo -e "${GREEN}done${NC}"
        
        # Screenshot 06: Back to search
        echo -e "  ${YELLOW}Going back...${NC}"
        backend_back
        backend_wait 0.8
        
        count=$((count + 1))
        echo -ne "  📸 ${CYAN}$(printf '%02d' $count)_back_to_search.png${NC}... "
        backend_screenshot "back_to_search" "$output_dir/$(printf '%02d' $count)_back_to_search.png"
        echo -e "${GREEN}done${NC}"
        
        # Screenshot 07: New search
        echo -e "  ${YELLOW}Searching 'computer'...${NC}"
        backend_tap_search
        backend_wait 0.5
        backend_clear_text
        backend_type "computer"
        backend_wait 1.5
        
        count=$((count + 1))
        echo -ne "  📸 ${CYAN}$(printf '%02d' $count)_search_computer.png${NC}... "
        backend_screenshot "search_computer" "$output_dir/$(printf '%02d' $count)_search_computer.png"
        echo -e "${GREEN}done${NC}"
        
        # Screenshot 08: Computer definition
        echo -e "  ${YELLOW}Opening computer definition...${NC}"
        backend_tap_first_result
        backend_wait 1.5
        
        count=$((count + 1))
        echo -ne "  📸 ${CYAN}$(printf '%02d' $count)_definition_computer.png${NC}... "
        backend_screenshot "definition_computer" "$output_dir/$(printf '%02d' $count)_definition_computer.png"
        echo -e "${GREEN}done${NC}"
        
        echo -e "  ${GREEN}Captured $count screenshots${NC}"
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
    
    # Check if dark screenshots exist
    local has_light=$(ls "$light_dir"/*.png 2>/dev/null | head -1)
    local has_dark=$(ls "$dark_dir"/*.png 2>/dev/null | head -1)
    
    # Start HTML
    cat > "$html_file" << 'HTMLHEAD'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>App Screenshots</title>
    <style>
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body { font-family: system-ui, sans-serif; background: #1a1a2e; color: #eee; min-height: 100vh; }
        .container { max-width: 1400px; margin: 0 auto; padding: 2rem; }
        header { margin-bottom: 2rem; }
        h1 { font-size: 1.5rem; font-weight: 600; }
        .meta { color: #888; font-size: 0.9rem; margin-top: 0.5rem; }
        .device { color: #6a9fb5; }
        .toggle { display: flex; gap: 1rem; margin: 1.5rem 0; }
        .toggle button { padding: 0.5rem 1rem; border: 1px solid #444; background: #252542; color: #aaa; border-radius: 6px; cursor: pointer; }
        .toggle button.active { background: #3a3a6a; color: #fff; border-color: #5a5a8a; }
        .section { margin-bottom: 2rem; }
        .section h2 { font-size: 1rem; color: #888; margin-bottom: 1rem; padding-bottom: 0.5rem; border-bottom: 1px solid #333; }
        .gallery { display: grid; grid-template-columns: repeat(auto-fill, minmax(220px, 1fr)); gap: 1.5rem; }
        .card { background: #252542; border-radius: 12px; overflow: hidden; transition: transform 0.2s; }
        .card:hover { transform: translateY(-4px); }
        .card img { width: 100%; display: block; cursor: pointer; }
        .card .label { padding: 0.75rem; font-size: 0.8rem; color: #aaa; text-align: center; }
        .lightbox { display: none; position: fixed; inset: 0; background: rgba(0,0,0,0.95); z-index: 100; justify-content: center; align-items: center; }
        .lightbox.active { display: flex; }
        .lightbox img { max-width: 90vw; max-height: 90vh; border-radius: 8px; }
        .lightbox .close { position: absolute; top: 1rem; right: 1.5rem; font-size: 2rem; color: #888; cursor: pointer; }
        .hidden { display: none !important; }
    </style>
</head>
<body>
    <div class="container">
        <header>
            <h1>Dict App Screenshots</h1>
            <div class="meta">
HTMLHEAD

    echo "                <span class=\"device\">$device_model</span> • $(date -d "@$(date -d "$timestamp" +%s 2>/dev/null || date +%s)" '+%b %d, %Y at %I:%M %p' 2>/dev/null || date '+%b %d, %Y at %I:%M %p')" >> "$html_file"
    
    cat >> "$html_file" << 'HTMLHEAD2'
            </div>
        </header>
HTMLHEAD2

    # Toggle if both modes exist
    if [ -n "$has_light" ] && [ -n "$has_dark" ]; then
        cat >> "$html_file" << 'TOGGLE'
        <div class="toggle">
            <button class="active" onclick="showMode('light')">Light Mode</button>
            <button onclick="showMode('dark')">Dark Mode</button>
        </div>
TOGGLE
    fi
    
    # Light section
    if [ -n "$has_light" ]; then
        echo '        <div class="section" id="light-section">' >> "$html_file"
        echo '            <h2>Light Mode</h2>' >> "$html_file"
        echo '            <div class="gallery">' >> "$html_file"
        for img in "$light_dir"/*.png; do
            local name=$(basename "$img" .png | sed 's/^[0-9]*_//;s/_/ /g')
            echo "                <div class=\"card\" onclick=\"openLightbox('screenshots/$(basename "$img")')\"><img src=\"screenshots/$(basename "$img")\"><div class=\"label\">$name</div></div>" >> "$html_file"
        done
        echo '            </div>' >> "$html_file"
        echo '        </div>' >> "$html_file"
    fi
    
    # Dark section
    if [ -n "$has_dark" ]; then
        echo '        <div class="section hidden" id="dark-section">' >> "$html_file"
        echo '            <h2>Dark Mode</h2>' >> "$html_file"
        echo '            <div class="gallery">' >> "$html_file"
        for img in "$dark_dir"/*.png; do
            local name=$(basename "$img" .png | sed 's/^[0-9]*_//;s/_/ /g')
            echo "                <div class=\"card\" onclick=\"openLightbox('screenshots-dark/$(basename "$img")')\"><img src=\"screenshots-dark/$(basename "$img")\"><div class=\"label\">$name</div></div>" >> "$html_file"
        done
        echo '            </div>' >> "$html_file"
        echo '        </div>' >> "$html_file"
    fi
    
    cat >> "$html_file" << 'HTMLEND'
    </div>
    <div class="lightbox" id="lightbox" onclick="closeLightbox()">
        <span class="close">&times;</span>
        <img id="lightbox-img" src="">
    </div>
    <script>
        function showMode(mode) {
            document.querySelectorAll('.toggle button').forEach(b => b.classList.remove('active'));
            event.target.classList.add('active');
            document.getElementById('light-section').classList.toggle('hidden', mode !== 'light');
            document.getElementById('dark-section').classList.toggle('hidden', mode !== 'dark');
        }
        function openLightbox(src) {
            document.getElementById('lightbox-img').src = src;
            document.getElementById('lightbox').classList.add('active');
        }
        function closeLightbox() {
            document.getElementById('lightbox').classList.remove('active');
        }
        document.addEventListener('keydown', e => { if (e.key === 'Escape') closeLightbox(); });
    </script>
</body>
</html>
HTMLEND
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
