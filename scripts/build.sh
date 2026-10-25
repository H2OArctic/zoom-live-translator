#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
signing_identity="${SIGNING_IDENTITY:-}"
if [[ -z "$signing_identity" ]]; then
    signing_identity="$(security find-identity -v -p codesigning | awk '/"Apple Development:/ {print $2; exit}')"
fi
if [[ -z "$signing_identity" || "$signing_identity" == "-" ]]; then
    printf '%s\n' 'Нужен доступный сертификат Apple Development с приватным ключом. Добавь аккаунт в Xcode или укажи SIGNING_IDENTITY.' >&2
    exit 1
fi
export CLANG_MODULE_CACHE_PATH="$project_dir/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$project_dir/.build/swift-cache"
swift build -c release --disable-sandbox --cache-path .build/cache --config-path .build/config --security-path .build/security
app_dir="$project_dir/dist/Zoom Live Translator.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp .build/release/ZoomLiveTranslator "$app_dir/Contents/MacOS/ZoomLiveTranslator"
cp Resources/Info.plist "$app_dir/Contents/Info.plist"
cp Resources/AppIcon.icns "$app_dir/Contents/Resources/AppIcon.icns"
ditto .build/release/FluidAudio_FluidAudio.bundle "$app_dir/Contents/Resources/FluidAudio_FluidAudio.bundle"
mkdir -p "$app_dir/Contents/Resources/Licenses"
install -m 644 Resources/Licenses/*.txt "$app_dir/Contents/Resources/Licenses/"
ditto .build/checkouts/FluidAudio/ThirdPartyLicenses "$app_dir/Contents/Resources/Licenses/FluidAudio-ThirdParty"
codesign --force --sign "$signing_identity" --options runtime --timestamp=none --entitlements Resources/Translator.entitlements "$app_dir"
codesign --verify --deep --strict --verbose=2 "$app_dir"
printf '%s\n' "$app_dir"
