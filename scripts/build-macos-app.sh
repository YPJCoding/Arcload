#!/usr/bin/env bash
set -euo pipefail

[[ "$(uname -s)" == "Darwin" ]] || { echo "error: macOS app bundling requires macOS" >&2; exit 1; }

configuration="${CONFIGURATION:-debug}"
app_name="${APP_NAME:-Arcload}"
product_name="${PRODUCT_NAME:-Arcload}"
bundle_id="${BUNDLE_ID:-com.ypjcoding.arcload}"
version="${VERSION:-$(head -n 1 VERSION)}"
build_number="${BUILD_NUMBER:-$(date -u +%Y%m%d%H%M)}"
sign_identity="${SIGN_IDENTITY:--}"
output_dir="${OUTPUT_DIR:-build}"
release_swift_flags="${RELEASE_SWIFT_FLAGS:--Xswiftc -cross-module-optimization}"
release_linker_flags="${RELEASE_LINKER_FLAGS:--Xlinker -dead_strip}"
app="$output_dir/$app_name.app"
info_plist="${INFO_PLIST:-Resources/Info.plist}"
entitlements="${ENTITLEMENTS:-Config/$app_name.entitlements}"
icon="${APP_ICON:-build/AppIcon.icns}"

[[ "$configuration" == "debug" || "$configuration" == "release" ]] || {
  echo "error: CONFIGURATION must be debug or release" >&2
  exit 64
}
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][A-Za-z0-9.-]+)?$ ]] || {
  echo "error: VERSION must begin with a semantic X.Y.Z version" >&2
  exit 64
}
[[ -f "$info_plist" ]] || { echo "error: missing $info_plist" >&2; exit 1; }
[[ -f "$entitlements" ]] || { echo "error: missing $entitlements" >&2; exit 1; }

swift_build_arguments=(build --arch arm64 --product "$product_name" --configuration "$configuration")
if [[ "$configuration" == "release" ]]; then
  read -r -a release_build_arguments <<< "$release_swift_flags $release_linker_flags"
  swift_build_arguments+=("${release_build_arguments[@]}")
fi
swift "${swift_build_arguments[@]}"
bin_path="$(swift build --arch arm64 --product "$product_name" --configuration "$configuration" --show-bin-path)"
executable="$bin_path/$product_name"
[[ -x "$executable" ]] || { echo "error: executable not found at $executable" >&2; exit 1; }

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$executable" "$app/Contents/MacOS/$app_name"
packaged_executable="$app/Contents/MacOS/$app_name"
architectures="$(lipo -archs "$packaged_executable")"
[[ "$architectures" == "arm64" ]] || {
  echo "error: expected an arm64-only executable, found: $architectures" >&2
  exit 1
}
sed \
  -e "s|<string>Arcload</string>|<string>$app_name</string>|g" \
  -e "s|<string>com.ypjcoding.arcload</string>|<string>$bundle_id</string>|g" \
  -e "s|__SHORT_VERSION__|$version|g" \
  -e "s|__BUILD_VERSION__|$build_number|g" \
  "$info_plist" > "$app/Contents/Info.plist"
printf 'APPL????' > "$app/Contents/PkgInfo"

for bundle in "$bin_path"/*.bundle; do
  [[ -e "$bundle" ]] || continue
  cp -R "$bundle" "$app/Contents/Resources/"
done
if [[ -f "$icon" ]]; then
  cp "$icon" "$app/Contents/Resources/AppIcon.icns"
fi
[[ -x Resources/aria2-next ]] || { echo "error: missing pinned aria2-next engine" >&2; exit 1; }
engine_checksum="$(plutil -extract sha256 raw Resources/aria2-next-release.json)"
[[ "$(shasum -a 256 Resources/aria2-next | awk '{print $1}')" == "$engine_checksum" ]] || {
  echo "error: aria2-next checksum does not match pinned release" >&2
  exit 1
}
[[ "$(lipo -archs Resources/aria2-next)" == "arm64" ]] || {
  echo "error: aria2-next must be arm64-only" >&2
  exit 1
}
cp Resources/aria2-next "$app/Contents/MacOS/aria2-next"
chmod +x "$app/Contents/MacOS/aria2-next"
codesign --force --sign "$sign_identity" "$app/Contents/MacOS/aria2-next"
cp Resources/aria2-next-COPYING Resources/aria2-next-release.json "$app/Contents/Resources/"
cp NOTICE.md "$app/Contents/Resources/ThirdPartyNotices.md"

if [[ "$configuration" == "release" ]]; then
  ./scripts/harden-macos-binary.sh \
    "$packaged_executable" "$output_dir/Symbols/$app_name.app.dSYM"
fi

codesign --force --sign "$sign_identity" --entitlements "$entitlements" "$app"
codesign --verify --strict --verbose=2 "$app"
if [[ "$configuration" == "release" ]]; then
  ./scripts/verify-macos-hardening.sh \
    "$packaged_executable" "$output_dir/Symbols/$app_name.app.dSYM"
fi
plutil -lint "$app/Contents/Info.plist" >/dev/null
printf 'Created %s\n' "$app"
