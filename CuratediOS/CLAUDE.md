# Curated for iOS

The iPhone/iPad companion to the Mac app in `../Curated`, a parallel of the Android app in `../CuratedAndroid`. It plays videos the Mac downloaded (Automix, Top 15, category mixes, Time Limit, Watch Later, Bookmarks) and **never talks to TikTok or YouTube**: it only syncs with the Mac over the local network (Bonjour `_curated._tcp`, port 8765).

SwiftUI, AVFoundation, iOS 17+, bundle id `local.curated.ios`. Layouts for iPhone, iPad (landscape mirrors the Mac window, in `WideLayout.swift`) and iPhone Duo.

## Build and test

- On a real iPhone (USB): `xcodebuild -project Curated.xcodeproj -scheme Curated -configuration Release -destination 'id=<device UDID>' -derivedDataPath <dir> DEVELOPMENT_TEAM=<your team ID> -allowProvisioningUpdates -allowProvisioningDeviceRegistration build`, then `xcrun devicectl device install app --device 00008140-001D790A013A801C <dir>/Build/Products/Release-iphoneos/Curated.app`. Building for the device itself (not `generic/platform=iOS`) is what gets it into the provisioning profile.
- The Xcode project is generated: edit `project.yml`, then run `xcodegen generate`. Don't hand-edit `Curated.xcodeproj`.
- Build with a full Xcode via `DEVELOPER_DIR` (the active developer dir is the Command Line Tools):
  `xcodebuild -project Curated.xcodeproj -scheme Curated -destination 'platform=iOS Simulator,name=<name>' build`
- Simulators: use "iPhone Duo (Curated test)" or "iPhone 16 (Curated test)" (iOS 27.0; a copy of the iPhone 16 simulator's library with no pairing, so it can't sync) with `-muteCurated`. The plain Duo, iPhone 16 and iPhone 18 Pro simulators may be paired with an everyday Mac and would sync with it.
- UI tests (`CuratedUITests/`) open straight into Automix, so short clips get marked watched quickly. `xcodebuild test` can hang after finishing: poll the log for `** TEST SUCCEEDED/FAILED` and stop it. Keep runs short, and ask before long ones.
- Debug-only launch hooks (`Sources/TestHooks.swift`): `-resetCurated` (unpair and wipe), `CURATED_TEST_PAIR=host:port:code` (pair with a test Mac and sync), `-muteCurated`, `-curatedHome` (start on Home), `-curatedSwitchLong` (switch to long videos 3 seconds after launch), `-curatedSettings` (start in Settings), `-curatedLandscape` (turn the window sideways; the headless simulator can't be turned), `-curatedTestReopen` (when already paired: sync, play the first long video, pause past the fresh-item limit, resume, and log the result to `Documents/diagnostics.log`; seed `pairing.json` in the container to pair), `-curatedSettingsPlayback` (with `-curatedSettings`, opens on its Playback page), `-curatedTestSpeed` (after the first sync, plays Automix at 2× and logs each video's real rate to `Documents/diagnostics.log`) and `-curatedAppearanceFirst` (with `-curatedSettings`, opens on its Appearance page) and `-curatedTestArtwork` (logs the lock screen's picture to `Documents/diagnostics.log`). `xcrun simctl spawn <device> defaults write local.curated.ios <key> <value>` sets preferences before a launch.
- The version is `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` in `project.yml`, kept in step with the Mac and Android apps. Work happens on `main` (the old `iphone-duo` branch was merged into it on 2026-11-03).

## Code map (`Curated/Sources/`)

| File | What it does |
|---|---|
| `CuratedApp.swift` | App entry; registers the background sync task |
| `AppState.swift` | All app state, the sync routine (`runSync`), merges, preferences, background sync scheduling |
| `Store.swift` | Every file the app reads or writes |
| `Model.swift` | `Manifest`/`Creator`/`Video`/`Category`, `PlayedMark`, `WatchLaterMark`, `Pairing`, `PlaybackMode`, shared ISO 8601 coders |
| `SyncClient.swift` | HTTP client for the Mac's sync API, resumable downloads, Bonjour discovery |
| `Queues.swift` | Automix / Top / Watch Later queue building (mirrors the Mac's `Library.swift`) |
| `Playback.swift`, `PlayerScreen.swift` | AVPlayer queue and the player UI |
| `HomeView.swift`, `WideLayout.swift`, `SidewaysLayout.swift`, `Onboarding.swift`, `SettingsView.swift`, `Components.swift` | UI |
| `Themes.swift` | The aurora's palettes (`AuroraPalette`: Curated and five more, plus six holiday ones), `BackgroundStyle`, and `Holiday` (which holiday wordmark, by date), as on the Mac and Android. The wordmarks are `Wordmark<Holiday>` in the asset catalog |

## How data is stored

Everything lives in the app container's **Application Support** folder, `Library/Application Support/Curated/` (`Store.root`). There is no database. The Mac is the source of truth for which videos exist; the phone keeps a copy of the latest manifest plus the files it has downloaded. The library on screen is built from the manifest, filtered to videos whose file is fully downloaded (`AppState.rebuildLibraries`).

| Path (under `Curated/`) | Contents |
|---|---|
| `library/` | Marked **excluded from iCloud backup** (`isExcludedFromBackup`) |
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
| `playbackrules.json` | `PlaybackRules`: per form, the cards Automix leaves out (`automixOff`) and the cards that stay at 1× (`normalSpeed`), plus `resumeRewindSeconds`, `timeLimitMinutes` and `at`. Swapped with the Mac in `/positions` (API 8), newest wins. Deleted on unpair |
| `pairing.json` | `Pairing`: host, port, the bearer **token**, macName (a plain file, not the Keychain) |

The mark files and `pairing.json` are outside `library/`, so they are included in device backups. All writes are `.atomic`.

**UserDefaults** (standard): `appearance`, `autoSync`, `collapsedCards`, `lastSyncMessage`, `lastSyncAt`, `syncForms` (short, long or all: what a sync asks the Mac for) `autoplayLong` and `autoplayShort` (short videos go on to the next one when they end, or loop; on by default), `background` (aurora or holiday), `auroraPalette` and `holidayPalette` (each style's palette id), `holidayWordmarks`, `lowPower` (a lighter aurora, pre-blurred blobs at half the frame rate, and no `VideoBackdrop` behind short videos); `@AppStorage("queueHidden")` for the iPad layout.

### Short and long videos

Like the Mac, the app has a short and a long Home (`AppState.form`, always short at launch), switched by the mark in the top bar. Every sync fetches the Mac's whole list (`/manifest?forms=short,long`; it's small) but only downloads one kind: Sync Now asks Short, Long or All each time, and automatic sync (and pull to refresh on iOS) uses the default saved in Settings (`syncForms`). Nothing is removed for being a kind that wasn't picked; only videos missing from the Mac's list leave the device. A Mac from before long videos ignores `forms` and sends short videos only. The manifest's videos carry `form: "long"`, a title, description and `hasPoster`; creators can be playlists with an `order`. `AppState.rebuildLibraries` makes short libraries (creators that aren't playlists, minus YouTube creators the Mac only sent long videos for) and long libraries (creators with long videos, then playlists, built from `order` because the Mac sends each video once). The long Home has Latest and Automix (playlists stay out of the mixes), its own Watch Later and Bookmarks, category cards with long-video creators, and a Playlists card last; a long creator or playlist opens a gallery. Long videos play in Apple's stock player (`StockPlayerView`, an AVPlayerViewController on Playback's shared AVPlayer): its controls skip 10 seconds, scrub, change speed, and go full screen or picture in picture. They resume where they were left off and stop at the end with an Up Next card unless autoplay is on. The app turns freely (`OrientationLock`, asked by `AppDelegate`); the stock player going full screen turns an upright iPhone sideways and back. An iPhone on its side (compact height) gets `SidewaysLayout`, like the Android app on a Fold's cover screen: the phone's screens on the left with Home's mixes as bar icons and a collapsible tray under them (picture in picture, the queue, short videos' progress and main controls, the video's details), and the player on the right with its buttons down the edge. `Router.open` sends players to that pane (`sidePlayer`) instead of the path; turning upright puts the playing one back on the path. Short videos widen the left pane by 35%. A long video's full screen button there shows only the video (`LongFullscreen`); turning upright, or the exit button while paused, goes back. The Duo's inner display keeps its two-pane landscape layout. In portrait, its long mode uses the phone's screens (Home → gallery → player, with Back and the queue as a sheet) rather than the floating-sidebar wide layout; `RootView` switches layouts with the form. Debug builds take `-curatedLong` to start on the long Home with Latest open.

### Settings and playback rules

Settings (`SettingsView.swift`) has four pages: Sync, Playback, Appearance and Storage, with the version at the bottom of Sync. It's a `fullScreenCover` on `RootView` in every layout (`Router.settingsShown`), and unpairing closes it. It's tabs in a narrow, upright window, and otherwise (an iPad either way up, a phone on its side, a regular width) the pages listed on the left with the chosen one on the right; the chosen page carries across a rotation. The Mac's download is only followed while the Sync page is on screen. Playback has Short Videos and Long Videos groups. `Playback.applySpeed` keeps a video at 1× while its card is in the rules' `normalSpeed` (`speedLocked`), leaving the chosen `speed` alone so it returns on the next video; a held 2× still works. The stock player's speed menu is hidden while locked, and a speed picked in that menu is taken as the chosen one. Only the main Automix and its picker's starting cards use `automixOff`. Autoplay stays each device's own; the rules and time limit are shared.

### Hand-picked long videos

A long video picked on the Mac from a creator's older videos has `pickedAt` in the manifest (API 9). `AppState.handPickedFirst` puts the unwatched ones first in Latest, Automix and the creator's gallery, latest pick first; once watched they go back to their place by date. A playlist keeps its own order.

### Asking the Mac about creators (`CreatorRequests.swift`)

API 10. Add Creator on the Sync page draws the form the Mac describes (`GET /creators/form`), so it only offers what that Mac understands, and sends just the fields showing. The Mac checks them and answers with a message and errors by field, or `formChanged` to fetch the form again. Older Videos (a long creator's long-press menu and gallery) follows the Mac's listing as server-sent events, shows 40 at a time, and fetches thumbnails from the Mac only as they come on screen; the picks go to the Mac, which downloads them. `AppState.requestedVideoIDs` (saved) remembers them: the Mac's download is followed past Settings closing until they're fetched, again each time the app comes back, and any sync fetches them whichever kinds it's syncing, without the rest of the long library. Home's + opens the same Add Creator form when paired. A Mac without these routes answers 404, shown as a request to update it.

### Vines

Every sync asks for `/manifest?forms=short,long&vine=1`. While Vine is on on the Mac, that lists its Vines as short videos under made-up creators keyed `vine@<Vine user ID>` (with `"vine": true`), plus `vineCategories`, the categories whose Automix plays them. They download whenever short videos do (Short or All). `AppState.vineLibraries` holds the authors with a Vine on the device, kept out of `libraries` (no category card, no Top list). Home shows them in a Vine card (the V glyph, green avatar rings, a Vine Automix button), and `automixLibraries` adds all of them as one more creator to the main Automix and those categories' Automix. Turning Vine off on the Mac drops them from the manifest, so the next sync removes them.

### Sync and the data lifecycle (`AppState.runSync`)

1. Find the Mac by Bonjour and use the first address from its `/info` that answers (wired first), saving it in `pairing`; if Bonjour finds nothing, use the saved address. Position swaps skip the lookup, starting from the saved address so they stay quick. `GET /manifest`.
2. `POST /played` with all local played/Watch Later/bookmark marks. The Mac merges them and returns the merged sets, which replace the local ones. For each video id, the change with the newest `at` wins, so un-watching and un-saving sync too. Never delete a mark to clear it; set it to false with a new date. Create marks with `PlayedMark.now` / `WatchLaterMark.now`, which round to whole seconds (the Mac parses no fractional seconds).
3. Save the new manifest, then **delete every file in `library/videos/` that isn't in it** (`Store.removeVideos(except:)`). The Mac decides what the phone keeps.
4. Download new avatars (the rest are replaced behind the sync, about once a day), then missing videos newest first, six at a time. Each step's time goes to `diagnostics.log` as `Sync timing:` lines. Downloads resume from `.part` files using HTTP Range, inside a `beginBackgroundTask`.

Force Download: `manifest.lastDownloadAt` (API 6) is when the Mac last finished a download, shown in Settings beside **Update Mac**, which sends `POST /download` to start a total download on the Mac. While Settings is on screen the phone follows `GET /download/progress` (API 7): a ring on the right of that row fills, with who's downloading below it. The Mac closes the connection when the run ends, and leaving Settings or the app closes it from this end. A run that finished (a newer last download time than when it was seen running, saved as `macDownloadBaseline`; a stopped one keeps the old time) starts a sync of the kinds in `syncForms` (after any sync under way) and shows a checkmark (`macDownloadFinished`), which that sync leaves and the next successful one removes. Those two preferences survive closing the app and are cleared on unpair. A Mac without the route answers 404, shown as a request to update it.

Background sync: a `BGProcessingTask` (`local.curated.ios.sync`) requiring external power and network, at most hourly, when `autoSync` is on.

**Unpair wipes the phone**: pairing, all videos, avatars, the manifest, every mark and the sync-related defaults (`AppState.unpair`, also used by `-resetCurated`).

### Compatibility rules

- The payload format is defined by the Mac (`../Curated/Sources/Curated/PhoneSync.swift`). Use optionals for anything new so older and newer Macs both work, and keep the JSON identical to the Android app's `Model.kt`.
- New local fields must be optional, so a downgrade (rolling back to an older `vX.Y` build) still reads the files.

## Conventions

- Every commit appends an entry to `CHANGELOG.md` (oldest first): `## YYYY-MM-DD · Short title`, or `## X.Y · YYYY-MM-DD` for a release.
- Keep feature parity with the Android app; the two are deliberately parallel (`Store`, `Model`, `Queues`, `AppState`, `SyncClient` match file for file).
