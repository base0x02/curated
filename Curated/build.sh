#!/bin/zsh
# Builds Curated.app next to this script. Pass --install to also copy it to ~/Applications.
set -euo pipefail
cd "$(dirname "$0")"

VERSION="2.2"
BUILD_NUMBER="25"

# The Command Line Tools lack SwiftUI's macro plugin (@Entry, @Observable…) and actool, so when they're the active
# developer dir, build with a full Xcode instead: the newest non-beta one in /Applications, else a beta.
if [[ -z "${DEVELOPER_DIR:-}" && "$(xcode-select -p 2>/dev/null)" != *Xcode*.app/* ]]; then
    XCODE=$(/bin/ls -d /Applications/Xcode*.app 2>/dev/null | grep -v -i beta | sort -V | tail -1 || true)
    [[ -z "$XCODE" ]] && XCODE=$(/bin/ls -d /Applications/Xcode*.app 2>/dev/null | sort -V | tail -1 || true)
    if [[ -n "$XCODE" ]]; then
        export DEVELOPER_DIR="$XCODE/Contents/Developer"
        echo "Using $XCODE"
    fi
fi

swift build -c release
BIN="$(swift build -c release --show-bin-path)/Curated"

APP="Curated.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Curated"
# Logo artwork (and the long-video wordmark), the short/long marks, the Vine logo and the autoplay glyphs (vector SVGs, loaded at runtime).
for f in Resources/logo.svg Resources/logo-dark.svg Resources/wordmark-*.svg Resources/mark-*.svg Resources/vine.svg Resources/vine-glyph.svg Resources/autoplay-*.svg; do
    [[ -f "$f" ]] && cp "$f" "$APP/Contents/Resources/"
done

# App icon. Preferred: the Icon Composer file (Liquid Glass, light/dark/tinted variants), which needs
# Xcode's actool. Fallback: an .icns generated from the 1024x1024 PNG.
ICON_NAME="AppIcon"
ICON_KEYS="<key>CFBundleIconFile</key><string>AppIcon</string>"
ICON_SOURCE="Resources/CuratedAppIcon.icon"
# Use Xcode's actool even when the active developer dir is the Command Line Tools.
ACTOOL_ENV=()
if ! xcrun --find actool >/dev/null 2>&1 && [[ -d /Applications/Xcode.app ]]; then
    ACTOOL_ENV=(DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer)
fi
if [[ -d "$ICON_SOURCE" ]] && env "${ACTOOL_ENV[@]}" xcrun --find actool >/dev/null 2>&1; then
    ICON_NAME="$(basename "$ICON_SOURCE" .icon)"
    # Absolute paths: actool's icon export can resolve relative ones from somewhere else and fail.
    env "${ACTOOL_ENV[@]}" xcrun actool "$PWD/$ICON_SOURCE" \
        --compile "$PWD/$APP/Contents/Resources" \
        --platform macosx \
        --minimum-deployment-target 14.0 \
        --app-icon "$ICON_NAME" \
        --output-partial-info-plist "$PWD/.build/icon-partial.plist" >/dev/null
    ICON_KEYS="<key>CFBundleIconName</key><string>$ICON_NAME</string>
    <key>CFBundleIconFile</key><string>$ICON_NAME</string>"
    echo "App icon: $ICON_SOURCE (via actool)"
elif [[ -f Resources/AppIcon.png ]]; then
    [[ -d "$ICON_SOURCE" ]] && echo "App icon: Resources/AppIcon.png (install Xcode to use $ICON_SOURCE)"
    ICONSET=".build/AppIcon.iconset"
    rm -rf "$ICONSET" && mkdir -p "$ICONSET"
    for size in 16 32 128 256 512; do
        sips -z $size $size Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
        sips -z $((size * 2)) $((size * 2)) Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
    done
    iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Curated</string>
    <key>CFBundleDisplayName</key><string>Curated</string>
    <key>CFBundleIdentifier</key><string>local.curated.app</string>
    <key>CFBundleExecutable</key><string>Curated</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    $ICON_KEYS
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSLocalNetworkUsageDescription</key><string>Curated uses your local network to sync videos to your phone.</string>
    <key>NSBonjourServices</key><array><string>_curated._tcp</string></array>
</dict>
</plist>
PLIST

# Sign with the Apple Development certificate when there is one: privacy grants such as Full Disk Access (needed to
# read browser cookies) are tied to the signature, and an ad-hoc signature changes with every build, so macOS would
# silently stop honoring the grant after each reinstall.
IDENTITY=$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ { print $2; exit }')
codesign --force --sign "${IDENTITY:--}" "$APP"
echo "Built $PWD/$APP (version $VERSION)"

if [[ "${1:-}" == "--install" ]]; then
    mkdir -p ~/Applications
    rm -rf ~/Applications/Curated.app
    cp -R "$APP" ~/Applications/
    echo "Installed to ~/Applications/Curated.app"
fi
