#!/bin/bash
# DEPRECATED: This script has been replaced by run-e2e.sh
#
# This script is kept for backwards compatibility but will be removed in the future.
# Please use the new unified script instead:
#
#   ./run-e2e.sh capture --target emulator|device [OPTIONS]
#
# Examples:
#   ./run-e2e.sh capture --target emulator
#   ./run-e2e.sh capture --target device --no-video
#   ./run-e2e.sh capture --target emulator --skip-dark

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "⚠️  DEPRECATED: capture-app-media.sh"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "This script has been replaced by: ./run-e2e.sh"
echo ""
echo "Please use instead:"
echo "  ./run-e2e.sh capture --target emulator|device [OPTIONS]"
echo ""
echo "Examples:"
echo "  ./run-e2e.sh capture --target emulator"
echo "  ./run-e2e.sh capture --target device --no-video"
echo ""
echo "Run './run-e2e.sh --help' for full usage"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Try to auto-convert old flags to new ones
ARGS=""

# Detect target
if echo "$@" | grep -q -- "--device"; then
    ARGS="--target device"
else
    ARGS="--target emulator"
fi

# Pass through other flags
for arg in "$@"; do
    case "$arg" in
        --no-video|--skip-dark|--skip-build)
            ARGS="$ARGS $arg"
            ;;
        --device)
            # Already handled above
            ;;
        --serial)
            ARGS="$ARGS --serial"
            ;;
    esac
done

if [ -n "$ARGS" ]; then
    echo "Auto-converting to: ./run-e2e.sh capture $ARGS"
    echo ""
    read -p "Continue? (Y/n) " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        exec ./run-e2e.sh capture $ARGS
    fi
fi

exit 1
