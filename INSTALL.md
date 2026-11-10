# Installing Curated

This guide assumes you've never built an app before. You need a Mac for all three apps: the Mac app does the downloading, and the iPhone and Android apps are built on the Mac.

Commands go in the **Terminal** app (Applications → Utilities → Terminal). Paste each line and press Return.

---

## Part 1: Set up your Mac

### 1. Install Xcode

Xcode is Apple's free toolkit for building apps. Curated needs the full Xcode, not just the command line tools.

1. Open the **App Store**, search for **Xcode** and click **Get**. It's large (several GB), so give it a while.
2. Open Xcode once. Agree to the license and let it install its extra components.
3. In Xcode, open **Settings → Components** (called **Platforms** in some versions) and install the **iOS** platform. You only need this for the iPhone app.

### 2. Install Homebrew, yt-dlp and ffmpeg

[Homebrew](https://brew.sh) installs command line tools. Curated uses **yt-dlp** to download videos and **ffmpeg** to process them.

1. Install Homebrew by pasting the command from [brew.sh](https://brew.sh) into Terminal, and follow what it prints at the end (it may ask you to run two more lines).
2. Then run:

   ```sh
   brew install yt-dlp ffmpeg git
   ```

TikTok and YouTube change often. If downloads start failing, update yt-dlp first:

```sh
brew upgrade yt-dlp
```

### 3. Get the code

```sh
cd ~
git clone https://github.com/base0x02/curated.git
cd curated
```

This puts everything in a `curated` folder in your home folder.

---

## Part 2: The Mac app

```sh
cd ~/curated/Curated
./build.sh --install
open ~/Applications/Curated.app
```

`./build.sh --install` builds the app and copies it to the **Applications** folder in your home folder. The first build takes a few minutes. After that you can open Curated from Finder or Spotlight like any other app.

- To update later: `cd ~/curated && git pull`, quit Curated, then run `./build.sh --install` again in the `Curated` folder.
- If the build complains about a missing macro plugin or `actool`, Xcode isn't installed or hasn't been opened yet. Go back to Part 1, step 1.
- If TikTok or YouTube downloads ask you to sign in, open **Settings → Downloads → Sign-In** in Curated and pick the browser you're signed in with. For Safari, also give Curated **Full Disk Access** in **System Settings → Privacy & Security**.

See the [README](README.md) for how to add creators and sync.

---

## Part 3: iPhone and iPad

You install the app on your own device straight from Xcode. A free Apple account works. With a free account the app stops opening after **7 days**, and you just run it from Xcode again to renew it. A paid Apple Developer account ($99/year) makes it last a year.

### 1. Sign in to Xcode

Open Xcode → **Settings → Accounts**, click **+**, choose **Apple ID** and sign in.

### 2. Open the project

```sh
open ~/curated/CuratediOS/Curated.xcodeproj
```

### 3. Set up signing

1. In the left sidebar, click the blue **Curated** project at the top, then the **Curated** target under **Targets**.
2. Open the **Signing & Capabilities** tab.
3. Make sure **Automatically manage signing** is checked, and pick your name under **Team**.
4. Change **Bundle Identifier** from `local.curated.ios` to something unique to you, like `com.yourname.curated`. Apple won't let two people register the same one.

If you'll be regenerating the project with [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`, then `xcodegen generate` in the `CuratediOS` folder), put your team ID in `DEVELOPMENT_TEAM` and your bundle identifier in `project.yml` instead, or they'll be reset. You don't need XcodeGen just to install the app.

### 4. Get your iPhone ready

1. Connect the iPhone to the Mac with a cable and unlock it. Tap **Trust** if it asks.
2. On the iPhone, turn on **Developer Mode**: **Settings → Privacy & Security → Developer Mode**. The iPhone restarts, and you confirm after it does. (If you don't see the option, run the app once from Xcode first and it will appear.)

### 5. Run it

1. At the top of the Xcode window, click the device menu and pick your iPhone.
2. Press **⌘R** (or the ▶ button). Xcode builds the app and installs it.
3. The first time, the iPhone may refuse to open it because the developer isn't trusted. Go to **Settings → General → VPN & Device Management**, tap your Apple account and tap **Trust**. Then open Curated.

When it asks to find devices on your local network, tap **Allow**. That's how it finds your Mac.

To try it without a device, pick an iPhone **simulator** from the device menu instead. The simulator can sync with the Mac app too.

---

## Part 4: Android

There are two ways to do this. Android Studio is easier if you've never used the command line.

### Get the phone ready (both ways)

1. On the phone, open **Settings → About phone** and tap **Build number** seven times. You'll see "You are now a developer".
2. Go to **Settings → System → Developer options** and turn on **USB debugging**.
3. Connect the phone to the Mac with a cable, unlock it, and tap **Allow** when it asks to allow USB debugging from this computer.

The phone needs Android 10 or later.

### Option A: Android Studio (easiest)

1. Download [Android Studio](https://developer.android.com/studio), drag it to Applications and open it. Accept the defaults in the setup wizard. It downloads the Android SDK for you.
2. Choose **Open** and pick the `curated/CuratedAndroid` folder.
3. Wait for the "Gradle sync" bar at the bottom to finish. The first time, this downloads a lot and can take several minutes.
4. Pick your phone in the device menu at the top and click the green **Run ▶** button.

### Option B: Command line

1. Install Java and the Android tools:

   ```sh
   brew install openjdk@21
   brew install --cask android-platform-tools
   ```

   You also need the Android SDK. The simplest way to get it is to install Android Studio once (Option A, step 1), which puts it in `~/Library/Android/sdk`. Then tell the build where it is:

   ```sh
   echo "sdk.dir=$HOME/Library/Android/sdk" > ~/curated/CuratedAndroid/local.properties
   ```

2. Build and install:

   ```sh
   cd ~/curated/CuratedAndroid
   ./install.sh
   ```

   That builds the app, installs it on the connected phone and sets up syncing over the USB cable. `./install.sh --debug` builds faster but plays less smoothly.

### Installing on a phone without a cable

You can also build the app file and copy it over:

```sh
cd ~/curated/CuratedAndroid
JAVA_HOME=/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home ./gradlew assembleRelease
```

This makes `app/build/outputs/apk/release/app-release.apk`. Send it to the phone (by email, Google Drive or anything else), open it there, and allow installing from that source when Android asks.

---

## Pairing a phone

Once the apps are installed, follow **Sync to your phone** in the [README](README.md). In short: turn on **Settings → Phone → Phone sync** on the Mac, choose **Pair a Phone…** from the sync button in the sidebar, then enter the code in Curated on the phone. The Mac and phone need to be on the same Wi-Fi, or an Android phone can be connected by USB.

If the phone can't find the Mac:

- Check both are on the same Wi-Fi network (not a guest network).
- On the Mac, allow Curated through the firewall if macOS asks.
- On iPhone, check **Settings → Privacy & Security → Local Network** is on for Curated.
- Type the Mac's address shown in the pairing window by hand.
