# Curated: dev commands

Three separate git repos live under `~/codes/curated`:

| App | Folder | Notes |
|---|---|---|
| Mac | `Curated/` | SwiftPM, no Xcode project |
| Android | `CuratedAndroid/` | Kotlin / Compose / Media3, package `local.curated.phone` |
| iOS | `CuratediOS/` | SwiftUI + XcodeGen, simulator only for now |

The Mac, Android and iOS version numbers move together (currently **1.6 / build 7**).

## Commit

```sh
cd ~/codes/curated/Curated          # or CuratedAndroid / CuratediOS
git status --short                 # check nothing unrelated is sneaking in
git add <files>
git commit -m "Short summary"
```

Every commit also appends an entry to that repo's `CHANGELOG.md` (oldest first, newest at the bottom):
`## YYYY-MM-DD · Short title` with user-facing bullets, or `## X.Y · YYYY-MM-DD` for a release.

### Release "as X.Y"

1. Bump the version in both apps:
   - Mac: `VERSION` and `BUILD_NUMBER` at the top of `Curated/build.sh`
   - Android: `versionName` and `versionCode` in `CuratedAndroid/app/build.gradle.kts`
2. Commit and tag each repo:

```sh
cd ~/codes/curated/Curated        && git commit -am "Curated X.Y"             && git tag vX.Y
cd ~/codes/curated/CuratedAndroid && git commit -am "Curated for Android X.Y" && git tag vX.Y
```

## Install the Mac app

Quit Curated first (the install replaces `~/Applications/Curated.app`):

```sh
pgrep -x Curated && echo "Curated is running, quit it first"
cd ~/codes/curated/Curated && ./build.sh --install
open ~/Applications/Curated.app
```

`./build.sh` without `--install` only builds `./Curated.app`. The Liquid Glass icon needs Xcode's `actool`, which the script finds automatically.

## Install on the Android phone (over USB)

```sh
cd ~/codes/curated/CuratedAndroid
./install.sh          # release build, installs, sets up USB sync (adb reverse 8765)
./install.sh --debug  # quicker unoptimized build
```

- Keep USB debugging on and the phone unlocked. Only one device should be connected: if the emulator is running too, stop it or use `adb -s <serial> ...`.
- Your synced videos and watch history stay on the phone across installs.
- Just build without installing: `JAVA_HOME=/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home ./gradlew assembleDebug`
- USB sync: the Mac app runs `adb reverse tcp:8765 tcp:8765` itself every few seconds while sync is on (toggle "USB Sync" in the Phone Sync popover; on at every launch), so it recovers on its own after the cable is reconnected.

## iOS (simulator)

```sh
cd ~/codes/curated/CuratediOS
xcodegen generate
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Curated.xcodeproj -scheme Curated \
  -destination 'platform=iOS Simulator,name=<simulator name>' build
```

No simulators are installed yet: add an iOS runtime through Xcode → Settings → Components (`xcodebuild -downloadPlatform` hangs), then list device names with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun simctl list devices available`.

## Testing without touching real data

Never test against the real library or port 8765: the everyday Curated uses both.

```sh
# Mac: a debug build with its own data folder, sync port and a fixed pairing code
cd ~/codes/curated/Curated && swift build
CURATED_DATA_DIR=/tmp/curated-test CURATED_SYNC_PORT=18765 CURATED_TEST_PAIRING_CODE=123456 .build/debug/Curated

# Android emulator, pointed at the test Mac app
~/Library/Android/sdk/emulator/emulator -avd Pixel_4_XL -read-only -no-window &
adb -e reverse tcp:8765 tcp:18765
adb -e install -r CuratedAndroid/app/build/outputs/apk/debug/app-debug.apk
```

Use `adb -e` for the emulator so nothing lands on a real phone by accident. A test copy on its own port sets up USB sync only on emulators (or `ANDROID_SERIAL` if set), never a real phone; it needs `"syncEnabled": true` in its `config.json`. The test Mac app auto-plays Automix, so use silent test videos.

## Downloads and logs

| What | Where / how |
|---|---|
| Videos | `~/Movies/Curated/<username>/` (YouTube: `youtube@<handle>/`) |
| Config, played list | `~/Library/Application Support/Curated/` |
| Overnight download log | `tail -f ~/Library/Application\ Support/Curated/logs/scheduled.log` |
| Run the overnight download now | `launchctl kickstart gui/$(id -u)/local.curated.download` |
| Update the downloader | `brew upgrade yt-dlp` (do this when TikTok downloads start failing) |
| Android logs | `adb logcat --pid=$(adb shell pidof local.curated.phone)` |
