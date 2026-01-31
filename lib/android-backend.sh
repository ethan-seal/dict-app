#!/bin/bash
# android-backend.sh - Backend abstraction for Android device/emulator operations
#
# This library provides a unified interface for interacting with Android devices
# and emulators, abstracting away the differences between Espresso tests and adb commands.
#
# Usage:
#   source lib/android-backend.sh
#   backend_init --target device|emulator [--serial <id>]
#   backend_tap 540 600
#   backend_type "hello"
#   backend_screenshot "name" "/path/to/output.png"
#   backend_cleanup

# Backend state
BACKEND_TARGET=""           # "device" or "emulator"
BACKEND_SERIAL=""           # Device/emulator serial
BACKEND_ADB=""              # Path to adb executable
BACKEND_USE_ESPRESSO=false  # Whether to use Espresso (if available)
BACKEND_SCREEN_W=0          # Screen width in pixels
BACKEND_SCREEN_H=0          # Screen height in pixels
BACKEND_PKG="org.example.dictapp"
BACKEND_ACTIVITY="org.example.dictapp.MainActivity"

# Error codes
BACKEND_ERR_NOT_INITIALIZED=10
BACKEND_ERR_NO_DEVICE=11
BACKEND_ERR_INVALID_TARGET=12

# Initialize backend
# Usage: backend_init --target device|emulator [--serial <id>]
backend_init() {
    local target=""
    local serial=""
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --target)
                target="$2"
                shift 2
                ;;
            --serial)
                serial="$2"
                shift 2
                ;;
            *)
                echo "backend_init: Unknown option $1" >&2
                return 1
                ;;
        esac
    done
    
    if [ -z "$target" ]; then
        echo "backend_init: --target required (device|emulator)" >&2
        return $BACKEND_ERR_INVALID_TARGET
    fi
    
    if [[ "$target" != "device" && "$target" != "emulator" ]]; then
        echo "backend_init: Invalid target '$target' (must be device|emulator)" >&2
        return $BACKEND_ERR_INVALID_TARGET
    fi
    
    BACKEND_TARGET="$target"
    
    # Find ADB
    backend_find_adb || return $?
    
    # Find device/emulator
    if [ -n "$serial" ]; then
        BACKEND_SERIAL="$serial"
    else
        backend_find_target "$target" || return $?
    fi
    
    # Verify device exists
    if ! $BACKEND_ADB -s "$BACKEND_SERIAL" get-state >/dev/null 2>&1; then
        echo "backend_init: Device $BACKEND_SERIAL not found or offline" >&2
        return $BACKEND_ERR_NO_DEVICE
    fi
    
    # Get screen dimensions
    local size=$($BACKEND_ADB -s "$BACKEND_SERIAL" shell wm size 2>/dev/null | grep -oE '[0-9]+x[0-9]+' | tail -1)
    BACKEND_SCREEN_W=$(echo "$size" | cut -dx -f1)
    BACKEND_SCREEN_H=$(echo "$size" | cut -dx -f2)
    
    # Determine if we should use Espresso (emulator only for now)
    # Try Espresso first, fall back to adb
    if [[ "$target" == "emulator" ]]; then
        # Check if test APK is installed
        if $BACKEND_ADB -s "$BACKEND_SERIAL" shell pm list packages | grep -q "$BACKEND_PKG.test"; then
            BACKEND_USE_ESPRESSO=true
        fi
    fi
    
    return 0
}

# Find adb executable
backend_find_adb() {
    # Check common locations
    if [ -n "$ANDROID_SDK_ROOT" ] && [ -x "$ANDROID_SDK_ROOT/platform-tools/adb" ]; then
        BACKEND_ADB="$ANDROID_SDK_ROOT/platform-tools/adb"
    elif [ -n "$ANDROID_HOME" ] && [ -x "$ANDROID_HOME/platform-tools/adb" ]; then
        BACKEND_ADB="$ANDROID_HOME/platform-tools/adb"
    elif [ -d "$HOME/Android/Sdk/platform-tools" ]; then
        BACKEND_ADB="$HOME/Android/Sdk/platform-tools/adb"
    elif [ -d "$HOME/android/sdk/platform-tools" ]; then
        BACKEND_ADB="$HOME/android/sdk/platform-tools/adb"
    elif command -v adb >/dev/null 2>&1; then
        BACKEND_ADB="adb"
    else
        echo "backend_find_adb: adb not found" >&2
        return 1
    fi
    return 0
}

# Find target device/emulator
backend_find_target() {
    local target="$1"
    local device=""
    
    if [[ "$target" == "device" ]]; then
        # Find physical device (not emulator)
        device=$($BACKEND_ADB devices 2>/dev/null | grep -v "emulator-" | grep -E "^\S+\s+device$" | head -1 | cut -f1)
    else
        # Find emulator
        device=$($BACKEND_ADB devices 2>/dev/null | grep "emulator-" | grep -E "\s+device$" | head -1 | cut -f1)
    fi
    
    if [ -z "$device" ]; then
        echo "backend_find_target: No $target found" >&2
        $BACKEND_ADB devices -l >&2
        return $BACKEND_ERR_NO_DEVICE
    fi
    
    BACKEND_SERIAL="$device"
    return 0
}

# Check if backend is initialized
backend_check_init() {
    if [ -z "$BACKEND_SERIAL" ]; then
        echo "backend: Not initialized. Call backend_init first." >&2
        return $BACKEND_ERR_NOT_INITIALIZED
    fi
    return 0
}

# Wait for UI to settle
backend_wait() {
    local duration="${1:-0.5}"
    sleep "$duration"
}

# Tap at coordinates
# Usage: backend_tap <x> <y>
backend_tap() {
    backend_check_init || return $?
    local x=$1
    local y=$2
    
    $BACKEND_ADB -s "$BACKEND_SERIAL" shell input tap "$x" "$y"
    backend_wait 0.5
}

# Tap center of screen
backend_tap_center() {
    backend_check_init || return $?
    backend_tap $((BACKEND_SCREEN_W / 2)) $((BACKEND_SCREEN_H / 2))
}

# Swipe up
backend_swipe_up() {
    backend_check_init || return $?
    local start_y=$((BACKEND_SCREEN_H * 3 / 4))
    local end_y=$((BACKEND_SCREEN_H / 4))
    local x=$((BACKEND_SCREEN_W / 2))
    $BACKEND_ADB -s "$BACKEND_SERIAL" shell input swipe "$x" "$start_y" "$x" "$end_y" 300
    backend_wait 0.5
}

# Swipe down
backend_swipe_down() {
    backend_check_init || return $?
    local start_y=$((BACKEND_SCREEN_H / 4))
    local end_y=$((BACKEND_SCREEN_H * 3 / 4))
    local x=$((BACKEND_SCREEN_W / 2))
    $BACKEND_ADB -s "$BACKEND_SERIAL" shell input swipe "$x" "$start_y" "$x" "$end_y" 300
    backend_wait 0.5
}

# Type text
# Usage: backend_type "hello world"
backend_type() {
    backend_check_init || return $?
    local text="$1"
    $BACKEND_ADB -s "$BACKEND_SERIAL" shell input text "$text"
    backend_wait 0.5
}

# Press key
# Usage: backend_key KEYCODE_BACK
backend_key() {
    backend_check_init || return $?
    local keycode="$1"
    $BACKEND_ADB -s "$BACKEND_SERIAL" shell input keyevent "$keycode"
    backend_wait 0.3
}

# Press back button
backend_back() {
    backend_key KEYCODE_BACK
}

# Press enter
backend_enter() {
    backend_key KEYCODE_ENTER
}

# Clear text field (select all and delete)
backend_clear_text() {
    backend_check_init || return $?
    $BACKEND_ADB -s "$BACKEND_SERIAL" shell input keyevent KEYCODE_MOVE_END
    for i in {1..30}; do
        $BACKEND_ADB -s "$BACKEND_SERIAL" shell input keyevent KEYCODE_DEL
    done
    backend_wait 0.3
}

# Open app
# Usage: backend_open_app [package] [activity]
backend_open_app() {
    backend_check_init || return $?
    local pkg="${1:-$BACKEND_PKG}"
    local activity="${2:-$BACKEND_ACTIVITY}"
    
    $BACKEND_ADB -s "$BACKEND_SERIAL" shell am start -n "$pkg/$activity" >/dev/null 2>&1
    backend_wait 2
}

# Force stop app
# Usage: backend_stop_app [package]
backend_stop_app() {
    backend_check_init || return $?
    local pkg="${1:-$BACKEND_PKG}"
    
    $BACKEND_ADB -s "$BACKEND_SERIAL" shell am force-stop "$pkg"
    backend_wait 0.5
}

# Restart app (stop then start)
backend_restart_app() {
    backend_stop_app "$@"
    backend_open_app "$@"
}

# Take screenshot
# Usage: backend_screenshot "name" "/path/to/output.png"
backend_screenshot() {
    backend_check_init || return $?
    local name="$1"
    local output="$2"
    local tmp="/sdcard/backend_screenshot.png"
    
    $BACKEND_ADB -s "$BACKEND_SERIAL" shell screencap -p "$tmp"
    $BACKEND_ADB -s "$BACKEND_SERIAL" pull "$tmp" "$output" 2>/dev/null
    $BACKEND_ADB -s "$BACKEND_SERIAL" shell rm -f "$tmp"
}

# Find element by UI Automator and tap it
# Usage: backend_tap_text "Button text"
backend_tap_text() {
    backend_check_init || return $?
    local text="$1"
    
    # Dump UI to find element
    $BACKEND_ADB -s "$BACKEND_SERIAL" shell uiautomator dump /dev/tty 2>/dev/null | \
        grep -oE "text=\"$text\"[^>]*bounds=\"\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\]\"" | \
        head -1 | grep -oE 'bounds="\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\]"' | \
        grep -oE '[0-9]+' | {
        read -r left
        read -r top
        read -r right
        read -r bottom
        if [ -n "$left" ]; then
            local x=$(( (left + right) / 2 ))
            local y=$(( (top + bottom) / 2 ))
            backend_tap "$x" "$y"
            return 0
        fi
        return 1
    }
}

# Find search field and tap it
backend_tap_search() {
    backend_check_init || return $?
    
    # Dump UI and find EditText bounds
    $BACKEND_ADB -s "$BACKEND_SERIAL" shell uiautomator dump /sdcard/ui_dump.xml 2>/dev/null
    local bounds=$($BACKEND_ADB -s "$BACKEND_SERIAL" shell "cat /sdcard/ui_dump.xml" 2>/dev/null | \
        grep -o 'EditText[^>]*bounds="\[[0-9]*,[0-9]*\]\[[0-9]*,[0-9]*\]"' | \
        head -1 | grep -oE '\[([0-9]+),([0-9]+)\]\[([0-9]+),([0-9]+)\]')
    
    if [ -n "$bounds" ]; then
        local left=$(echo "$bounds" | grep -oE '[0-9]+' | sed -n '1p')
        local top=$(echo "$bounds" | grep -oE '[0-9]+' | sed -n '2p')
        local right=$(echo "$bounds" | grep -oE '[0-9]+' | sed -n '3p')
        local bottom=$(echo "$bounds" | grep -oE '[0-9]+' | sed -n '4p')
        local x=$(( (left + right) / 2 ))
        local y=$(( (top + bottom) / 2 ))
        backend_tap "$x" "$y"
        return 0
    else
        # Fallback: tap typical search field location
        backend_tap $((BACKEND_SCREEN_W / 2)) 400
        return 0
    fi
}

# Find first search result and tap it
backend_tap_first_result() {
    backend_check_init || return $?
    
    $BACKEND_ADB -s "$BACKEND_SERIAL" shell uiautomator dump /sdcard/ui_dump.xml 2>/dev/null
    # Look for clickable views below y=500 (below search bar)
    local bounds=$($BACKEND_ADB -s "$BACKEND_SERIAL" shell "cat /sdcard/ui_dump.xml" 2>/dev/null | \
        grep 'clickable="true"' | grep -oE 'bounds="\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\]"' | \
        while read b; do
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
        backend_tap "$x" "$y"
        return 0
    else
        # Fallback: tap below search bar
        backend_tap $((BACKEND_SCREEN_W / 2)) 650
        return 0
    fi
}

# Set dark mode
backend_dark_mode() {
    backend_check_init || return $?
    local enable="${1:-yes}"  # yes or no
    $BACKEND_ADB -s "$BACKEND_SERIAL" shell cmd uimode night "$enable" 2>/dev/null || true
    backend_wait 1
}

# Get device info
backend_get_info() {
    backend_check_init || return $?
    
    local model=$($BACKEND_ADB -s "$BACKEND_SERIAL" shell getprop ro.product.model 2>/dev/null | tr -d '\r')
    local sdk=$($BACKEND_ADB -s "$BACKEND_SERIAL" shell getprop ro.build.version.sdk 2>/dev/null | tr -d '\r')
    local abi=$($BACKEND_ADB -s "$BACKEND_SERIAL" shell getprop ro.product.cpu.abi 2>/dev/null | tr -d '\r')
    
    echo "model=$model"
    echo "sdk=$sdk"
    echo "abi=$abi"
    echo "serial=$BACKEND_SERIAL"
    echo "screen=${BACKEND_SCREEN_W}x${BACKEND_SCREEN_H}"
}

# Check if app is installed
backend_app_installed() {
    backend_check_init || return $?
    local pkg="${1:-$BACKEND_PKG}"
    
    $BACKEND_ADB -s "$BACKEND_SERIAL" shell pm list packages 2>/dev/null | grep -q "^package:$pkg$"
}

# Install APK
# Usage: backend_install_apk /path/to/app.apk
backend_install_apk() {
    backend_check_init || return $?
    local apk="$1"
    
    if [ ! -f "$apk" ]; then
        echo "backend_install_apk: File not found: $apk" >&2
        return 1
    fi
    
    $BACKEND_ADB -s "$BACKEND_SERIAL" install -r -g "$apk" 2>&1
}

# Uninstall app
backend_uninstall_app() {
    backend_check_init || return $?
    local pkg="${1:-$BACKEND_PKG}"
    
    $BACKEND_ADB -s "$BACKEND_SERIAL" uninstall "$pkg" 2>&1
}

# Clear logcat
backend_logcat_clear() {
    backend_check_init || return $?
    $BACKEND_ADB -s "$BACKEND_SERIAL" logcat -c
}

# Get logcat with filters
# Usage: backend_logcat [-d] [tag:level ...]
backend_logcat() {
    backend_check_init || return $?
    $BACKEND_ADB -s "$BACKEND_SERIAL" logcat "$@"
}

# Cleanup
backend_cleanup() {
    # Remove temp files
    if [ -n "$BACKEND_SERIAL" ] && [ -n "$BACKEND_ADB" ]; then
        $BACKEND_ADB -s "$BACKEND_SERIAL" shell rm -f /sdcard/ui_dump.xml /sdcard/backend_screenshot.png 2>/dev/null || true
    fi
}
