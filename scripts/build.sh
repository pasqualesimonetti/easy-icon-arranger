#!/bin/bash
# Builds "Easy Icon Arranger.app" (SwiftUI + Go engine) into build/ and,
# with --install, copies it to ~/Applications.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$(pwd)
APP="$ROOT/build/Easy Icon Arranger.app"

echo "1/4 Go engine (libeia.a)"
export MACOSX_DEPLOYMENT_TARGET=26.0 CGO_ENABLED=1 GOOS=darwin GOARCH=arm64
export CGO_CFLAGS="-mmacosx-version-min=26.0" CGO_LDFLAGS="-mmacosx-version-min=26.0"
mkdir -p macos/Vendor
go build -trimpath -ldflags "-s -w" -buildmode=c-archive -o macos/Vendor/libeia.a ./libeia
cp macos/Vendor/libeia.h macos/Sources/CEIA/libeia.h

echo "2/4 SwiftUI app"
# With Xcode installed the default (newest) SDK works. The Command Line Tools
# alone lack the SwiftUI macro plugin needed by the macOS 27 SDK, so fall back
# to the newest macOS 26 SDK there.
if ! xcode-select -p | grep -q "Xcode"; then
  SDK=$(ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.*.sdk 2>/dev/null | sort -V | tail -1)
  [ -n "$SDK" ] && export SDKROOT="$SDK"
fi
(cd macos && swift build -c release --arch arm64 2>&1 | grep -vE "ld: warning: search path" )
BIN="$(cd macos && swift build -c release --arch arm64 --show-bin-path)/EasyIconArranger"

echo "3/4 App bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Easy Icon Arranger"
cp macos/Info.plist "$APP/Contents/Info.plist"
# Interface strings: one JSON file per language. The empty .lproj folders and
# CFBundleLocalizations let macOS offer a per-app language in System Settings.
cp -R macos/Localization "$APP/Contents/Resources/Localization"
PB=/usr/libexec/PlistBuddy
$PB -c "Delete :CFBundleLocalizations" "$APP/Contents/Info.plist" >/dev/null 2>&1 || true
$PB -c "Add :CFBundleLocalizations array" "$APP/Contents/Info.plist"
for f in macos/Localization/*.json; do
  code=$(basename "$f" .json)
  mkdir -p "$APP/Contents/Resources/$code.lproj"
  printf '/* Interface strings are in Localization/%s.json */\n' "$code" > "$APP/Contents/Resources/$code.lproj/InfoPlist.strings"
  $PB -c "Add :CFBundleLocalizations: string $code" "$APP/Contents/Info.plist"
done
ICONSET=$(mktemp -d)/AppIcon.iconset
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s assets/appicon.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s * 2)) $((s * 2)) assets/appicon.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - --timestamp=none "$APP"

echo "4/4 Done: $APP ($(du -sh "$APP" | cut -f1))"
if [ "${1:-}" = "--install" ]; then
  osascript -e 'quit app "Easy Icon Arranger"' >/dev/null 2>&1 || true
  sleep 1
  rm -rf "$HOME/Applications/Easy Icon Arranger.app"
  cp -R "$APP" "$HOME/Applications/"
  echo "Installed in ~/Applications"
fi
