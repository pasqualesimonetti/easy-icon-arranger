#!/bin/bash
# Packages build/Easy Icon Arranger.app into dist/Easy-Icon-Arranger.dmg: a
# window with the app, an Applications shortcut and a background that says
# to drag one onto the other. Run scripts/build.sh first.
set -euo pipefail
cd "$(dirname "$0")/.."
NAME="Easy Icon Arranger"
APP="build/$NAME.app"
OUT="dist/Easy-Icon-Arranger.dmg"
[ -d "$APP" ] || { echo "Missing $APP, run scripts/build.sh first"; exit 1; }

WORK=$(mktemp -d)
trap '[ -n "${MNT:-}" ] && hdiutil detach "$MNT" -quiet 2>/dev/null; rm -rf "$WORK"' EXIT
STAGE="$WORK/stage"
mkdir -p "$STAGE/.background" dist
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
tiffutil -cathidpicheck assets/dmg/background.png assets/dmg/background@2x.png -out "$STAGE/.background/background.tiff" >/dev/null

echo "1/3 Writable image"
hdiutil create -quiet -srcfolder "$STAGE" -volname "$NAME" -fs HFS+ -format UDRW -ov "$WORK/rw.dmg"
MNT=$(hdiutil attach -readwrite -noverify -noautoopen "$WORK/rw.dmg" | grep -o "/Volumes/.*$" | head -1)
echo "   mounted at $MNT"
# custom volume icon (needs SetFile from the Xcode tools; skipped otherwise)
if command -v SetFile >/dev/null; then
  cp "$APP/Contents/Resources/AppIcon.icns" "$MNT/.VolumeIcon.icns"
  SetFile -a C "$MNT"
fi

echo "2/3 Window layout"
# Finder lays out the window; this needs permission to control Finder the
# first time. If it is refused the DMG still works, just without the layout.
osascript <<EOF || echo "   Finder layout skipped"
tell application "Finder"
  set d to disk "$(basename "$MNT")"
  open d
  set w to container window of d
  set current view of w to icon view
  set toolbar visible of w to false
  set statusbar visible of w to false
  set bounds of w to {200, 120, 860, 560}
  set o to icon view options of w
  set arrangement of o to not arranged
  set icon size of o to 128
  set text size of o to 13
  set background picture of o to file ".background:background.tiff" of d
  set position of item "$NAME.app" of d to {165, 215}
  set position of item "Applications" of d to {495, 215}
  update d without registering applications
  delay 1
  close w
end tell
EOF
sync
hdiutil detach -quiet "$MNT"; MNT=

echo "3/3 Compressed image"
rm -f "$OUT"
hdiutil convert -quiet "$WORK/rw.dmg" -format UDZO -imagekey zlib-level=9 -o "$OUT"
echo "Done: $OUT ($(du -h "$OUT" | cut -f1))"
