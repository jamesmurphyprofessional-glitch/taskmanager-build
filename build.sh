#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"
xcodebuild -scheme TaskManager -configuration Release -arch arm64 \
  -derivedDataPath build \
  CODE_SIGN_IDENTITY="-" ONLY_ACTIVE_ARCH=YES
rm -rf dist/TaskManager.app
mkdir -p dist
cp -R build/Build/Products/Release/TaskManager.app dist/TaskManager.app
echo "Built dist/TaskManager.app"
