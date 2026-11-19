#!/bin/zsh
set -euo pipefail

cd "${0:A:h}/.."
app="build/TeX Messages.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"

if [[ ${1:-} == --release ]]; then
  slices=()
  for arch in arm64 x86_64; do
    args=(-c release --triple $arch-apple-macosx26.0)
    swift build $args
    cp "$(swift build $args --show-bin-path)/TeXMessages" "build/TeXMessages-$arch"
    slices+=("build/TeXMessages-$arch")
  done
  lipo -create $slices -output "$app/Contents/MacOS/TeXMessages"
  extra=(--timestamp)
else
  swift build -c release
  cp .build/release/TeXMessages "$app/Contents/MacOS/TeXMessages"
  extra=()
fi

cp Resources/mathjax.js "$app/Contents/Resources/mathjax.js"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
cp Resources/Info.plist "$app/Contents/Info.plist"

local_identity=$(security find-certificate -c "LaTeXMessages Local Signing" -Z 2>/dev/null | awk '/SHA-1/ {print $NF}' | head -1 || true)
codesign --force --options runtime --entitlements Resources/TeXMessages.entitlements $extra \
  --sign "${SIGN_IDENTITY:-${local_identity:--}}" "$app"
echo "$PWD/$app"
