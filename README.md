# Curated

Watch the creators you choose, not the ones the algorithm chooses for you.

Curated is a Mac app that downloads recent videos from a short list of TikTok and YouTube creators you pick, usually overnight, and plays them with no feed and no recommendations. When the videos run out, it stops and tells you to go enjoy some sunshine. Companion apps for iPhone/iPad and Android sync the videos from your Mac so you can watch them on your phone.

New to building apps? See **[INSTALL.md](INSTALL.md)** for step-by-step setup on macOS, iOS and Android.

## What's in this repo

| Folder | What it is |
|---|---|
| [`Curated/`](Curated) | The Mac app (SwiftUI, Swift Package Manager). It does all the downloading and runs the sync server for phones. |
| [`CuratediOS/`](CuratediOS) | The iPhone and iPad app (SwiftUI). It syncs from the Mac and plays the videos. |
| [`CuratedAndroid/`](CuratedAndroid) | The Android app (Kotlin, Jetpack Compose, Media3). It syncs from the Mac and plays the videos. |
| `icons and logos/` | Source artwork for the icons, wordmarks and holiday themes. |
| `divine/` | A stand-alone script for browsing the classic Vine archive (the app has its own built-in version). |

The phones never talk to TikTok or YouTube. Only the Mac downloads. Phones just copy what the Mac already has.

## Getting started

### 1. Add a creator

1. Open **Creators & Downloads** (the clipboard icon at the bottom of the sidebar).
2. Paste a creator's `@username` or profile link into the add field. Curated works out whether it's TikTok or YouTube from the link, or you can pick the platform yourself.
3. Choose how much to keep: the last few **days** of posts, or a set **number of videos**.
4. Click **Add Creator**.

A YouTube **playlist** link works too. It becomes a playlist instead of a creator.

You can also give each creator a minimum view count, and you can group creators into **categories** (like "News" or "Cooking"). Each category gets its own section in the sidebar and its own mixes.

### 2. Download

- Click **Download All Now** to download right away.
- Or let it run on its own: **Settings → Downloads → Schedule** sets a time (overnight by default). The download runs in the background even when the app is closed.
- If downloads fail with "log in" or "prove you're not a bot" messages, go to **Settings → Downloads → Sign-In** and pick the browser you're signed in with. Curated borrows that browser's sign-in.

### 3. Watch

Click any creator in the sidebar to watch their videos, newest first, or pick one of the mixes:

- **Automix**: plays everyone's unwatched videos, rotating from creator to creator, so no one person takes over.
- **Top 15**: your 15 most-viewed unwatched videos, then it stops. Each category also gets a **Top 5**.
- **Time Limit**: a fresh mix that lasts about as long as you choose (set the length in **Settings → Playback**), then it ends.

A video counts as watched as soon as it starts. Automix never repeats one.

### 4. Sync to your phone

1. Install the app on your phone (see [INSTALL.md](INSTALL.md)).
2. On the Mac, open **Settings → Phone** and turn on **Phone sync**.
3. Click the sync (antenna) button at the bottom of the sidebar and choose **Pair a Phone…**. The Mac shows a code.
4. Open Curated on the phone. It finds your Mac on the same Wi-Fi network (or you can type the address the Mac shows), then asks for the code.

After that, the phone syncs whenever you tap sync, and it can sync on its own. Watched videos, Watch Later and playback positions stay in step on every device. Android phones can also sync over a USB cable.

## Short videos and long videos

Curated keeps two separate libraries, and you switch between them with the **Short | Long** switch in the row of icons at the bottom of the sidebar (on phones, the mark in the top bar):

- **Short videos** are TikToks and YouTube **Shorts**. They're vertical and play one after another, like a feed you control.
- **Long videos** are regular YouTube videos and playlists. They get their own sidebar, their own mixes (Latest and Automix), their own Watch Later and their own resume points.

TikTok creators are always short. For a YouTube creator you choose **Shorts**, **long videos** or both on their row in Creators & Downloads. New long videos aren't downloaded automatically. Curated lists them so you can pick the ones you actually want, because long videos are big.

## Vine

Under **Settings → Downloads → Vine** you can turn on **Classic Vines**. Curated then keeps a small batch of unwatched classic Vines from [divine.video](https://divine.video)'s archive and mixes them into Automix at random. Every download tops the batch back up with more. The Vines also get their own card in the sidebar. You can choose how many to keep, or leave Vine out of Automix in the Playback settings.

## Requirements

- **Mac:** macOS 14 or later, Xcode, and `yt-dlp` and `ffmpeg` from Homebrew.
- **iPhone/iPad:** iOS 17 or later.
- **Android:** Android 10 or later.

Not affiliated with TikTok, YouTube, Vine or divine.video. Curated is for personal use: download only what you're allowed to watch.

## License

GPL-3.0. See [LICENSE](LICENSE). The Lilita One font is under the SIL Open Font License (see the license file next to it).
