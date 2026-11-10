# Curated for iOS: changelog

Oldest first. Every commit adds an entry at the bottom; release commits are headed with their version.

## 1.5 · 2026-10-02

The iPhone companion, caught up with the Android app (version in step with the Mac).

- Watch Later: a player button saves a video and moves on without marking it watched; a Watch Later row on Home plays them; synced both ways with the Mac
- Home: the Curated logo, Automix and Top 15 tiles, and collapsible creator cards with avatar grids, count badges and each category's Automix and Top 5 buttons
- TikTok and YouTube avatar rings; YouTube creators show as @handle
- Player: TikTok-style swipe between videos, view count, Time Limit as a round icon with a glass countdown
- Opens straight into Automix, refreshes the queue after a sync, skips unplayable files, keeps the screen awake while playing

## 2026-10-02 · iPad layouts

- Landscape on a full-width iPad mirrors the Mac window: sidebar, queue and player side by side; portrait and narrow windows use the phone layout
- Phone player: Queue, Time Limit and picture in picture in one column

## 2026-10-03 · iPhone Duo layouts

- Built with Xcode 27.1 so the app runs natively on iPhone Duo
- Inner display: the sidebar stays in landscape and slides out as a glass panel in portrait; the player's buttons go in the system side toolbar
- Outer display: the same side toolbar in the phone player
- Swipe between videos in the wide player too; previous, play/pause and next buttons removed (tap, swipe and hold on the video do those)

## 2026-10-03 · Blurred video fill

- Behind every player, the playing video scaled to fill, blurred and dimmed, instead of black bars

## 2026-10-03 · Playing on when locked; headphone triple-click

- Locking the screen keeps the sound playing (the picture comes back on unlock); leaving the app still goes to picture in picture, or pauses
- Headphones: one click plays or pauses, two skip, three go back; at the first video, three clicks restart it
- The picture-in-picture button appears only when picture in picture can actually start

## 1.6 · 2026-10-03

- Bookmarks: a player button (⌘B on iPad) and context-menu item, a Bookmarks list on Home and in the iPad/Duo sidebar; kept out of Automix, never deleted automatically on the Mac, played straight through; synced both ways
- First launch (and after Unpair) opens a pairing screen: the logo over slowly drifting color, an orb that pulses like AirDrop while it looks for your Mac, found Macs as chips, and the code in six boxes; the last digit starts pairing, the orb follows the first sync, and it fades into the app. On iPhone Duo it runs full screen behind the side strip (with Xcode 27.1) and the orb shrinks to fit
- Home (and the iPad/Duo sidebar) has the same drifting color behind Liquid Glass cards. The Automix icon is the logo's red and the Top 15 star its cyan (red in light mode), including the selected rows in the iPad/Duo sidebar
- A gear opens Settings: the sync controls (Unpair beside Sync Now, videos with their storage) and Appearance: System, Light or Dark (the player stays dark). Remove Downloaded Videos is gone: Unpair now clears this device (videos, watched history, Watch Later and bookmarks; the Mac keeps its copies)
- Builds with Xcode 27.0 again (the iPhone Duo side-toolbar code needs the 27.1 SDK and is left out of older ones)

## 2026-10-04 · Developer notes

- CLAUDE.md describes the project, how to build and test it safely, and exactly how and where data is stored on the phone

## 2026-10-06 · Long videos and playlists

- A long-video Home, switched with the mark in the top bar: Latest and Automix, its own Watch Later and Bookmarks, category cards, and a Playlists card last. It shows the long-video wordmark in place of the logo. Curated always opens on short videos
- A long-video creator or playlist opens a gallery of thumbnails with length, progress, title and description
- Long videos play in Apple's own player: 10-second skips, scrubbing, speed, full screen and picture in picture. They pick up where they were left off and stop at the end with an Up Next card unless Autoplay is on
- Turning an iPhone sideways with a long video open shows just the video; turning it upright goes back. The rest of the app stays upright
- iPhone Duo in portrait: long mode uses the phone's screens (Home, gallery, player, with the queue as a sheet); the inner display keeps its two-pane landscape layout
- Sync Now asks Short, Long or All each time and only downloads that; videos already on the device stay. Settings sets what automatic sync and pull to refresh download

## 2026-10-07 · Scrub short videos

- Slide a finger along a short video's progress bar to scrub, like TikTok: the video pauses and follows the finger, the bar thickens and the time shows above it, and playback resumes on release. VoiceOver can swipe up or down on it to skip 5 seconds

## 2026-10-07 · Save the right video's place when starting a mix

- Starting a mix while a long video plays now saves the place for that video, not for whichever video sits at the same spot in the new queue

## 2026-10-07 · Sunshine panel

- The end of a time-limited or Top mix, or of a creator's videos, fills the screen with an animated sunny morning: sky, hills, a bouncing sun, clouds, birds and flowers, with "Your N minutes are up" or "You've reached the end" and "Time to enjoy some sunshine" in Lilita One. With Reduce Motion it shows the finished scene, standing still. Other queues still end with the "You're all caught up" card

## 2026-10-07 · Vine

- Vines from the Mac (Settings → Experimental → Include Vine videos there) sync to the phone along with short videos, when you sync Short or All
- Home (and the iPhone Duo sidebar) has a Vine card with the author of every Vine on the phone, each with a Vine-green ring (or a Vine-green circle with their initial when they have no picture), and a shuffle button for Vine Automix
- Vines play in Automix and the Funny category's Automix, taking about one creator's share of the mix, and stay out of Top lists

## 2026-10-07 · Autoplay for short videos

- A round button in the short-video player turns autoplay on or off. On (an arrow with a dashed stem), the next video starts when one ends, as before. Off (the arrow slashed), each video plays on a loop; it counts as watched the first time it ends

## 2026-10-09 · Pick categories for Automix and Top 15

- Long-press Automix or Top 15 (on Home, or in the iPhone Duo and iPad sidebar) to pick which categories the next mix plays from: a popup of round glass buttons with each category's glyph and name, a blue glyph and an unplayed-count badge on the ones that are on, and a red start button on the right. Tap outside it or swipe it away to cancel. On iPhone Duo's outer display it spans the screen
- Tapping a mix tile always starts a fresh list, even when that mix is already playing
- The iPhone Duo and iPad sidebar has the same Automix and Top 15 tiles as Home (Latest and Automix for long videos) in place of the rows with category icons; the open mix's tile fills with its color
- Category cards show their glyph from the Mac before the name; their buttons sit closer together, and the unplayed count steps aside before a long name would be cut off. The caught-up toggle turns the logo red when on
- iPhone Duo partly folded and upright, playing a long video: the video fills the top half; below the fold are the top bar, a seek bar, back 10 / play-pause / ahead 10, and the description and buttons at the bottom

## 1.7 · 2026-10-11

- Version brought in step with Curated for Mac 1.7

## 2026-10-13 · Watch Later and Bookmarks popups

- Home: Watch Later and Bookmarks are small square icon buttons on the right, shown while something is saved. Tapping one pops up its list of videos; picking one plays the list from there. The same in the wide layout's sidebar

## 2026-10-19 · Holiday colors and wordmarks; "watched" everywhere

- Settings → Appearance picks what's behind Home: Aurora, in Curated's colors or Northern Lights, Ocean, Sunset, Forest or Blossom; or Holiday, in Halloween, Halloween 2, Thanksgiving or Christmas 1–3 colors. Each palette is a round swatch to tap, and the pairing screen uses the same colors. Light mode's colors are richer than before, as on the Mac and Android
- Holiday wordmarks swaps Home's Curated wordmark (light and dark) for a holiday one through the season:
  - Halloween: October 1 – October 31
  - Thanksgiving: November 1 – Thanksgiving Day (the fourth Thursday of November)
  - Christmas: the day after Thanksgiving – January 5
- The long-video Home has its own holiday wordmarks too, with landscape cards. The rest of the year, and with the option off, each Home has its usual wordmark
- Short videos are "watched" and "unwatched" now too, as long ones already were: the mix tiles, creator counts, menus, the player's button and its labels

## 2026-10-23 · Landscape on iPhone, wordmark in the top bar

- Home's wordmark sits in the top bar, level with the long-videos and Settings buttons
- The iPhone app turns sideways now. On its side it gets the same layout as the Android app on a Fold's cover screen:
  - The screens on the left, with Home's mixes as icons in the top bar beside the wordmark (Automix and Top 15 on the short Home, Latest and Automix on the long one); the one playing is lit, and long-pressing still picks its cards. The mix tiles and the mini player step aside
  - A tray under them: picture in picture and the queue, then for short videos the progress bar, watched, play or pause and next, then the creator, date and caption (a long video's title and description). Drag it down, or tap its handle, to shrink it to one row; drag it up to open it again
  - The player on the right. Short videos keep to its left edge, full height, and widen the left pane by 35%; long videos have back 10, play, ahead 10 and full screen above a thin progress bar. Either way the buttons (Time Limit or autoplay, then autoplay or watched, speed, Watch Later, bookmark and share) stand down the right edge, out by the screen's edge and clear of the Dynamic Island
  - Full screen shows just the long video; turning the phone upright, or the exit button while paused, goes back. Turning upright puts the playing video's player back on top
- Long videos no longer jump to full screen when the phone turns sideways; the full screen button does that. Apple's player's own full screen still turns an upright phone sideways and back

## 2026-10-25 · Snappier swipes

- The next video is queued and ready behind the one playing, so a swipe up starts it almost at once; the previous one is opened ahead of a swipe back
- The first-frame picture covering a new video goes away as soon as it starts playing, instead of lingering for a moment
- Easier to swipe: an eighth of the screen, or any quick flick, moves on (it was a quarter, or a long flick)
- Marking a video watched saves in the background, so it no longer holds up the next video
- More space between the buttons under a short video

## 2026-10-25 · Lighter aurora

- The aurora behind Home uses much less battery: each color is blurred once and then just moved, instead of blurring the whole screen for every frame. It moves as before, ten times a second (it drifts slowly enough that it looks the same)
- It stands still while the player covers Home and while the app isn't active

## 2026-10-25 · Lighter video backdrop

- The blurred fill behind short videos uses much less battery: ten times a second it takes a tiny frame of the video and stretches it out, instead of blurring a second full-size copy of the video live
- It stops taking frames while the app is in the background, so sound with the screen locked stays as light as before

## 2026-10-25 · Low Power setting

- New Low Power switch in Settings, off by default. Off, the aurora and the blur behind short videos look exactly as they used to; on, they use the lighter versions above
- In Low Power the blur behind short videos is drawn on the GPU straight into memory the screen reads, which takes a little more load off
- The aurora still stands still while it's hidden, either way

## 2026-10-25 · Low Power: no blur behind videos

- In Low Power, short videos play on black, with no blurred fill behind them at all (instead of the lighter blur)

## 1.9 · 2026-10-29

- Fixed: the locked phone could start playing videos on its own. When iOS opened the app in the background for a sync (while charging), the launch went into Automix and started playing. A mix started in the background now waits, paused, and starts playing once you open the app

## 2026-10-29 · Version in Settings

- The bottom of Settings shows the app's version and build, e.g. "Curated 1.9 (10)"

## 2.0 · 2026-10-30

- The short-video player's buttons match the Mac's: share, speed, and Watch Later, bookmark and watched together in a glass pill, midway down the right edge under the queue and autoplay. Watch Later fills in once the video is saved, and tapping it again takes it off the list. The caption gets the full width
- Time Limit is no longer a button, here, sideways, on iPhone Duo or on iPad: long-press the Automix title or the queue button to start or end a time-limited mix, or use the timer on the left of the queue's Done row
- Clear mode, as on Android: a button under autoplay hides everything over a short video, and the status bar, until you tap it; then the controls come up for 3 seconds after the last touch

## 2.1 · 2026-11-03

- Syncing downloads three videos at a time, and shows the speed ("Downloading 4 of 12 · 256 Mbps")
- Fixed: the Picture in Picture button could do nothing, then disappear. Picture in picture could end up tied to the mini player's hidden thumbnail under the player; now it always follows the player on screen
- Fixed: turning the phone sideways while a video played paused it
- A diagnostics log (diagnostics.log in the app's Documents) records why picture in picture fails to start, audio session errors and interruptions, sound route changes and each resume, to track down sound going missing
- Long videos full screen stay sideways, however the phone is turned, until you leave full screen (as in YouTube); leaving goes back to the player for the way the phone is held: upright, or the sideways layout
- Sideways full screen has a single exit button: its own controls (tap to show; back and ahead 10 seconds, play or pause, the scrub bar, exit) replace the stock player's, whose full screen button overlapped the exit one
- Long videos on an upright iPhone play in the same player as full screen and sideways, with its own controls (tap to show: back and ahead 10 seconds, play or pause, the scrub bar, full screen), instead of Apple's stock player; its full screen button turns the phone sideways and holds it there. iPad and iPhone Duo's inner display keep the stock player

## 2026-11-03 · Back on main

- The iphone-duo branch, where all iOS work had gone since 1.6, is merged into main, and work carries on there

## 2026-11-04 · Fewer redraws from environment closures

- The sidebar, queue, Time Limit and full screen actions passed down through the environment no longer redraw every view reading them each time their parent updates (`ViewAction`)

## 2026-11-04 · Synced playback positions, sound after a long pause, faster syncs

- Where you left off in a long video syncs between devices: on opening the app, a moment after pausing, switching videos or leaving, and in full syncs. The newest change wins, and a paused player showing that video moves to a newer position. Needs a Mac on API 4
- Trying to fix sound cutting out on resume: resuming after 2 seconds or more off screen, or a minute on screen, swaps in a new player item at the same spot and speed. The cause isn't established, so `diagnostics.log` now records `Resumed with a fresh item` and player errors
- Full syncs find the Mac by Bonjour whatever its IP is, and use its wired address when it has one (about 600 Mbps against 320 over its Wi-Fi address). The saved address is the fallback, and position swaps still start from it
- Syncing downloads six videos at a time, up from three
- `DEVELOPMENT_TEAM` is set in `project.yml`, so builds install on the iPhone without changing it by hand

## 2026-11-04 · Now playing syncs between devices

- The long video last playing on any device comes along when positions swap (needs a Mac on API 5). Switching to long videos, or a paused long player when a newer one arrives, has it in Now Playing, paused where it was left. Stop or finishing it clears it
- While a video plays on with the screen locked, its position goes to the Mac every minute

## 2026-11-04 · A much quicker start to syncing

- Syncing no longer downloads every avatar again: only new ones hold it up, and the rest are replaced behind the sync about once a day
- Looking for the Mac stops as soon as it appears, rather than always waiting 1.5 seconds. A sync with nothing to download went from about 4 seconds to about 0.4 on the iPhone
- `diagnostics.log` records how long each step of a sync takes (`Sync timing:` lines)

## 2026-11-05 · Force Download, last download on the Mac

- Settings: Force Download, near Sync Now, asks the Mac to download everything now and shows its answer
- Settings shows when the Mac last finished a download, updated with each sync

## 2026-11-05 · Live download progress from the Mac

- Force Download now reads "Force Download on" and the Mac's name. While the Mac downloads, a ring on the right of that row fills and the creators downloading are listed under it, live, while Settings is open. The connection closes when the download ends
- When it finishes, the ring becomes a checkmark, which the next sync removes. A stopped download shows no checkmark
- The "started downloading" message that never went away is gone

## 2026-11-05 · Sync when the Mac's download finishes

- When a download followed in Settings finishes, the phone syncs by itself, fetching the kinds of video set under Automatic Sync Downloads. The checkmark stays through that sync, and the next one removes it

## 2026-11-05 · Settings in pages, 1× only categories, Automix defaults

- Settings is now a short list: Sync, Playback, Appearance and Storage, each with its own page
- Playback has Short Videos and Long Videos groups, with Autoplay in each and the Time Limit under short videos, now settable here
- Each category can be left out of Automix by default, and set to 1× only. A 1× only category plays at normal speed with the speed button dimmed, and your chosen speed comes back on the next video
- Long-pressing Automix starts from the checked categories, and a category's own Automix still plays it
- Long videos: playlists can be 1× only, and Back Up When Resuming starts a video 5, 10 or 30 seconds before where you left off
- These settings and the Time Limit are shared with the Mac and other phones: the newest change on any device wins

## 2026-11-05 · Settings fills the screen, in tabs or two panes

- Settings now covers the whole screen. An upright iPhone gets tabs along the bottom. An iPhone on its side and an iPad, either way up, get the pages on the left and the chosen one on the right
- The version moved to the bottom of the Sync page

## 2026-11-05 · Open a creator in YouTube or TikTok

- Long-pressing a creator or playlist now offers Open in YouTube or Open in TikTok. Vine authors and the Suggestions playlist have no page, so they don't

## 2026-11-05 · Hand-picked long videos come first

- Long videos you picked on the Mac from a creator's older videos come first in Latest, Automix and the creator's gallery until you've watched them. Then they go back to their place by date

## 2026-11-05 · Add creators and pick older videos, on the Mac from here

- Add Creator on the Sync page shows the same options as the Mac, whichever the Mac offers. The Mac checks them and answers: added, or what's wrong beside the field. A Mac too old for it asks to be updated
- Older Videos, in a long creator's long-press menu and gallery, or Request Older Videos on the Sync page for any creator with long videos on, lists what's not downloaded yet, 40 at a time. Pick some and your Mac downloads them; skip some and they're marked watched. They arrive with your next sync of long videos

## 2026-11-05 · Home's colors stop behind Settings

- Home's moving colors no longer keep drawing behind the full-screen Settings, which used battery for nothing

## 2026-11-05 · Requested videos come by themselves, and + on Home

- Long videos you pick from a creator's older videos now come to this device on their own once the Mac finishes, or the next time you open Curated if it was closed. Only those videos, so a device that syncs short videos doesn't start on the whole long library
- A + on Home adds a creator on your Mac, the same form as on the Sync page. It shows once you're paired

## 2026-11-05 · A simpler Sync page

- Paired Mac is now just the Mac and Unpair
- Sync shows how the last one went beside it, and syncs what the new Sync: menu says (Short, Long or All Videos) instead of asking each time
- Sync Automatically comes under that, then Update Mac (what Force Download was), with when it last downloaded beside it
- Add Creator is on its own at the bottom, above the version
- Request Older Videos is gone from Settings. A long creator's long-press menu and gallery still have Older Videos

## 2026-11-05 · The pairing screen no longer freezes, and sound after interruptions

- The pairing screen on a phone with nothing paired could come up blank and use the whole processor, because its card and orb kept resizing each other. Now it draws straight away
- After something interrupts the sound, resuming waits for the sound system before playing. This is aimed at sound going silent while the picture carries on; it's not yet known whether it cures it

## 2026-11-07 · A picture on the lock screen

- The lock screen and Control Center now show the video's thumbnail. Long videos use their poster, and short videos a frame from the video
