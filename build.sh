#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
ROOT="$(pwd)"
SDK="$(xcrun --show-sdk-path)"
ARCH="$(uname -m)"
case "$ARCH" in
  arm64|x86_64) ;;
  *)
    echo "Unsupported architecture: $ARCH" >&2
    exit 1
    ;;
esac
TARGET="${ARCH}-apple-macosx14.0"
APP="$ROOT/build/Grove.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$ROOT/build/icon.iconset"

swiftc -O -swift-version 5 -sdk "$SDK" -target "$TARGET" -framework AppKit \
  "$ROOT/Scripts/make-icon.swift" -o "$ROOT/build/make-icon"
"$ROOT/build/make-icon" "$ROOT/build/icon-1024.png"

while read -r pixels name; do
  sips -z "$pixels" "$pixels" "$ROOT/build/icon-1024.png" --out "$ROOT/build/icon.iconset/${name}.png" >/dev/null
done <<'EOF'
16 icon_16x16
32 icon_16x16@2x
32 icon_32x32
64 icon_32x32@2x
128 icon_128x128
256 icon_128x128@2x
256 icon_256x256
512 icon_256x256@2x
512 icon_512x512
1024 icon_512x512@2x
EOF
iconutil -c icns "$ROOT/build/icon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"

swiftc -O -parse-as-library -swift-version 5 -sdk "$SDK" -target "$TARGET" \
  -framework SwiftUI -framework AppKit -framework QuickLookUI \
  "$ROOT"/Sources/*.swift \
  -o "$APP/Contents/MacOS/Grove"

codesign --force --sign - "$APP" >/dev/null
# The project copy is only for building. Launch Services otherwise lists it
# next to the app in /Applications.
touch "$ROOT/build/.metadata_never_index"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
"$LSREGISTER" -u -f "$APP" >/dev/null || true
echo "$APP"
