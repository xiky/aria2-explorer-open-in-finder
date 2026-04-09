#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_APP="$ROOT_DIR/Aria2Browse.app"
DEST_DIR="$HOME/Applications"
DEST_APP="$DEST_DIR/Aria2Browse.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

"$ROOT_DIR/build.sh" >/dev/null

mkdir -p "$DEST_DIR"
rm -rf "$DEST_APP"
cp -R "$SRC_APP" "$DEST_APP"
codesign --force --deep -s - "$DEST_APP" >/dev/null

if "$LSREGISTER" -f "$DEST_APP" >/dev/null 2>&1; then
  echo "Registered URL scheme with LaunchServices: $DEST_APP"
else
  echo "Copied app to: $DEST_APP"
  echo "LaunchServices did not register it from CLI."
  echo "Open the app once in Finder, then retry the aria2:// link."
fi

echo
echo "Set Aria2-Explorer -> RPC -> 下载目录打开程序URL to:"
echo "aria2://browse?dir={taskdir}&name={taskname}"
