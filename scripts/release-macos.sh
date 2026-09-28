#!/usr/bin/env bash
set -euo pipefail

[[ "$(uname -s)" == "Darwin" ]] || { echo "error: release requires macOS" >&2; exit 1; }
: "${CERT_NAME:?Set CERT_NAME to a Developer ID Application identity}"
: "${NOTARY_PROFILE:?Set NOTARY_PROFILE to a notarytool keychain profile}"

app_name="${APP_NAME:-Arcload}"
product_name="${PRODUCT_NAME:-Arcload}"
bundle_id="${BUNDLE_ID:-com.ypjcoding.arcload}"
version="${VERSION:-$(head -n 1 VERSION)}"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][A-Za-z0-9.-]+)?$ ]] || {
  echo "error: VERSION must begin with a semantic X.Y.Z version" >&2
  exit 64
}

dist_dir="${DIST_DIR:-dist}"
app="build/$app_name.app"
release_dmg="$dist_dir/$app_name-$version-macos.dmg"
dmg_root="$dist_dir/.dmg-root"

rm -rf build "$dist_dir"
mkdir -p "$dist_dir"
APP_NAME="$app_name" PRODUCT_NAME="$product_name" BUNDLE_ID="$bundle_id" \
  CONFIGURATION=release SIGN_IDENTITY="$CERT_NAME" VERSION="$version" \
  ./scripts/build-macos-app.sh

codesign --force --options runtime --timestamp --sign "$CERT_NAME" \
  --entitlements "Config/$app_name.entitlements" "$app"
codesign --verify --deep --strict --verbose=2 "$app"
./scripts/verify-macos-hardening.sh \
  "$app/Contents/MacOS/$app_name" "build/Symbols/$app_name.app.dSYM"

rm -rf "$dmg_root"
mkdir -p "$dmg_root"
ditto "$app" "$dmg_root/$app_name.app"
ln -s /Applications "$dmg_root/Applications"

hdiutil create \
  -volname "$app_name" \
  -srcfolder "$dmg_root" \
  -ov \
  -format UDZO \
  "$release_dmg"

codesign --force --timestamp --sign "$CERT_NAME" "$release_dmg"
xcrun notarytool submit "$release_dmg" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait

xcrun stapler staple "$release_dmg"
xcrun stapler validate "$release_dmg"
spctl --assess --type open --context context:primary-signature --verbose=2 "$release_dmg"

(
  cd "$dist_dir"
  dmg_name="$(basename "$release_dmg")"
  shasum -a 256 "$dmg_name" > "$dmg_name.sha256"
  shasum -a 256 -c "$dmg_name.sha256"
)

rm -rf "$dmg_root"
echo "Created $release_dmg and $release_dmg.sha256"
