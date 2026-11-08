#!/bin/zsh
set -euo pipefail

cd "${0:A:h}/.."
swift build -c release

app="build/TeX Messages.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp .build/release/TeXMessages "$app/Contents/MacOS/TeXMessages"
cp Resources/mathjax.js "$app/Contents/Resources/mathjax.js"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
cp Resources/Info.plist "$app/Contents/Info.plist"

local_identity=$(security find-certificate -c "LaTeXMessages Local Signing" -Z 2>/dev/null | awk '/SHA-1/ {print $NF}' | head -1 || true)
codesign --force --deep --sign "${SIGN_IDENTITY:-${local_identity:--}}" "$app"
echo "$PWD/$app"
