#!/bin/zsh
# Builds Curated for Android and installs it on the phone connected over USB (USB debugging on).
# Pass --debug for a quicker, unoptimized build.
set -euo pipefail
cd "$(dirname "$0")"
export JAVA_HOME="${JAVA_HOME:-/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home}"

if [[ "${1:-}" == "--debug" ]]; then
    ./gradlew assembleDebug -q
    APK=app/build/outputs/apk/debug/app-debug.apk
else
    ./gradlew assembleRelease -q
    APK=app/build/outputs/apk/release/app-release.apk
fi
echo "Built $APK ($(du -h "$APK" | cut -f1))"

adb install -r "$APK"
# Lets the phone reach the Mac's sync server over the cable.
adb reverse tcp:8765 tcp:8765
echo "Installed. USB sync is ready while the phone stays plugged in."
