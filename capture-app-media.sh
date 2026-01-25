#!/bin/bash
set -e

# capture-app-media.sh - Capture screenshots and video of the app for UI/UX review
#
# Usage:
#   ./capture-app-media.sh              # Capture with default settings
#   ./capture-app-media.sh --gui        # Show emulator window while capturing
#   ./capture-app-media.sh --no-video   # Screenshots only (faster)
#   ./capture-app-media.sh --skip-build # Skip APK build (use existing)
#   ./capture-app-media.sh --avd <name> # Use specific AVD
#
# Output: ./captures/<timestamp>/
#   - screenshots/*.png  (captured at key UI states)
#   - app-flow.mp4       (video of the full flow)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
AVD_NAME="Medium_Phone_API_35"
HEADLESS=true
CAPTURE_VIDEO=true
SKIP_BUILD=false
BOOT_TIMEOUT=120
EMULATOR_STARTED_BY_US=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --gui)
            HEADLESS=false
            shift
            ;;
        --no-video)
            CAPTURE_VIDEO=false
            shift
            ;;
        --skip-build)
            SKIP_BUILD=true
            shift
            ;;
        --avd)
            AVD_NAME="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Capture screenshots and video of the app for UI/UX review."
            echo ""
            echo "Options:"
            echo "  --gui         Show emulator window (default: headless)"
            echo "  --no-video    Skip video recording (screenshots only)"
            echo "  --skip-build  Skip APK build/install (use existing APKs)"
            echo "  --avd <name>  Use specific AVD (default: Medium_Phone_API_35)"
            echo "  --help, -h    Show this help message"
            echo ""
            echo "Output is saved to: ./captures/<timestamp>/"
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            exit 1
            ;;
    esac
done

# Detect Android SDK
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
    exit 1
fi

export ANDROID_SDK_ROOT="$SDK_ROOT"
export ANDROID_HOME="$SDK_ROOT"

EMULATOR="$SDK_ROOT/emulator/emulator"
ADB="$SDK_ROOT/platform-tools/adb"

[ ! -x "$ADB" ] && ADB="adb"
[ ! -x "$EMULATOR" ] && EMULATOR="emulator"

# Create output directory with timestamp
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_DIR="$SCRIPT_DIR/captures/$TIMESTAMP"
SCREENSHOT_DIR="$OUTPUT_DIR/screenshots"
SCREENSHOT_DIR_DARK="$OUTPUT_DIR/screenshots-dark"
mkdir -p "$SCREENSHOT_DIR" "$SCREENSHOT_DIR_DARK"

# Device paths
DEVICE_VIDEO="/sdcard/app-capture.mp4"
DEVICE_SCREENSHOT_DIR="/sdcard/app-captures"

echo -e "${BLUE}=== App Media Capture ===${NC}"
echo ""
echo "Output: $OUTPUT_DIR"
echo ""

# Check prerequisites
echo "Checking prerequisites..."

if [ ! -f "android/app/src/main/jniLibs/x86_64/libdict_core.so" ]; then
    echo -e "${RED}ERROR: Native libraries not found${NC}"
    echo "Run ./build-android-native.sh first"
    exit 1
fi
echo -e "  ${GREEN}✓${NC} Native libraries found"

# Check AVD
if ! "$EMULATOR" -list-avds 2>/dev/null | grep -q "^${AVD_NAME}$"; then
    echo -e "${RED}ERROR: AVD '$AVD_NAME' not found${NC}"
    "$EMULATOR" -list-avds 2>/dev/null | sed 's/^/  /'
    exit 1
fi
echo -e "  ${GREEN}✓${NC} AVD '$AVD_NAME' exists"

# Check/start emulator
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
    
    EMU_ARGS="-avd $AVD_NAME -no-snapshot-save"
    if [ "$HEADLESS" = true ]; then
        EMU_ARGS="$EMU_ARGS -no-window -no-audio -gpu swiftshader_indirect"
    fi
    
    "$EMULATOR" $EMU_ARGS &>/dev/null &
    
    # Wait for any emulator to appear
    echo "  Waiting for emulator to start..."
    for i in $(seq 1 $BOOT_TIMEOUT); do
        if emulator_running; then
            break
        fi
        sleep 1
    done
    
    if ! emulator_running; then
        echo -e "${RED}ERROR: Emulator failed to start${NC}"
        exit 1
    fi
fi

# Get emulator serial for targeted commands
EMU_SERIAL=$(get_emulator_serial)
if [ -z "$EMU_SERIAL" ]; then
    echo -e "${RED}ERROR: No emulator found${NC}"
    exit 1
fi
echo -e "  ${GREEN}✓${NC} Using emulator: $EMU_SERIAL"

# Create adb command that targets the emulator (works in subshells too)
ADB_EMU="$ADB -s $EMU_SERIAL"

# Wait for boot to complete
echo "  Waiting for boot..."
for i in $(seq 1 $BOOT_TIMEOUT); do
    if [ "$($ADB_EMU shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ]; then
        break
    fi
    sleep 1
    [ $((i % 10)) -eq 0 ] && echo "    ... ${i}s"
done

if [ "$($ADB_EMU shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" != "1" ]; then
    echo -e "${RED}ERROR: Emulator boot timed out${NC}"
    exit 1
fi
echo -e "  ${GREEN}✓${NC} Emulator ready"
sleep 2

# Clean up any previous capture files on device
$ADB_EMU shell "rm -f $DEVICE_VIDEO" 2>/dev/null || true
$ADB_EMU shell "rm -rf $DEVICE_SCREENSHOT_DIR" 2>/dev/null || true

echo ""

MARKER_PATTERN="CAPTURE_MARKER"

# APK paths
APP_APK="$SCRIPT_DIR/android/app/build/outputs/apk/debug/app-debug.apk"
TEST_APK="$SCRIPT_DIR/android/app/build/outputs/apk/androidTest/debug/app-debug-androidTest.apk"

# Function: build and install APKs
build_and_install_apks() {
    echo -e "${BLUE}Building APKs...${NC}"
    cd android
    ./gradlew assembleDebug assembleDebugAndroidTest --quiet
    cd ..
    
    if [ ! -f "$APP_APK" ] || [ ! -f "$TEST_APK" ]; then
        echo -e "${RED}ERROR: APK build failed${NC}"
        exit 1
    fi
    echo -e "  ${GREEN}✓${NC} APKs built"
    
    echo -e "${BLUE}Installing APKs...${NC}"
    $ADB_EMU install -r -g "$APP_APK" >/dev/null
    echo -e "  ${GREEN}✓${NC} App APK installed"
    $ADB_EMU install -r -g "$TEST_APK" >/dev/null
    echo -e "  ${GREEN}✓${NC} Test APK installed"
}

# Function: run a capture pass (test + screenshot collection)
# Args: $1 = mode label (light/dark), $2 = local output directory for screenshots
run_capture_pass() {
    local mode="$1"
    local local_screenshot_dir="$2"

    # Clean device screenshot dir
    $ADB_EMU shell "rm -rf $DEVICE_SCREENSHOT_DIR" 2>/dev/null || true
    $ADB_EMU shell "mkdir -p $DEVICE_SCREENSHOT_DIR" 2>/dev/null || true

    # Start logcat monitoring for screenshot markers
    echo -e "${BLUE}Starting screenshot capture monitor ($mode mode)...${NC}"
    local screenshot_count=0

    (
        $ADB_EMU logcat -c
        $ADB_EMU logcat -s "AppCapture:I" | while read -r line; do
            if echo "$line" | grep -q "$MARKER_PATTERN"; then
                MARKER_NAME=$(echo "$line" | sed -n "s/.*${MARKER_PATTERN}:\([^ ]*\).*/\1/p")
                if [ -n "$MARKER_NAME" ] && [ "$MARKER_NAME" != "DONE" ] && [ "$MARKER_NAME" != "outlier_DONE" ]; then
                    screenshot_count=$((screenshot_count + 1))
                    FILENAME="${MARKER_NAME}.png"
                    $ADB_EMU shell "screencap -p $DEVICE_SCREENSHOT_DIR/$FILENAME"
                    echo -e "  ${GREEN}✓${NC} Captured ($mode): $FILENAME"
                fi
                if [ "$MARKER_NAME" = "outlier_DONE" ]; then
                    echo "CAPTURE_COMPLETE" >> "/tmp/capture_done_${mode}_$$"
                    break
                fi
            fi
        done
    ) &
    local logcat_pid=$!

    # Run the capture test directly via am instrument (faster than Gradle)
    echo ""
    echo -e "${BLUE}Running capture test flow ($mode mode)...${NC}"
    echo ""

    $ADB_EMU shell am instrument -w \
        -e class org.example.dictapp.AppCaptureTest \
        org.example.dictapp.test/androidx.test.runner.AndroidJUnitRunner \
        2>&1 | grep -E "OK\|FAILURES\|Error\|captureAppFlow\|captureOutlierCases" || true

    # Wait for final screenshot
    sleep 2

    # Stop logcat monitor
    kill $logcat_pid 2>/dev/null || true
    rm -f "/tmp/capture_done_${mode}_$$"

    # Pull screenshots
    echo ""
    echo -e "${BLUE}Retrieving $mode mode screenshots...${NC}"
    local pulled=0
    for file in $($ADB_EMU shell "ls $DEVICE_SCREENSHOT_DIR/*.png 2>/dev/null" | tr -d '\r'); do
        filename=$(basename "$file")
        $ADB_EMU pull "$file" "$local_screenshot_dir/$filename" 2>/dev/null && pulled=$((pulled + 1))
    done

    if [ $pulled -gt 0 ]; then
        echo -e "  ${GREEN}✓${NC} $pulled screenshots saved to $local_screenshot_dir/"
    else
        echo -e "  ${YELLOW}!${NC} No screenshots captured ($mode mode)"
    fi
}

# Build and install APKs (unless --skip-build)
if [ "$SKIP_BUILD" = true ]; then
    echo -e "${YELLOW}Skipping build (--skip-build)${NC}"
    if [ ! -f "$APP_APK" ] || [ ! -f "$TEST_APK" ]; then
        echo -e "${RED}ERROR: APKs not found. Run without --skip-build first.${NC}"
        exit 1
    fi
    # Still need to ensure APKs are installed
    echo -e "${BLUE}Installing APKs...${NC}"
    $ADB_EMU install -r -g "$APP_APK" >/dev/null
    $ADB_EMU install -r -g "$TEST_APK" >/dev/null
    echo -e "  ${GREEN}✓${NC} APKs installed"
else
    build_and_install_apks
fi
echo ""

# Start video recording in background (if enabled)
VIDEO_PID=""
if [ "$CAPTURE_VIDEO" = true ]; then
    echo -e "${BLUE}Starting video recording...${NC}"
    $ADB_EMU shell "screenrecord --bit-rate 8000000 $DEVICE_VIDEO" &
    VIDEO_PID=$!
    sleep 1
fi

# === Pass 1: Light mode ===
echo ""
echo -e "${BLUE}=== Light Mode Capture ===${NC}"
$ADB_EMU shell "cmd uimode night no" 2>/dev/null || true
sleep 1
run_capture_pass "light" "$SCREENSHOT_DIR"

# === Pass 2: Dark mode ===
echo ""
echo -e "${BLUE}=== Dark Mode Capture ===${NC}"
$ADB_EMU shell "cmd uimode night yes" 2>/dev/null || true
sleep 2  # Extra settle time for theme change
run_capture_pass "dark" "$SCREENSHOT_DIR_DARK"

# Restore light mode
$ADB_EMU shell "cmd uimode night no" 2>/dev/null || true

# Stop video recording
if [ -n "$VIDEO_PID" ]; then
    echo ""
    echo -e "${BLUE}Stopping video recording...${NC}"
    $ADB_EMU shell "pkill -INT screenrecord" 2>/dev/null || true
    sleep 2
fi

# Pull video
if [ "$CAPTURE_VIDEO" = true ]; then
    echo ""
    echo -e "${BLUE}Retrieving video...${NC}"
    if $ADB_EMU shell "test -f $DEVICE_VIDEO" 2>/dev/null; then
        $ADB_EMU pull "$DEVICE_VIDEO" "$OUTPUT_DIR/app-flow.mp4" 2>/dev/null
        echo -e "  ${GREEN}✓${NC} Video saved to $OUTPUT_DIR/app-flow.mp4"
    else
        echo -e "  ${YELLOW}!${NC} No video file found"
    fi
fi

# Cleanup device
$ADB_EMU shell "rm -f $DEVICE_VIDEO" 2>/dev/null || true
$ADB_EMU shell "rm -rf $DEVICE_SCREENSHOT_DIR" 2>/dev/null || true

# Summary
echo ""
echo -e "${GREEN}=== Capture Complete ===${NC}"
echo ""
echo "Output directory: $OUTPUT_DIR"
echo ""
ls -la "$OUTPUT_DIR" 2>/dev/null || true
echo ""
if [ -d "$SCREENSHOT_DIR" ]; then
    echo "Screenshots (light):"
    ls -la "$SCREENSHOT_DIR" 2>/dev/null | tail -n +2 || true
fi
echo ""
if [ -d "$SCREENSHOT_DIR_DARK" ]; then
    echo "Screenshots (dark):"
    ls -la "$SCREENSHOT_DIR_DARK" 2>/dev/null | tail -n +2 || true
fi

# Generate HTML viewer
generate_html_viewer() {
    local html_file="$OUTPUT_DIR/index.html"
    local has_video="false"
    [ -f "$OUTPUT_DIR/app-flow.mp4" ] && has_video="true"
    
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
    if [ -d "$SCREENSHOT_DIR_DARK" ] && ls "$SCREENSHOT_DIR_DARK"/*.png &>/dev/null; then
        has_dark="true"
    fi

    # Determine which sections have content
    local has_search=false
    local has_definition=false
    local has_edge_long=false
    local has_edge_many=false
    local has_edge_missing=false
    if [ -d "$SCREENSHOT_DIR" ]; then
        for img in $(ls -1 "$SCREENSHOT_DIR"/*.png 2>/dev/null); do
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
        if [ -f "$SCREENSHOT_DIR_DARK/$filename" ]; then
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

    if [ -d "$SCREENSHOT_DIR" ]; then
        for img in $(ls -1 "$SCREENSHOT_DIR"/*.png 2>/dev/null | sort); do
            found_screenshots=true
            local filename=$(basename "$img")
            local fname=$(basename "$img" .png)
            local label=$(echo "$fname" | sed 's/^outlier_[0-9]*[a-z]*_//;s/^[0-9]*[a-z]*_//;s/_/ /g')

            case "$fname" in
                01_*|02_*|04_*|05_*|07_*)
                    search_files+=("$filename|$label") ;;
                03_*|03b_*|06_*|06b_*|06c_*)
                    definition_files+=("$filename|$label") ;;
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

generate_html_viewer

# Create symlink to latest capture
rm -f "$SCRIPT_DIR/captures/latest" 2>/dev/null || true
ln -sf "$TIMESTAMP" "$SCRIPT_DIR/captures/latest"
echo ""
echo "View captures: file://$OUTPUT_DIR/index.html"
echo "Tip: ./captures/latest always points to the most recent capture"
