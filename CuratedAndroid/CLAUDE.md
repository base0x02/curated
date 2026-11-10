# Curated for Android

The Android companion to the Mac app in `../Curated`. It plays the videos Curated downloaded on the Mac, with the same Automix, Top 15, category mixes, Time Limit, Watch Later and Bookmarks. **The phone never talks to TikTok or YouTube**: it only syncs with the Mac (Wi-Fi via Bonjour `_curated._tcp`, or USB via `adb reverse`) and plays local files.

Kotlin, Jetpack Compose (Material 3), Media3 ExoPlayer with a `MediaSessionService`, WorkManager. Package `local.curated.phone`, minSdk 29, targetSdk 36.

## Build and install

- Needs `JAVA_HOME=/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home` and the SDK in `~/Library/Android/sdk`.
- `./install.sh` (release) or `./install.sh --debug` builds, installs over USB and runs `adb reverse tcp:8765 tcp:8765`. That installs to whichever phone is connected over USB.
- To build without installing: `./gradlew assembleDebug`.
- For testing, use the emulator with `adb -e` only (so nothing lands on a real phone), pointed at a test Mac app on port 18765: `adb -e reverse tcp:8765 tcp:18765`. See `../dev-readme.md`.
- The version is `versionName`/`versionCode` in `app/build.gradle.kts`, kept in step with the Mac and iOS apps.

## Code map (`app/src/main/java/local/curated/phone/`)

| File | What it does |
|---|---|
| `CuratedApplication.kt` | Holds the single `AppState`; `SyncWorker` (background sync) |
| `AppState.kt` | All app state, the sync routine (`runSync`), merges, auto-sync scheduling, preferences |
| `Store.kt` | Every file the app reads or writes |
| `Model.kt` | `Manifest`/`Creator`/`Video`/`Category`, `PlayedMark`, `WatchLaterMark`, `Pairing`, plus their JSON (org.json) |
| `SyncClient.kt` | HTTP client for the Mac's sync API, resumable downloads, Bonjour discovery |
| `Queues.kt` | Automix / Top / Watch Later queue building (mirrors the Mac's `Library.swift`) |
| `Playback.kt`, `PlaybackService.kt` | ExoPlayer queue and media session (background audio, PiP controls) |
| `MainActivity.kt`, `HomeScreen.kt`, `PlayerScreen.kt`, `CreatorScreen.kt`, `SettingsScreen.kt`, `OnboardingScreen.kt`, `NowPlayingBar.kt`, `Components.kt` | Compose UI |
| `Themes.kt` | The aurora's palettes (`AuroraPalette`: Curated and five more, plus six holiday ones), `BackgroundStyle`, and `Holiday` (which holiday wordmark, by date), as on the Mac |
| `VideoZoom.kt` | Long videos' pinch zoom: fit to past fill, with a hold (and haptic tick) at the scale that fills the screen; one-finger pan while zoomed |

## How data is stored

Everything lives in the app's private internal storage (`context.filesDir`, i.e. `/data/data/local.curated.phone/files/`). There is no database. The Mac is the source of truth for which videos exist; the phone keeps a copy of the latest manifest plus the files it has downloaded. The library on screen is built from the manifest, filtered to videos whose file is fully downloaded (`AppState.rebuildLibraries`).

| Path (under `filesDir`) | Contents |
|---|---|
| `library/manifest.json` | The last `GET /manifest` response from the Mac, saved verbatim: macName, timeLimitMinutes, categories, creators, videos (id, creator, date, caption, duration, viewCount, size, fileExtension) |
| `library/videos/<video id>.<ext>` | Downloaded videos. While downloading they are `<id>.<ext>.part`, renamed when complete. A file counts as downloaded only if its size matches the manifest's `size` (`Store.isDownloaded`) |
| `library/avatars/<creator key>.jpg` | Avatars. The creator key is the TikTok username, `youtube@<handle>` or `youtube-playlist@<ID>`, the same as the Mac's folder name. A playlist's is its YouTube thumbnail |
| `library/posters/<video id>.jpg` | Long videos' thumbnails, from the Mac's `/poster/<id>`. Removed with their video |
| `played.json` | `{videoID: {"played": Bool, "at": ISO8601}}` |
| `watchlater.json` | `{videoID: {"saved": Bool, "at": ISO8601}}` |
| `bookmarks.json` | Same shape as `watchlater.json` |
| `positionmarks.json` | `{videoID: {"seconds"?: Double, "at": ISO8601}}`: where each long video was left off, so it resumes there on any device. Newest change wins; no `seconds` means cleared (watched or nearly finished). Swapped with the Mac (`POST /positions`, API 4) in full syncs, on opening the app, and a moment after pausing, switching videos or leaving, whatever the auto-sync setting. A paused player showing that video moves to a newer position. Deleted on unpair |
| `positions.json` | The pre-sync `{videoID: seconds}`. Only read when `positionmarks.json` doesn't exist yet (dated 1970 so any newer change wins); deleted on unpair |
| `nowplaying.json` | `NowPlayingMark` `{"id"?: String, "at": ISO8601}`: the long video last playing on any device, swapped with `/positions` (API 5). Newest wins; no `id` means closed or finished. With long videos showing and no long video playing, `Playback.loadSyncedVideo` loads it paused where it was left. Deleted on unpair |
| `playbackrules.json` | `PlaybackRules`: per form, the cards Automix leaves out (`automixOff`) and the cards that stay at 1x (`normalSpeed`), plus `resumeRewindSeconds`, `timeLimitMinutes` and `at`. Swapped with the Mac in `/positions` (API 8), newest wins. Deleted on unpair |
| `pairing.json` | `Pairing`: host, port, the bearer **token**, macName |

All JSON writes go through `Store.writeAtomically` (write `<name>.tmp`, then rename). The mark files are `@Synchronized` because `SyncWorker` and the UI can touch them at the same time.

**SharedPreferences** file `curated` (`Store.prefs`): `lastSyncMessage`, `lastSyncAt`, `autoSync`, `collapsedCards` (string set), `appearance`, `syncForms` (Short, Long or All: what a sync asks the Mac for) `autoplayLong` and `autoplayShort` (short videos go on to the next one when they end, or loop; on by default), `background` (Aurora or Holiday), `auroraPalette` and `holidayPalette` (each style's palette id), `holidayWordmarks`.

**FileProvider** (`${applicationId}.files`, `res/xml/file_paths.xml`) exposes `library/videos/` read-only, only for the Share action in the player.

The manifest doesn't set `android:allowBackup`, so Android's default auto-backup applies.

### Short and long videos

Like the Mac, the app has a short and a long Home (`AppState.form`, always short at launch), switched by the mark in the top bar. Every sync fetches the Mac's whole list (`/manifest?forms=short,long`; it's small) but only downloads one kind: Sync Now asks Short, Long or All each time, and automatic sync (and pull to refresh on iOS) uses the default saved in Settings (`syncForms`). Nothing is removed for being a kind that wasn't picked; only videos missing from the Mac's list leave the device. A Mac from before long videos ignores `forms` and sends short videos only. The manifest's videos carry `form: "long"`, a title, description and `hasPoster`; creators can be playlists with an `order`. `AppState.rebuildLibraries` makes short libraries (creators that aren't playlists, minus YouTube creators the Mac only sent long videos for) and long libraries (creators with long videos, then playlists, built from `order` because the Mac sends each video once). The long Home has Latest and Automix (playlists stay out of the mixes), its own Watch Later and Bookmarks, category cards with long-video creators, and a Playlists card last; a long creator or playlist opens a gallery. Long videos resume where they were left off, have a seek bar, and stop at the end with an Up Next card unless autoplay is on. They don't swipe to the next video like short ones; they pinch to zoom instead. Skipping a long video (`Playback.next()`, e.g. from the notification) saves its place and leaves it unwatched, unless it's in its last 20 seconds. Positions are saved from 2 seconds in, for watched videos too (a rewatch resumes), and opening the video that's already loaded carries on without reloading it.

### Settings and playback rules

Settings (`SettingsScreen.kt`) has four pages: Sync, Playback, Appearance and Storage, with the version at the bottom of Sync. It takes the whole window in every layout (`CuratedRoot` returns early for it). It's tabs in a narrow, upright window (a phone, a Fold's cover screen), and otherwise (at least 600dp wide, or wider than tall: a Fold's inner screen either way up, a phone on its side) the pages listed on the left with the chosen one on the right; the chosen page carries across a rotation. The Mac's download is only followed while the Sync page is on screen. Playback has Short videos and Long videos groups. `Playback.applySpeed` keeps a video at 1x while its card is in the rules' `normalSpeed` (`speedLocked`), leaving the chosen `speed` alone so it returns on the next video; a held 2x still works. Only the main Automix and its picker's starting cards use `automixOff`. Autoplay stays each device's own; the rules and time limit are shared.

### Hand-picked long videos

A long video picked on the Mac from a creator's older videos has `pickedAt` in the manifest (API 9). `AppState.handPickedFirst` puts the unwatched ones first in Latest, Automix and the creator's gallery, latest pick first; once watched they go back to their place by date. A playlist keeps its own order.

### Asking the Mac about creators (`CreatorRequests.kt`)

API 10. Add Creator on the Sync page draws the form the Mac describes (`GET /creators/form`), so it only offers what that Mac understands, and sends just the fields showing. The Mac checks them and answers with a message and errors by field, or `formChanged` to fetch the form again. Older Videos (a long creator's long-press menu and gallery) follows the Mac's listing as server-sent events, shows 40 at a time, and fetches thumbnails from the Mac only as they come on screen; the picks go to the Mac, which downloads them. `AppState.requestedVideoIDs` (saved) remembers them: the Mac's download is followed past Settings closing until they're fetched, again each time the app comes back, and any sync fetches them whichever kinds it's syncing, without the rest of the long library. Home's + opens the same Add Creator form when paired. A Mac without these routes answers 404, shown as a request to update it.

### Vines

Every sync asks for `/manifest?forms=short,long&vine=1`. While Vine is on on the Mac, that lists its Vines as short videos under made-up creators keyed `vine@<Vine user ID>` (with `"vine": true`), plus `vineCategories`, the categories whose Automix plays them. They download whenever short videos do (Short or All). `AppState.vineLibraries` holds the authors with a Vine on the device, kept out of `libraries` (no category card, no Top list). Home shows them in a Vine card (the V glyph, green avatar rings, a Vine Automix button), and `automixLibraries` adds all of them as one more creator to the main Automix and those categories' Automix. Turning Vine off on the Mac drops them from the manifest, so the next sync removes them.

### Sync and the data lifecycle (`AppState.runSync`)

1. Use USB if `adb reverse` answers. Otherwise find the Mac by Bonjour and use the first address from its `/info` that answers (wired first), saving it in `pairing`; if Bonjour finds nothing, use the saved address. Position swaps skip the lookup, starting from the saved address so they stay quick. `GET /manifest`.
2. `POST /played` with all local played/Watch Later/bookmark marks. The Mac merges them and returns the merged sets, which replace the local ones. For each video id, the change with the newest `at` wins, so un-watching and un-saving sync too. Never delete a mark to clear it; set it to false with a new date. Dates are whole-second ISO 8601 (the Mac parses no fractional seconds).
3. Save the new manifest, then **delete every file in `library/videos/` that isn't in it** (`Store.removeVideosExcept`). The Mac decides what the phone keeps.
4. Download new avatars (the rest are replaced behind the sync, about once a day), then missing videos newest first, six at a time. Downloads resume from `.part` files using HTTP Range.

Force Download: `manifest.lastDownloadAt` (API 6) is when the Mac last finished a download, shown in Settings beside **Update Mac**, which sends `POST /download` to start a total download on the Mac. While Settings is on screen the phone follows `GET /download/progress` (API 7): a ring on the right of that row fills, with who's downloading below it. The Mac closes the connection when the run ends, and leaving Settings or the app closes it from this end. A run that finished (a newer last download time than when it was seen running, saved as `macDownloadBaseline`; a stopped one keeps the old time) starts a sync of the kinds in `syncForms` (after any sync under way) and shows a checkmark (`macDownloadFinished`), which that sync leaves and the next successful one removes. Those two preferences survive closing the app and are cleared on unpair. A Mac without the route answers 404, shown as a request to update it.

Auto sync: a WorkManager periodic job (`SyncWorker`, hourly) that requires Wi-Fi (unmetered) and charging.

**Unpair wipes the phone**: pairing, all videos, avatars, the manifest and every mark (`AppState.unpair`). Videos and history survive app reinstalls (`adb install -r`), not uninstalls.

### Compatibility rules

- The payload format is defined by the Mac (`../Curated/Sources/Curated/PhoneSync.swift`). Parse with `opt*` and defaults so older and newer Macs both work, and keep this app's JSON identical to the iOS app's `Model.swift`.
- New local fields must be optional, so a downgrade (rolling back to an older `vX.Y` build) still reads the files.

## Conventions

- Every commit appends an entry to `CHANGELOG.md` (oldest first): `## YYYY-MM-DD · Short title`, or `## X.Y · YYYY-MM-DD` for a release.
- Keep feature parity with the iOS app (`../CuratediOS`); the two are deliberately parallel (`Store`, `Model`, `Queues`, `AppState`, `SyncClient` match file for file).
