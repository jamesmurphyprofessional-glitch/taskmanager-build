#!/bin/zsh
# Double-click this file to put Task Manager in your Applications folder.
# You do not need Xcode.

set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
APP_SRC="$DIR/TaskManager.app"
DEST="/Applications/TaskManager.app"

osascript <<'EOF' >/dev/null 2>&1 || true
tell application "Task Manager" to quit
EOF
osascript <<'EOF' >/dev/null 2>&1 || true
tell application "TaskManager" to quit
EOF
sleep 0.4
pkill -x TaskManager 2>/dev/null || true

if [[ ! -d "$APP_SRC" ]]; then
  osascript -e 'display dialog "TaskManager.app should be in the same folder as this installer.\n\nKeep both files together, then try again." buttons {"OK"} default button 1 with title "Task Manager" with icon stop'
  exit 1
fi

if [[ -d "$DEST" ]]; then
  rm -rf "$DEST"
fi

ditto "$APP_SRC" "$DEST"
xattr -cr "$DEST" 2>/dev/null || true
xattr -d com.apple.quarantine "$DEST" 2>/dev/null || true

/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST" >/dev/null 2>&1 || true

open "$DEST"

osascript <<'EOF'
display dialog "Task Manager is now in your Applications folder and should open on its own.

This is a beta project. It is not yet legally registered. Please do not share this file.

Developed by James Murphy.

If your Mac says the app cannot be opened:
1. Open System Settings
2. Privacy & Security
3. Scroll down and click Open Anyway" buttons {"OK"} default button 1 with title "Task Manager is installed"
EOF
exit 0
