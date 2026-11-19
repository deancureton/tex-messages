#!/bin/zsh
set -euo pipefail

cd "${0:A:h}/.."
identity=$(security find-identity -v -p codesigning | awk -F'"' '/Developer ID Application/ {print $2; exit}')
[[ -n $identity ]] || { echo "no Developer ID Application certificate in the keychain" >&2; exit 1; }

SIGN_IDENTITY=$identity scripts/build.sh --release
app="build/TeX Messages.app"
version=$(/usr/bin/plutil -extract CFBundleShortVersionString raw Resources/Info.plist)
zip="build/TeXMessages-$version.zip"

ditto -c -k --keepParent "$app" "$zip"
result=$(xcrun notarytool submit "$zip" --keychain-profile tex-messages --wait --output-format json)
if [[ $(/usr/bin/plutil -extract status raw - <<< "$result") != Accepted ]]; then
  echo "$result" >&2
  xcrun notarytool log "$(/usr/bin/plutil -extract id raw - <<< "$result")" --keychain-profile tex-messages >&2
  exit 1
fi

xcrun stapler staple "$app"
spctl --assess --type execute --verbose "$app"
rm "$zip"
ditto -c -k --keepParent "$app" "$zip"
shasum -a 256 "$zip"
