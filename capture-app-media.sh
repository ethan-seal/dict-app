#!/bin/bash
set -e

# capture-app-media.sh - Capture screenshots and video of the app for UI/UX review
#
# Usage:
#   ./capture-app-media.sh              # Capture with default settings
#   ./capture-app-media.sh --gui        # Show emulator window while capturing
#   ./capture-app-media.sh --no-video   # Screenshots only (faster)
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
mkdir -p "$SCREENSHOT_DIR"

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
$ADB_EMU shell "mkdir -p $DEVICE_SCREENSHOT_DIR" 2>/dev/null || true

echo ""

# Start video recording in background (if enabled)
VIDEO_PID=""
if [ "$CAPTURE_VIDEO" = true ]; then
    echo -e "${BLUE}Starting video recording...${NC}"
    # screenrecord has 180s limit, which should be plenty
    $ADB_EMU shell "screenrecord --bit-rate 8000000 $DEVICE_VIDEO" &
    VIDEO_PID=$!
    sleep 1  # Let recording stabilize
fi

# Start logcat monitoring for screenshot markers
echo -e "${BLUE}Starting screenshot capture monitor...${NC}"
MARKER_PATTERN="CAPTURE_MARKER"
SCREENSHOT_COUNT=0

# Monitor logcat in background and capture screenshots when markers appear
(
    $ADB_EMU logcat -c  # Clear logcat buffer
    $ADB_EMU logcat -s "AppCapture:I" | while read -r line; do
        if echo "$line" | grep -q "$MARKER_PATTERN"; then
            MARKER_NAME=$(echo "$line" | sed -n "s/.*${MARKER_PATTERN}:\([^ ]*\).*/\1/p")
            if [ -n "$MARKER_NAME" ] && [ "$MARKER_NAME" != "DONE" ]; then
                SCREENSHOT_COUNT=$((SCREENSHOT_COUNT + 1))
                FILENAME="${MARKER_NAME}.png"
                $ADB_EMU shell "screencap -p $DEVICE_SCREENSHOT_DIR/$FILENAME"
                echo -e "  ${GREEN}✓${NC} Captured: $FILENAME"
            fi
            if [ "$MARKER_NAME" = "DONE" ]; then
                echo "CAPTURE_COMPLETE" >> /tmp/capture_done_$$
                break
            fi
        fi
    done
) &
LOGCAT_PID=$!

# Run the capture test
echo ""
echo -e "${BLUE}Running capture test flow...${NC}"
echo ""

cd android
TEST_EXIT=0
# Run only on the target emulator (not physical devices)
ANDROID_SERIAL="$EMU_SERIAL" ./gradlew connectedAndroidTest \
    -Pandroid.testInstrumentationRunnerArguments.class=org.example.dictapp.AppCaptureTest \
    --info 2>&1 | grep -E "> Task|BUILD|PASSED|FAILED|captureAppFlow|SEVERE" || TEST_EXIT=$?
cd ..

# Wait a moment for final screenshot
sleep 2

# Stop logcat monitor
kill $LOGCAT_PID 2>/dev/null || true
rm -f /tmp/capture_done_$$

# Stop video recording
if [ -n "$VIDEO_PID" ]; then
    echo ""
    echo -e "${BLUE}Stopping video recording...${NC}"
    # Send Ctrl+C to screenrecord
    $ADB_EMU shell "pkill -INT screenrecord" 2>/dev/null || true
    sleep 2
fi

# Pull captured files
echo ""
echo -e "${BLUE}Retrieving captured media...${NC}"

# Pull screenshots
PULLED_SCREENSHOTS=0
for file in $($ADB_EMU shell "ls $DEVICE_SCREENSHOT_DIR/*.png 2>/dev/null" | tr -d '\r'); do
    filename=$(basename "$file")
    $ADB_EMU pull "$file" "$SCREENSHOT_DIR/$filename" 2>/dev/null && PULLED_SCREENSHOTS=$((PULLED_SCREENSHOTS + 1))
done

if [ $PULLED_SCREENSHOTS -gt 0 ]; then
    echo -e "  ${GREEN}✓${NC} $PULLED_SCREENSHOTS screenshots saved to $SCREENSHOT_DIR/"
else
    echo -e "  ${YELLOW}!${NC} No screenshots captured"
fi

# Pull video
if [ "$CAPTURE_VIDEO" = true ]; then
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
    echo "Screenshots:"
    ls -la "$SCREENSHOT_DIR" 2>/dev/null | tail -n +2 || true
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
            padding: 2rem;
        }
        .container { max-width: 1400px; margin: 0 auto; }
        header {
            text-align: center;
            margin-bottom: 2rem;
            padding-bottom: 1rem;
            border-bottom: 1px solid #333;
        }
        h1 { font-size: 1.5rem; font-weight: 500; margin-bottom: 0.5rem; }
        .timestamp { color: #888; font-size: 0.9rem; }
        .commit { color: #666; font-size: 0.8rem; font-family: monospace; margin-top: 0.25rem; }
        .commit a { color: #6a9fb5; text-decoration: none; }
        .commit a:hover { text-decoration: underline; }
        .video-section { margin-bottom: 2rem; text-align: center; }
        .video-section h2, .screenshots-section h2 {
            font-size: 1rem;
            font-weight: 500;
            margin-bottom: 1rem;
            color: #aaa;
        }
        video {
            max-width: 400px;
            width: 100%;
            border-radius: 12px;
            box-shadow: 0 4px 20px rgba(0,0,0,0.4);
        }
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
        .screenshot-card .label {
            padding: 0.75rem;
            font-size: 0.8rem;
            color: #aaa;
            text-align: center;
            background: #1e1e36;
        }
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
        @media (max-width: 600px) {
            body { padding: 1rem; }
            .gallery { grid-template-columns: repeat(2, 1fr); gap: 1rem; }
        }
    </style>
</head>
<body>
    <div class="container">
        <header>
            <h1>Dict App - UI Capture</h1>
            <div class="timestamp">$display_ts</div>
            $commit_html
        </header>
HTMLHEAD

    # Add video section if video exists
    if [ "$has_video" = "true" ]; then
        cat >> "$html_file" << 'HTMLVIDEO'
        <section class="video-section">
            <h2>App Flow Video</h2>
            <video controls>
                <source src="app-flow.mp4" type="video/mp4">
                Your browser does not support video playback.
            </video>
        </section>
HTMLVIDEO
    fi

    # Start screenshots section
    cat >> "$html_file" << 'HTMLGALLERY'
        <section class="screenshots-section">
            <h2>Screenshots</h2>
            <div class="gallery" id="gallery">
HTMLGALLERY

    # Add screenshot cards
    local index=0
    local found_screenshots=false
    if [ -d "$SCREENSHOT_DIR" ]; then
        for img in $(ls -1 "$SCREENSHOT_DIR"/*.png 2>/dev/null | sort); do
            found_screenshots=true
            local filename=$(basename "$img")
            local label=$(basename "$img" .png | sed 's/^[0-9]*_//;s/_/ /g')
            cat >> "$html_file" << HTMLCARD
                <div class="screenshot-card" onclick="openLightbox($index)">
                    <img src="screenshots/$filename" alt="$label">
                    <div class="label">$label</div>
                </div>
HTMLCARD
            index=$((index + 1))
        done
    fi
    
    if [ "$found_screenshots" = false ]; then
        echo '                <div class="no-content">No screenshots captured</div>' >> "$html_file"
    fi

    # Close gallery and add lightbox + script
    cat >> "$html_file" << 'HTMLEND'
            </div>
        </section>
    </div>
    
    <div class="lightbox" id="lightbox">
        <span class="close" onclick="closeLightbox()">&times;</span>
        <span class="nav prev" onclick="navigate(-1)">&#10094;</span>
        <span class="nav next" onclick="navigate(1)">&#10095;</span>
        <img id="lightbox-img" src="" alt="">
        <div class="caption" id="lightbox-caption"></div>
    </div>
    
    <script>
        const images = Array.from(document.querySelectorAll('.screenshot-card img'));
        let currentIndex = 0;
        
        function openLightbox(index) {
            currentIndex = index;
            updateLightbox();
            document.getElementById('lightbox').classList.add('active');
            document.body.style.overflow = 'hidden';
        }
        
        function closeLightbox() {
            document.getElementById('lightbox').classList.remove('active');
            document.body.style.overflow = '';
        }
        
        function navigate(dir) {
            currentIndex = (currentIndex + dir + images.length) % images.length;
            updateLightbox();
        }
        
        function updateLightbox() {
            const img = images[currentIndex];
            document.getElementById('lightbox-img').src = img.src;
            document.getElementById('lightbox-caption').textContent = img.alt;
        }
        
        document.addEventListener('keydown', (e) => {
            if (!document.getElementById('lightbox').classList.contains('active')) return;
            if (e.key === 'Escape') closeLightbox();
            if (e.key === 'ArrowLeft') navigate(-1);
            if (e.key === 'ArrowRight') navigate(1);
        });
        
        document.getElementById('lightbox').addEventListener('click', (e) => {
            if (e.target.id === 'lightbox') closeLightbox();
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
