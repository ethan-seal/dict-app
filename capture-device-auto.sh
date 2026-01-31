#!/bin/bash
# DEPRECATED: This script has been replaced by run-e2e.sh
#
# This script is kept for backwards compatibility but will be removed in the future.
# Please use the new unified script instead:
#
#   ./run-e2e.sh capture --target device [OPTIONS]
#
# Examples:
#   ./run-e2e.sh capture --target device
#   ./run-e2e.sh capture --target device --skip-dark
#   ./run-e2e.sh capture --target device --serial <id>

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "⚠️  DEPRECATED: capture-device-auto.sh"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "This script has been replaced by: ./run-e2e.sh"
echo ""
echo "Please use instead:"
echo "  ./run-e2e.sh capture --target device [OPTIONS]"
echo ""
echo "Examples:"
echo "  ./run-e2e.sh capture --target device"
echo "  ./run-e2e.sh capture --target device --skip-dark"
echo ""
echo "Run './run-e2e.sh --help' for full usage"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Auto-convert flags
ARGS="--target device"

for arg in "$@"; do
    case "$arg" in
        --serial)
            ARGS="$ARGS --serial"
            ;;
        --skip-dark)
            ARGS="$ARGS --skip-dark"
            ;;
    esac
done

echo "Auto-converting to: ./run-e2e.sh capture $ARGS"
echo ""
read -p "Continue? (Y/n) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    exec ./run-e2e.sh capture $ARGS
fi

exit 1
