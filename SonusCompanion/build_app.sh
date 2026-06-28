#!/usr/bin/env bash
# Build Sonus.app for release and package Sonus-macos.zip for GitHub Releases.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$SCRIPT_DIR"

SCHEME="SonusCompanion"
APP_NAME="Sonus"
CONFIGURATION="${CONFIGURATION:-Release}"
BUILD_DIR="$SCRIPT_DIR/build"
DERIVED_DATA="$BUILD_DIR/DerivedData"
RUNTIME_STAGING="$BUILD_DIR/sonus-runtime"
ZIP_NAME="Sonus-macos.zip"

usage() {
    cat <<EOF
Usage: $0 release [version]

  release [version]  Release build, bundle embedded Python runtime, ad-hoc sign,
                     zip -> build/$ZIP_NAME
                     version defaults to latest git tag (without v prefix)

Environment:
  CONFIGURATION      Xcode configuration (default: Release)
  DEVELOPER_ID       Optional codesign identity for Developer ID builds
  SKIP_RUNTIME       Set to 1 to skip embedding Python (local UI-only builds)
EOF
}

resolve_version() {
    if [[ -n "${1:-}" ]]; then
        echo "$1"
        return
    fi
    if git -C "$REPO_ROOT" describe --tags --abbrev=0 >/dev/null 2>&1; then
        git -C "$REPO_ROOT" describe --tags --abbrev=0 | sed 's/^v//'
        return
    fi
    echo "0.0.0"
}

sign_runtime_binaries() {
    local runtime_dir="$1"
    local sign_identity="$2"
    echo "Signing embedded runtime binaries..."
    find "$runtime_dir" \( -name "*.so" -o -name "*.dylib" -o -name "python*" -o -name "uvicorn" \) -type f | while read -r f; do
        codesign --force -s "$sign_identity" "$f" 2>/dev/null || true
    done
}

release() {
    local version
    version="$(resolve_version "${1:-}")"
    local app_path="$DERIVED_DATA/Build/Products/$CONFIGURATION/$APP_NAME.app"
    local zip_path="$BUILD_DIR/$ZIP_NAME"
    local resources_dir="$app_path/Contents/Resources/sonus-runtime"

    echo "Building $APP_NAME $version ($CONFIGURATION)..."

    rm -rf "$BUILD_DIR"
    mkdir -p "$BUILD_DIR"

    if [[ "${SKIP_RUNTIME:-0}" != "1" ]]; then
        bash "$REPO_ROOT/scripts/bundle-python-runtime.sh" "$RUNTIME_STAGING"
    else
        echo "SKIP_RUNTIME=1 — building app without embedded Python runtime"
    fi

    xcodebuild \
        -scheme "$SCHEME" \
        -configuration "$CONFIGURATION" \
        -destination 'generic/platform=macOS' \
        -derivedDataPath "$DERIVED_DATA" \
        MARKETING_VERSION="$version" \
        CURRENT_PROJECT_VERSION="$version" \
        CODE_SIGN_IDENTITY="-" \
        build

    if [[ ! -d "$app_path" ]]; then
        echo "error: expected app at $app_path" >&2
        exit 1
    fi

    if [[ -d "$RUNTIME_STAGING" ]]; then
        echo "Embedding sonus-runtime into app bundle..."
        rm -rf "$resources_dir"
        mkdir -p "$app_path/Contents/Resources"
        cp -R "$RUNTIME_STAGING" "$resources_dir"
    fi

    local sign_identity="-"
    if [[ -n "${DEVELOPER_ID:-}" ]]; then
        sign_identity="$DEVELOPER_ID"
    fi

    if [[ -d "$resources_dir" ]]; then
        sign_runtime_binaries "$resources_dir" "$sign_identity"
    fi

    codesign --force --deep -s "$sign_identity" "$app_path"

    rm -f "$zip_path"
    COPYFILE_DISABLE=1 ditto -c -k --keepParent --norsrc "$app_path" "$zip_path"

    echo "OK: $zip_path"
    echo "Bundle: $(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app_path/Contents/Info.plist")"
    if [[ -d "$resources_dir" ]]; then
        echo "Embedded runtime: $resources_dir/bin/python3"
    fi
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
