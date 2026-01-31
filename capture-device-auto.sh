#!/bin/bash

# capture-device-auto.sh - Fully automated screenshot capture using adb
#
# This script automates screenshot capture using adb input commands,
# bypassing Espresso entirely. Works on any Android version.
#
# Usage:
#   ./capture-device-auto.sh                    # Use connected device
#   ./capture-device-auto.sh --serial <id>      # Use specific device
#   ./capture-device-auto.sh --skip-dark        # Skip dark mode captures

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

TARGET_SERIAL=""
SKIP_DARK=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --serial)
            TARGET_SERIAL="$2"
            shift 2
            ;;
        --skip-dark)
            SKIP_DARK=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Fully automated screenshot capture from a physical device."
            echo ""
            echo "Options:"
            echo "  --serial <id>  Use specific device serial"
            echo "  --skip-dark    Skip dark mode captures"
            echo "  --help, -h     Show this help message"
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            exit 1
            ;;
    esac
done

# Find ADB
ADB="adb"
if [ -d "$HOME/Android/Sdk/platform-tools" ]; then
    ADB="$HOME/Android/Sdk/platform-tools/adb"
elif [ -d "$HOME/android/sdk/platform-tools" ]; then
    ADB="$HOME/android/sdk/platform-tools/adb"
fi

# Find device
if [ -n "$TARGET_SERIAL" ]; then
    DEVICE="$TARGET_SERIAL"
else
    DEVICE=$($ADB devices | grep -E "^\S+\s+device$" | grep -v "emulator-" | head -1 | cut -f1)
    if [ -z "$DEVICE" ]; then
        # Fall back to any device including emulator
        DEVICE=$($ADB devices | grep -E "^\S+\s+device$" | head -1 | cut -f1)
    fi
fi

if [ -z "$DEVICE" ]; then
    echo -e "${RED}ERROR: No device found${NC}"
    $ADB devices -l
    exit 1
fi

ADB_DEV="$ADB -s $DEVICE"

# Get device info
DEVICE_MODEL=$($ADB_DEV shell getprop ro.product.model | tr -d '\r')
DEVICE_SDK=$($ADB_DEV shell getprop ro.build.version.sdk | tr -d '\r')

# Get screen dimensions
SCREEN_SIZE=$($ADB_DEV shell wm size | grep -oE '[0-9]+x[0-9]+' | tail -1)
SCREEN_W=$(echo $SCREEN_SIZE | cut -dx -f1)
SCREEN_H=$(echo $SCREEN_SIZE | cut -dx -f2)

echo -e "${BLUE}=== Automated Device Screenshot Capture ===${NC}"
echo ""
echo -e "Device: ${GREEN}$DEVICE_MODEL${NC} (SDK $DEVICE_SDK)"
echo -e "Screen: ${SCREEN_W}x${SCREEN_H}"
echo ""

# Create output directory
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_DIR="$SCRIPT_DIR/captures/${TIMESTAMP}"
LIGHT_DIR="$OUTPUT_DIR/screenshots"
DARK_DIR="$OUTPUT_DIR/screenshots-dark"
mkdir -p "$LIGHT_DIR" "$DARK_DIR"

echo "Output: $OUTPUT_DIR"
echo ""

# Package name
PKG="org.example.dictapp"
ACTIVITY="org.example.dictapp.MainActivity"

# Helper functions
screenshot() {
    local name="$1"
    local dir="$2"
    local filename="${name}.png"
    
    echo -ne "  📸 ${CYAN}$filename${NC}... "
    $ADB_DEV shell screencap -p /sdcard/capture_tmp.png
    $ADB_DEV pull /sdcard/capture_tmp.png "$dir/$filename" 2>/dev/null
    $ADB_DEV shell rm -f /sdcard/capture_tmp.png
    echo -e "${GREEN}done${NC}"
}

wait_for_idle() {
    sleep 0.5
    # Wait for animations to settle
    $ADB_DEV shell "dumpsys window | grep -q 'mCurrentFocus.*$PKG'" 2>/dev/null || sleep 0.5
}

tap() {
    local x=$1
    local y=$2
    $ADB_DEV shell input tap $x $y
    wait_for_idle
}

tap_center() {
    tap $((SCREEN_W / 2)) $((SCREEN_H / 2))
}

swipe_up() {
    local start_y=$((SCREEN_H * 3 / 4))
    local end_y=$((SCREEN_H / 4))
    local x=$((SCREEN_W / 2))
    $ADB_DEV shell input swipe $x $start_y $x $end_y 300
    wait_for_idle
}

swipe_down() {
    local start_y=$((SCREEN_H / 4))
    local end_y=$((SCREEN_H * 3 / 4))
    local x=$((SCREEN_W / 2))
    $ADB_DEV shell input swipe $x $start_y $x $end_y 300
    wait_for_idle
}

type_text() {
    local text="$1"
    # Escape special characters for shell
    $ADB_DEV shell input text "$text"
    wait_for_idle
}

press_back() {
    $ADB_DEV shell input keyevent KEYCODE_BACK
    wait_for_idle
}

press_enter() {
    $ADB_DEV shell input keyevent KEYCODE_ENTER
    wait_for_idle
}

clear_text() {
    # Select all and delete
    $ADB_DEV shell input keyevent KEYCODE_MOVE_END
    for i in {1..30}; do
        $ADB_DEV shell input keyevent KEYCODE_DEL
    done
}

# Find and tap element by text using UI Automator
tap_text() {
    local text="$1"
    local bounds=$($ADB_DEV shell uiautomator dump /dev/tty 2>/dev/null | grep -oE "text=\"$text\"[^>]*bounds=\"\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\]\"" | head -1 | grep -oE 'bounds="\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\]"' | grep -oE '[0-9]+' | head -4)
    
    if [ -n "$bounds" ]; then
        local coords=($bounds)
        local x=$(( (${coords[0]} + ${coords[2]}) / 2 ))
        local y=$(( (${coords[1]} + ${coords[3]}) / 2 ))
        tap $x $y
        return 0
    fi
    return 1
}

# Find and tap the search field using UI Automator
tap_search_field() {
    # Dump UI and find EditText bounds
    $ADB_DEV shell uiautomator dump /sdcard/ui_dump.xml 2>/dev/null
    local bounds=$($ADB_DEV shell "cat /sdcard/ui_dump.xml" 2>/dev/null | grep -o 'EditText[^>]*bounds="\[[0-9]*,[0-9]*\]\[[0-9]*,[0-9]*\]"' | head -1 | grep -oE '\[([0-9]+),([0-9]+)\]\[([0-9]+),([0-9]+)\]')
    
    if [ -n "$bounds" ]; then
        # Parse bounds [left,top][right,bottom]
        local left=$(echo "$bounds" | grep -oE '[0-9]+' | sed -n '1p')
        local top=$(echo "$bounds" | grep -oE '[0-9]+' | sed -n '2p')
        local right=$(echo "$bounds" | grep -oE '[0-9]+' | sed -n '3p')
        local bottom=$(echo "$bounds" | grep -oE '[0-9]+' | sed -n '4p')
        local x=$(( (left + right) / 2 ))
        local y=$(( (top + bottom) / 2 ))
        echo "    [DEBUG] Found search field at ($x, $y)"
        tap $x $y
    else
        # Fallback: tap where search field typically is
        echo "    [DEBUG] Using fallback search field location"
        tap $((SCREEN_W / 2)) 400
    fi
    sleep 0.3
}

# Find first search result by looking for clickable items below search bar
tap_first_result() {
    $ADB_DEV shell uiautomator dump /sdcard/ui_dump.xml 2>/dev/null
    # Look for clickable views below y=500 (below search bar)
    local bounds=$($ADB_DEV shell "cat /sdcard/ui_dump.xml" 2>/dev/null | grep 'clickable="true"' | grep -oE 'bounds="\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\]"' | while read b; do
        local top=$(echo "$b" | grep -oE '[0-9]+' | sed -n '2p')
        if [ "$top" -gt 500 ] && [ "$top" -lt 1500 ]; then
            echo "$b"
            break
        fi
    done | head -1)
    
    if [ -n "$bounds" ]; then
        local left=$(echo "$bounds" | grep -oE '[0-9]+' | sed -n '1p')
        local top=$(echo "$bounds" | grep -oE '[0-9]+' | sed -n '2p')
        local right=$(echo "$bounds" | grep -oE '[0-9]+' | sed -n '3p')
        local bottom=$(echo "$bounds" | grep -oE '[0-9]+' | sed -n '4p')
        local x=$(( (left + right) / 2 ))
        local y=$(( (top + bottom) / 2 ))
        echo "    [DEBUG] Found result at ($x, $y)"
        tap $x $y
    else
        # Fallback: tap below search bar
        echo "    [DEBUG] Using fallback result location"
        tap $((SCREEN_W / 2)) 650
    fi
}

# ============================================================
# Main capture flow
# ============================================================

run_capture_flow() {
    local mode="$1"
    local output_dir="$2"
    local count=0
    
    echo ""
    echo -e "${BLUE}=== $mode Mode Capture ===${NC}"
    
    # Force stop and restart app for clean state
    echo -e "  ${YELLOW}Restarting app...${NC}"
    $ADB_DEV shell am force-stop $PKG
    sleep 0.5
    $ADB_DEV shell am start -n "$PKG/$ACTIVITY" >/dev/null 2>&1
    sleep 2
    wait_for_idle
    
    # 01 - Empty search screen
    count=$((count + 1))
    screenshot "$(printf '%02d' $count)_search_empty" "$output_dir"
    
    # 02 - Tap search and type query
    echo -e "  ${YELLOW}Typing search query...${NC}"
    tap_search_field
    sleep 0.3
    type_text "hello"
    sleep 1
    wait_for_idle
    
    count=$((count + 1))
    screenshot "$(printf '%02d' $count)_search_typing" "$output_dir"
    
    # 03 - Search results (dismiss keyboard first for clean screenshot)
    echo -e "  ${YELLOW}Dismissing keyboard...${NC}"
    $ADB_DEV shell input keyevent KEYCODE_ESCAPE 2>/dev/null || $ADB_DEV shell input keyevent KEYCODE_BACK
    sleep 0.8
    
    count=$((count + 1))
    screenshot "$(printf '%02d' $count)_search_results" "$output_dir"
    
    # 04 - Tap first result to view definition
    echo -e "  ${YELLOW}Opening definition...${NC}"
    tap_first_result
    sleep 2
    wait_for_idle
    
    count=$((count + 1))
    screenshot "$(printf '%02d' $count)_definition_top" "$output_dir"
    
    # 05 - Scroll down definition
    echo -e "  ${YELLOW}Scrolling definition...${NC}"
    swipe_up
    sleep 0.5
    
    count=$((count + 1))
    screenshot "$(printf '%02d' $count)_definition_scrolled" "$output_dir"
    
    # 06 - Go back to search (use navigation back, ensure we stay in app)
    echo -e "  ${YELLOW}Going back...${NC}"
    # Check if we're showing a definition (has back arrow), use that instead of system back
    $ADB_DEV shell input keyevent KEYCODE_BACK
    sleep 0.8
    
    # Verify we're still in the app, restart if needed
    local current_pkg=$($ADB_DEV shell "dumpsys window | grep mCurrentFocus" | grep -oE 'org\.example\.[^/}]*' | head -1)
    if [ "$current_pkg" != "org.example.dictapp" ]; then
        echo "    [DEBUG] Left app, restarting..."
        $ADB_DEV shell am start -n "$PKG/$ACTIVITY" >/dev/null 2>&1
        sleep 1
    fi
    wait_for_idle
    
    count=$((count + 1))
    screenshot "$(printf '%02d' $count)_back_to_search" "$output_dir"
    
    # 07 - Try another search
    echo -e "  ${YELLOW}New search...${NC}"
    tap_search_field
    sleep 0.5
    # Clear existing text and type new query
    $ADB_DEV shell input keyevent KEYCODE_MOVE_END
    for i in {1..20}; do $ADB_DEV shell input keyevent --longpress KEYCODE_DEL 2>/dev/null; done
    sleep 0.3
    type_text "computer"
    sleep 1.5
    wait_for_idle
    
    count=$((count + 1))
    screenshot "$(printf '%02d' $count)_search_computer" "$output_dir"
    
    # 08 - View computer definition
    echo -e "  ${YELLOW}Opening computer definition...${NC}"
    tap_first_result
    sleep 1.5
    wait_for_idle
    
    count=$((count + 1))
    screenshot "$(printf '%02d' $count)_definition_computer" "$output_dir"
    
    echo -e "  ${GREEN}Captured $count screenshots${NC}"
}

# ============================================================
# Execute captures
# ============================================================

# Ensure app is installed
if ! $ADB_DEV shell pm list packages | grep -q "$PKG"; then
    echo -e "${RED}ERROR: App not installed on device${NC}"
    echo "Install with: adb install android/app/build/outputs/apk/debug/app-debug.apk"
    exit 1
fi

# Light mode
$ADB_DEV shell cmd uimode night no 2>/dev/null || true
sleep 1
run_capture_flow "Light" "$LIGHT_DIR"

# Dark mode
if [ "$SKIP_DARK" = false ]; then
    echo ""
    echo -e "${YELLOW}Switching to dark mode...${NC}"
    $ADB_DEV shell cmd uimode night yes 2>/dev/null || true
    sleep 2
    run_capture_flow "Dark" "$DARK_DIR"
    
    # Restore light mode
    $ADB_DEV shell cmd uimode night no 2>/dev/null || true
fi

# ============================================================
# Generate HTML viewer
# ============================================================

echo ""
echo -e "${BLUE}Generating HTML viewer...${NC}"

cat > "$OUTPUT_DIR/index.html" << HTMLHEAD
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Device Screenshots - $(date '+%b %d, %Y')</title>
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
                <span class="device">$DEVICE_MODEL</span> • $(date '+%b %d, %Y at %I:%M %p')
            </div>
        </header>
HTMLHEAD

# Check if we have both modes
HAS_LIGHT=$(ls "$LIGHT_DIR"/*.png 2>/dev/null | head -1)
HAS_DARK=$(ls "$DARK_DIR"/*.png 2>/dev/null | head -1)

if [ -n "$HAS_LIGHT" ] && [ -n "$HAS_DARK" ]; then
    cat >> "$OUTPUT_DIR/index.html" << 'TOGGLE'
        <div class="toggle">
            <button class="active" onclick="showMode('light')">Light Mode</button>
            <button onclick="showMode('dark')">Dark Mode</button>
        </div>
TOGGLE
fi

# Light mode section
if [ -n "$HAS_LIGHT" ]; then
    echo '        <div class="section" id="light-section">' >> "$OUTPUT_DIR/index.html"
    echo '            <h2>Light Mode</h2>' >> "$OUTPUT_DIR/index.html"
    echo '            <div class="gallery">' >> "$OUTPUT_DIR/index.html"
    for img in "$LIGHT_DIR"/*.png; do
        name=$(basename "$img" .png | sed 's/^[0-9]*_//;s/_/ /g')
        echo "                <div class=\"card\" onclick=\"openLightbox('screenshots/$(basename "$img")')\"><img src=\"screenshots/$(basename "$img")\"><div class=\"label\">$name</div></div>" >> "$OUTPUT_DIR/index.html"
    done
    echo '            </div>' >> "$OUTPUT_DIR/index.html"
    echo '        </div>' >> "$OUTPUT_DIR/index.html"
fi

# Dark mode section
if [ -n "$HAS_DARK" ]; then
    echo '        <div class="section hidden" id="dark-section">' >> "$OUTPUT_DIR/index.html"
    echo '            <h2>Dark Mode</h2>' >> "$OUTPUT_DIR/index.html"
    echo '            <div class="gallery">' >> "$OUTPUT_DIR/index.html"
    for img in "$DARK_DIR"/*.png; do
        name=$(basename "$img" .png | sed 's/^[0-9]*_//;s/_/ /g')
        echo "                <div class=\"card\" onclick=\"openLightbox('screenshots-dark/$(basename "$img")')\"><img src=\"screenshots-dark/$(basename "$img")\"><div class=\"label\">$name</div></div>" >> "$OUTPUT_DIR/index.html"
    done
    echo '            </div>' >> "$OUTPUT_DIR/index.html"
    echo '        </div>' >> "$OUTPUT_DIR/index.html"
fi

cat >> "$OUTPUT_DIR/index.html" << 'HTMLEND'
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

# Summary
echo ""
echo -e "${GREEN}=== Capture Complete ===${NC}"
echo ""
echo "Screenshots saved to: $OUTPUT_DIR"
echo ""
ls -la "$LIGHT_DIR"/*.png 2>/dev/null | wc -l | xargs -I {} echo "Light mode: {} screenshots"
ls -la "$DARK_DIR"/*.png 2>/dev/null | wc -l | xargs -I {} echo "Dark mode:  {} screenshots"
echo ""
echo -e "View: ${CYAN}file://$OUTPUT_DIR/index.html${NC}"

# Update latest symlink
rm -f "$SCRIPT_DIR/captures/latest" 2>/dev/null || true
ln -sf "$(basename "$OUTPUT_DIR")" "$SCRIPT_DIR/captures/latest"
