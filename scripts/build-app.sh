#!/bin/bash
# Builds Halo.app into ./build.
#   scripts/build-app.sh            → debug, this Mac's architecture
#   scripts/build-app.sh release    → optimized universal (Apple silicon + Intel)
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-debug}"
VERSION="${HALO_VERSION:-1.0.0}"
BUILD_NUMBER="${HALO_BUILD:-1}"
SIGN_IDENTITY="${HALO_SIGN_IDENTITY:--}"   # "-" = ad-hoc

if [[ "$CONFIG" == "release" ]]; then
  # One architecture at a time (the multi-arch path trips over a dependency's
  # build plugin), then merge into a universal binary.
  swift build -c release --arch arm64
  swift build -c release --arch x86_64
  ARM_DIR="$(swift build -c release --arch arm64 --show-bin-path)"
  X86_DIR="$(swift build -c release --arch x86_64 --show-bin-path)"
  BIN_DIR="$ARM_DIR"
  UNIVERSAL="$(mktemp -d)/Halo"
  lipo -create "$ARM_DIR/Halo" "$X86_DIR/Halo" -output "$UNIVERSAL"
else
  swift build -c "$CONFIG"
  BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"
  UNIVERSAL="$BIN_DIR/Halo"
fi

APP="build/${HALO_APP_NAME:-Halo}.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$UNIVERSAL" "$APP/Contents/MacOS/Halo"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp -R Resources/Icons "$APP/Contents/Resources/Icons"
cp -R Resources/FillCorpus "$APP/Contents/Resources/FillCorpus"
cp -R Resources/Fixes "$APP/Contents/Resources/Fixes"
cp -R Resources/Brand "$APP/Contents/Resources/Brand"
# Smart Fill runtime (llama.cpp, MIT): the local model server and its libraries.
if [[ -d Vendor/llama ]]; then
  mkdir -p "$APP/Contents/Helpers"
  cp -R Vendor/llama "$APP/Contents/Helpers/llama"
fi
for bundle in "$BIN_DIR"/*.bundle; do
  [[ -e "$bundle" ]] && cp -R "$bundle" "$APP/Contents/Resources/"
done

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleExecutable</key><string>Halo</string>
  <key>CFBundleIdentifier</key><string>${HALO_BUNDLE_ID:-dev.halo.editor}</string>
  <key>CFBundleName</key><string>Halo</string>
  <key>CFBundleDisplayName</key><string>Halo</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSSupportsAutomaticTermination</key><false/>
  <key>NSHumanReadableCopyright</key><string>Halo — a calm place to write code.</string>
  <key>NSDesktopFolderUsageDescription</key><string>Halo needs access to open and edit projects stored on your Desktop.</string>
  <key>NSDocumentsFolderUsageDescription</key><string>Halo needs access to open and edit projects stored in Documents.</string>
  <key>NSDownloadsFolderUsageDescription</key><string>Halo needs access to open and edit files in Downloads.</string>
  <key>NSRemovableVolumesUsageDescription</key><string>Halo needs access to open projects on external drives.</string>
  <key>NSNetworkVolumesUsageDescription</key><string>Halo needs access to open projects on network volumes.</string>
  <key>NSAppleEventsUsageDescription</key><string>Commands you run in Halo’s terminal may control other apps.</string>
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeName</key><string>Folder</string>
      <key>CFBundleTypeRole</key><string>Editor</string>
      <key>LSHandlerRank</key><string>Alternate</string>
      <key>LSItemContentTypes</key><array><string>public.folder</string></array>
    </dict>
    <dict>
      <key>CFBundleTypeName</key><string>Source Code</string>
      <key>CFBundleTypeRole</key><string>Editor</string>
      <key>LSHandlerRank</key><string>Alternate</string>
      <key>LSItemContentTypes</key>
      <array>
        <string>public.source-code</string>
        <string>public.script</string>
        <string>public.plain-text</string>
        <string>public.json</string>
        <string>public.yaml</string>
        <string>public.xml</string>
        <string>public.html</string>
        <string>net.daringfireball.markdown</string>
        <string>public.data</string>
      </array>
    </dict>
  </array>
</dict>
</plist>
PLIST

# Sign nested code first (helpers aren't reached by --deep), then the app.
if [[ -d "$APP/Contents/Helpers/llama" ]]; then
  find "$APP/Contents/Helpers/llama" -type f \( -name "*.dylib" -o -name "llama-server" \) -exec codesign --force --sign "$SIGN_IDENTITY" {} \; >/dev/null
fi
codesign --force --deep --sign "$SIGN_IDENTITY" "$APP" >/dev/null
echo "Built $APP ($CONFIG, signed with: $SIGN_IDENTITY)"
