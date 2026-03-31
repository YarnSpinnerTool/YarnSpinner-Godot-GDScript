#!/usr/bin/env bash
# ======================================================================== #
#                    Yarn Spinner for Godot (GDScript)                     #
# ======================================================================== #
#
# Builds the NativeAOT compiler for all desktop platforms.
# The compiler source is referenced from the YarnSpinner repo — no copies.
#
# Usage:
#   ./build.sh              # build for current platform
#   ./build.sh all          # cross-compile for all platforms
#   ./build.sh macos        # macOS only (universal binary)
#   ./build.sh windows      # Windows x64 only
#   ./build.sh linux        # Linux x64 only
#
# Output goes to:
#   addons/yarn_spinner/native/bin/
#     ysc-native              (macOS universal)
#     ysc-native.exe          (Windows x64)
#     ysc-native-linux        (Linux x64)
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLI_PROJECT="$SCRIPT_DIR/YarnSpinner.NativeCompilerCLI"
LIB_PROJECT="$SCRIPT_DIR/YarnSpinner.NativeCompiler"
OUTPUT_DIR="$SCRIPT_DIR/../addons/yarn_spinner/native/bin"

mkdir -p "$OUTPUT_DIR"

build_cli() {
    local rid="$1"
    local output_name="$2"

    echo "Building CLI for $rid..."
    dotnet publish "$CLI_PROJECT/YarnSpinner.NativeCompilerCLI.csproj" \
        -c Release \
        -r "$rid" \
        --self-contained \
        -o "$SCRIPT_DIR/bin/cli-$rid"

    local exe_name="YarnSpinner.NativeCompilerCLI"
    if [[ "$rid" == win-* ]]; then
        exe_name="YarnSpinner.NativeCompilerCLI.exe"
    fi

    if [[ -f "$SCRIPT_DIR/bin/cli-$rid/$exe_name" ]]; then
        cp "$SCRIPT_DIR/bin/cli-$rid/$exe_name" "$OUTPUT_DIR/$output_name"
        chmod +x "$OUTPUT_DIR/$output_name"
        echo "  → $OUTPUT_DIR/$output_name ($(du -h "$OUTPUT_DIR/$output_name" | cut -f1))"
    else
        echo "  ERROR: Expected output not found"
        ls -la "$SCRIPT_DIR/bin/cli-$rid/" 2>/dev/null || true
        return 1
    fi
}

build_macos() {
    build_cli "osx-arm64" "ysc-native-arm64"
    build_cli "osx-x64" "ysc-native-x64"

    echo "Creating macOS universal binary..."
    lipo -create \
        "$OUTPUT_DIR/ysc-native-arm64" \
        "$OUTPUT_DIR/ysc-native-x64" \
        -output "$OUTPUT_DIR/ysc-native"
    chmod +x "$OUTPUT_DIR/ysc-native"

    rm "$OUTPUT_DIR/ysc-native-arm64" "$OUTPUT_DIR/ysc-native-x64"
    echo "  → $OUTPUT_DIR/ysc-native ($(du -h "$OUTPUT_DIR/ysc-native" | cut -f1))"
}

build_windows() {
    build_cli "win-x64" "ysc-native.exe"
}

build_linux() {
    build_cli "linux-x64" "ysc-native-linux"
}

build_current() {
    case "$(uname -s)" in
        Darwin)  build_macos ;;
        Linux)   build_linux ;;
        MINGW*|CYGWIN*|MSYS*) build_windows ;;
        *) echo "Unknown platform: $(uname -s)"; exit 1 ;;
    esac
}

case "${1:-current}" in
    all)     build_macos; build_windows; build_linux ;;
    macos)   build_macos ;;
    windows) build_windows ;;
    linux)   build_linux ;;
    current) build_current ;;
    *)       echo "Usage: $0 [all|macos|windows|linux|current]"; exit 1 ;;
esac

echo ""
echo "Done. Binaries in $OUTPUT_DIR:"
ls -lh "$OUTPUT_DIR"/ 2>/dev/null || echo "(empty)"
