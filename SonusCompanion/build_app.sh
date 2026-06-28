#!/usr/bin/env bash
# Build Sonus.app for release and package Sonus-macos.zip for GitHub Releases.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

SCHEME="SonusCompanion"
APP_NAME="Sonus"
CONFIGURATION="${CONFIGURATION:-Release}"
BUILD_DIR="$SCRIPT_DIR/build"
DERIVED_DATA="$BUILD_DIR/DerivedData"
ZIP_NAME="Sonus-macos.zip"

usage() {
    cat <<EOF
Usage: $0 release [version]

  release [version]  Release build, ad-hoc sign, zip -> build/$ZIP_NAME
                     version defaults to latest git tag (without v prefix)

Environment:
  CONFIGURATION      Xcode configuration (default: Release)
  DEVELOPER_ID       Optional codesign identity for Developer ID builds
EOF
}

resolve_version() {
    if [[ -n "${1:-}" ]]; then
        echo "$1"
        return
    fi
    if git -C "$SCRIPT_DIR/.." describe --tags --abbrev=0 >/dev/null 2>&1; then
        git -C "$SCRIPT_DIR/.." describe --tags --abbrev=0 | sed 's/^v//'
        return
    fi
    echo "0.0.0"
}

release() {
    local version
    version="$(resolve_version "${1:-}")"
    local app_path="$DERIVED_DATA/Build/Products/$CONFIGURATION/$APP_NAME.app"
    local zip_path="$BUILD_DIR/$ZIP_NAME"

    echo "Building $APP_NAME $version ($CONFIGURATION)..."

    rm -rf "$BUILD_DIR"
    mkdir -p "$BUILD_DIR"

    xcodebuild \
        -scheme "$SCHEME" \
        -configuration "$CONFIGURATION" \
        -derivedDataPath "$DERIVED_DATA" \
        MARKETING_VERSION="$version" \
        CURRENT_PROJECT_VERSION="$version" \
        build

    if [[ ! -d "$app_path" ]]; then
        echo "error: expected app at $app_path" >&2
        exit 1
    fi

    local sign_identity="-"
    if [[ -n "${DEVELOPER_ID:-}" ]]; then
        sign_identity="$DEVELOPER_ID"
    fi
    codesign --force --deep -s "$sign_identity" "$app_path"

    rm -f "$zip_path"
    COPYFILE_DISABLE=1 ditto -c -k --keepParent --norsrc "$app_path" "$zip_path"

    echo "OK: $zip_path"
    echo "Bundle: $(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app_path/Contents/Info.plist")"
}

case "${1:-}" in
    release)
        release "${2:-}"
        ;;
    -h|--help|help|"")
        usage
        [[ "${1:-}" == "release" ]] || exit 0
        ;;
    *)
        echo "error: unknown command '$1'" >&2
        usage
        exit 1
        ;;
esac
