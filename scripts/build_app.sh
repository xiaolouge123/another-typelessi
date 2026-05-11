#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="another-typelessi"
EXECUTABLE_NAME="AnotherTypeless"
CONFIG="${CONFIG:-release}"
INSTALL_DIR="${INSTALL_DIR:-/Applications}"

cd "$ROOT_DIR"
swift build -c "$CONFIG"

BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"
BIN_PATH="$BIN_DIR/$EXECUTABLE_NAME"

if [[ ! -x "$BIN_PATH" ]]; then
  echo "Built executable not found at $BIN_PATH" >&2
  exit 1
fi

APP_DIR="$ROOT_DIR/build/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
install -m 755 "$BIN_PATH" "$MACOS_DIR/$EXECUTABLE_NAME"
install -m 644 "$ROOT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"

codesign --force --deep --sign - "$APP_DIR" >/dev/null

INSTALL_APP_DIR="$INSTALL_DIR/$APP_NAME.app"
ditto "$APP_DIR" "$INSTALL_APP_DIR"
codesign --force --deep --sign - "$INSTALL_APP_DIR" >/dev/null

echo "$INSTALL_APP_DIR"
