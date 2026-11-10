# Curated for Android: changelog

Oldest first. Every commit adds an entry at the bottom; release commits are headed with their version.

## 1.0 · 2026-09-27

Companion app that syncs videos from Curated on the Mac and plays them.

- Pairing with a code from the Mac; finds it on Wi-Fi, by address, or over USB (adb reverse)
- Sync downloads new videos (resumable), removes ones the Mac deleted, and merges watched history both ways; optional automatic sync on Wi-Fi while charging
- Automix, Top 15, category Automix / Top 5, creator lists, Time Limit with countdown, unwatched count and time left, share sheet

## 2026-09-27 · Speed, Now Playing bar, adaptive icon

- Speed button cycles 1x / 1.5x / 2x; press and hold the video for 2x
- Now Playing bar on the home and creator screens with a live preview, play/pause, and an X that stops playback
- An empty mix rebuilds when reopened
- Adaptive launcher icon with a themed-icon layer

## 2026-09-27 · Picture-in-picture

- PiP button in the player; leaving the app while a video plays enters PiP automatically; the PiP window has play/pause and skip, and closing it pauses
- Videos are marked watched when they finish or are skipped, not when they start

## 1.4 · 2026-09-29

Version now tracks the Mac app.

- Home categories are collapsible cards like the Mac sidebar, with Automix and Top 5 buttons and a grid of avatars with unplayed counts; long-press an avatar to mark all played or unplayed
- TikTok and YouTube avatar rings and name colors
- YouTube Shorts creators show as @handle

## 1.5 · 2026-09-29

- Player shows the view count under an eye icon
- Watch Later: a player button saves the video and moves on without marking it watched; a Watch Later row on Home plays them; synced both ways with the Mac
- Videos the Mac deletes are removed on the next sync

## 2026-09-29 · Open into Automix

- A fresh launch with unplayed videos goes straight to the Automix player (Home stays underneath for Back)
- Automix drops Reshuffle; Time Limit is a round timer icon, filled while a timed mix runs

## 2026-09-29 · Screen stays awake; queue refreshes after sync

- The screen stays on whenever a video plays, on any screen
- A sync rebuilds the loaded queue without interrupting the current video; unplayable files are skipped

## 2026-09-29 · Calmer creator cards

- Cards show only creators with new videos, with count badges; a header toggle adds the caught-up ones in grayscale. Cards with nothing to watch start collapsed

## 2026-09-29 · Automix and Top 15 tiles

- Automix and Top 15 are square tiles at the top of Home

## 2026-09-29 · New launcher icon

- Launcher icon on a dark background

## 2026-10-03 · Headphone controls, playing on when locked

- Wired (and Bluetooth) headset button: one click plays or pauses, two skip to the next video, three go back to the previous one (or restart the first)
- Locking the screen keeps the video playing, with a media notification and lock-screen controls; closing picture-in-picture still pauses
- Unplugging headphones pauses; playback yields to calls and other apps' audio

## 2026-10-03 · Foldables, bookmarks, Settings, a swipe that follows your finger

- Galaxy Z Fold: the inner screen shows two panes split at the hinge (Home, creators and Settings on the left, the player on the right); folding or unfolding keeps the video playing. Half-folded on a table, the video sits above the hinge and its controls below
- Bookmarks: a player button keeps a video. Bookmarked videos get their own list on Home (played straight through, watched or not), stay out of Automix, and are never deleted automatically on the Mac. Synced both ways with the Mac
- The player's swipe follows your finger: the next or previous video slides in underneath, with rubber-band resistance where there's nothing to slide in
- Previous, play/pause and next are gone from the bottom of the player (tap and swipe on the video do those). Time Limit sits beside picture in picture and the queue as a matching icon; while a timed mix runs the header turns into a blue strip above the video with the MM:SS countdown in the middle
- Home shows the Curated logo and wordmark instead of the "Curated" title, and shorter Automix and Top 15 tiles with the icon beside the text
- A gear opens Settings: the sync controls, more compact (Sync Now beside the Mac, Remove Videos and Unpair on one row, USB help behind a button), and Appearance: System, Light or Dark. The player stays dark either way

## 1.6 · 2026-10-03

- First launch (and after Unpair) opens a pairing screen: the logo over slowly drifting color, an orb that pulses while it looks for your Mac, found Macs and USB as chips, and the code in six boxes; the last digit starts pairing, the orb follows the first sync, and the screen fades into the app. It fits shorter screens and gets out of the keyboard's way
- Home has the same drifting color behind frosted cards; Watch Later and Bookmarks are cards too. The Automix icon is the logo's red and the Top 15 star its cyan (red in light mode)
- Settings: the original sync controls with Unpair beside Sync Now, Appearance before what's on this phone, and an "On this phone" section with videos, storage and watch time. Remove Videos is gone: Unpair now clears the phone (videos, watched history, Watch Later and bookmarks; the Mac keeps its copies)

## 2026-10-04 · Developer notes

- CLAUDE.md describes the project, how to build and test it safely, and exactly how and where data is stored on the phone

## 2026-10-05 · Long videos and playlists

- A long-video Home, switched with the logo beside Settings: Latest and Automix, its own Watch Later and Bookmarks, category cards, and a Playlists card last with each playlist's thumbnail, length and watched count. Curated always opens on short videos
- A long-video creator or playlist opens a gallery of thumbnails with length, progress, title and description
- Long videos pick up where they were left off, with ⏪10 / play / ⏩10 and full screen above the usual buttons, a seek bar, double-tap the sides to skip 10 seconds, an Up Next sheet with Autoplay, and an Up Next card at the end when Autoplay is off
- Full screen: just the video; a tap shows the title, description and controls for 3 seconds. Landscape keeps the two-pane view, with its own full screen button
- Sync Now asks Short, Long or All each time and only downloads that; videos already on the phone stay. Settings sets what automatic sync downloads

## 2026-10-06 · Long-video wordmark

- The long Home's top bar shows the long-video wordmark (landscape cards) in place of the logo and "Long" tag

## 2026-10-07 · Scrub short videos

- Slide a finger along a short video's progress bar to scrub, like TikTok: the video pauses and follows the finger, the bar thickens and the time shows above it, and playback resumes on release

## 2026-10-07 · Save the right video's place when starting a mix

- Starting a mix while a long video plays now saves the place for that video, not for whichever video sits at the same spot in the new queue

## 2026-10-07 · Sunshine panel

- The end of a time-limited or Top mix, or of a creator's videos, fills the screen with an animated sunny morning: sky, hills, a bouncing sun, clouds, birds and flowers, with "Your N minutes are up" or "You've reached the end" and "Time to enjoy some sunshine" in Lilita One. Other queues still end with the "You're all caught up" card

## 2026-10-07 · Vine

- Vines from the Mac (Settings → Experimental → Include Vine videos there) sync to the phone along with short videos, when you sync Short or All
- Home has a Vine card with the author of every Vine on the phone, each with a Vine-green ring (or a Vine-green circle with their initial when they have no picture), and a shuffle button for Vine Automix
- Vines play in Automix and the Funny category's Automix, taking about one creator's share of the mix, and stay out of Top lists

## 2026-10-07 · Autoplay for short videos

- A round button in the short-video player turns autoplay on or off. On (an arrow with a dashed stem), the next video starts when one ends, as before. Off (the arrow slashed), each video plays on a loop; it counts as watched the first time it ends

## 2026-10-09 · Pick categories for Automix and Top 15

- Long-press Automix or Top 15 on Home to pick which categories the next mix plays from: a popup of round buttons with each category's glyph (the icon picked on the Mac) and name, a blue glyph and an unplayed-count badge on the ones that are on, and a red start button on the right. Tap outside it, press Back or swipe it away to cancel. Top 15 leaves Vine out, as Top lists always do
- Tapping a mix on Home (Automix, Top 15, Latest, or a card's own buttons) always starts a fresh list, even when that mix is already playing; the player's New List button is gone
- Category cards with nothing to play move below the ones that have something
- The short-video autoplay button moves from the top bar to the bottom row, beside the speed button

## 2026-10-09 · Watch Later and Bookmarks popups, round badges

- Watch Later and Bookmarks are small square icon buttons on the right of Home, under the mix tiles. Tapping one springs a popup list of its videos out of the button (sized to the list, up to 60% of the screen); picking a video plays the list from there, and tapping outside or Back shrinks it back into the button
- The category picker's start button sits at the bottom of the popup, under the categories
- Unplayed-count badges are circles for one digit (they were taller than wide)

## 1.7 · 2026-10-11

- Version brought in step with Curated for Mac 1.7

## 2026-10-13 · Pinch to zoom long videos; they keep their place

- Long videos no longer swipe to the next one. Pinch to zoom in or out instead: it holds for a moment (with a tick) where the video fills the screen, then keeps going if you keep pinching. Drag with one finger while zoomed in
- Long videos keep their place when you leave them: going back, opening another video, or skipping to the next one (which no longer marks it watched). Watched videos resume too, and the place is kept from 2 seconds in
- Going back into the video that's already playing carries on without reloading it

## 2026-10-14 · Clear mode; sideways short videos

- Clear mode, from the button beside picture in picture, hides everything over the video (and the status and navigation bars in the full-screen player) until you tap it; then the controls come back for 3 seconds after your last touch. It stays on until turned off
- A short video played sideways has its buttons in a column down the right edge instead of a row along the bottom
- Sideways, the screens run right up to the edge, and the player's top bar keeps clear of the camera cutout

## 2026-10-19 · Holiday colors and wordmarks

- Settings → Appearance picks what's behind Home: Aurora, in Curated's colors or Northern Lights, Ocean, Sunset, Forest or Blossom; or Holiday, in Halloween, Halloween 2, Thanksgiving or Christmas 1–3 colors. Each palette is a round swatch to tap, and the pairing screen uses the same colors. Light mode's colors are richer than before, as on the Mac
- Holiday wordmarks swaps Home's Curated wordmark (light and dark) for a holiday one through the season:
  - Halloween: October 1 – October 31
  - Thanksgiving: November 1 – Thanksgiving Day (the fourth Thursday of November)
  - Christmas: the day after Thanksgiving – January 5
- The long-video Home has its own holiday wordmarks too, with landscape cards. The rest of the year, and with the option off, each Home has its usual wordmark

## 2026-10-20 · Bigger top bar on scaled-down screens

- On a phone whose display zoom draws things smaller than usual (like a Galaxy Fold's outer screen at its Screen zoom setting), Home's wordmark, long-videos button and Settings button are drawn that much bigger, with a little room above them. Other phones, and a Fold's inner screen, look as before

## 2026-10-23 · Sideways side panel

- On a phone held sideways (a Galaxy Fold folded and turned on its side), the left pane gets its own layout. The inner screen and portrait are as before
- Home's top bar holds the main mixes as icons beside the wordmark: Automix and Top 15 on the short Home, Latest and Automix on the long one. The one that's playing is lit, and long-pressing Automix or Top 15 still picks its cards. The mix tiles step aside
- The video's details move off the video into a tray at the bottom of the left pane: picture in picture and the queue, then for short videos the progress bar, played, play or pause and next, then the creator, date and caption (a long video's title and description)
- Drag the tray down (or tap its handle) to shrink it to one row with the creator, play or pause and next, so the creator cards have room; drag it up to open it again
- Short videos make the left pane 35% wider; their remaining buttons stay in the column down the video's right edge
- Long videos get the same column of buttons down the right edge, with back 10, play, ahead 10 and full screen above a thin progress bar along the bottom

## 2026-10-23 · Short videos keep to the left sideways

- Held sideways, a short video sits against the left edge of the player pane, full height, with the room to its right left to its column of buttons

## 2.0 · 2026-10-30

- The short-video player's buttons stand in a column down the right edge, as on the Mac and the iPhone: the queue, autoplay and clear mode at the top, then share, speed, and Watch Later, bookmark and watched together in a pill, midway down. The same in the player pane of an unfolded Fold, either way up
- The buttons are round, and bigger. Share uses the same glyph as Apple's. Watch Later fills in once the video is saved, and tapping it again takes it off the list
- Time Limit is no longer a button: long-press the Automix title or the queue button to start or end a time-limited mix, or use Time Limit in the queue. While one runs, the title turns into a blue pill with the countdown, and the buttons stay where they are
- No picture-in-picture buttons in the player: leaving the app with a video playing goes into picture in picture by itself
- An unfolded Fold held upright with a short video playing: the left pane gives up to 15% of its width to the video, keeping four creators a row

## 2026-10-30 · Version in Settings

- The bottom of Settings shows the app's version and build, e.g. "Curated 2.0 (11)", as on iOS

## 2026-11-04 · Synced playback positions, Bonjour-first sync

- Where you left off in a long video syncs between devices: on opening the app, a moment after pausing, switching videos or leaving, and in full syncs. The newest change wins, and a paused player showing that video moves to a newer position. Needs a Mac on API 4
- Full syncs try USB, then find the Mac by Bonjour whatever its IP is, and use its wired address when it has one. The saved address is the fallback, and position swaps still start from it

## 2026-11-04 · Now playing syncs between devices

- The long video last playing on any device comes along when positions swap (needs a Mac on API 5). Switching to long videos, or a paused long player when a newer one arrives, has it in Now Playing, paused where it was left. Stop or finishing it clears it
- While a video plays on with the screen locked, its position goes to the Mac every minute

## 2026-11-04 · A much quicker start to syncing, six downloads at a time

- Syncing downloads six videos at a time, up from one, as on iOS
- Syncing no longer downloads every avatar again: only new ones hold it up, and the rest are replaced behind the sync about once a day
- Looking for the Mac stops as soon as it appears, rather than always waiting 1.5 seconds
- Logcat records how long the main steps of a sync take (`Sync timing:` lines, tag `Curated`)

## 2026-11-05 · Force Download, last download on the Mac

- Settings: Force Download, near Sync Now, asks the Mac to download everything now and shows its answer
- Settings shows when the Mac last finished a download, updated with each sync

## 2026-11-05 · Live download progress from the Mac

- Force Download now reads "Force Download on" and the Mac's name. While the Mac downloads, a ring on the right of that row fills and the creators downloading are listed under it, live, while Settings is open. The connection closes when the download ends
- When it finishes, the ring becomes a checkmark, which the next sync removes. A stopped download shows no checkmark
- The "started downloading" message that never went away is gone

## 2026-11-05 · Sync when the Mac's download finishes

- When a download followed in Settings finishes, the phone syncs by itself, fetching the kinds of video set under Automatic Sync Downloads. The checkmark stays through that sync, and the next one removes it

## 2026-11-05 · Settings in pages, 1x only categories, Automix defaults

- Settings is now a short list: Sync, Playback, Appearance and Storage, each with its own page
- Playback has Short Videos and Long Videos groups, with Autoplay in each and the Time Limit under short videos, now settable here
- Each category can be left out of Automix by default, and set to 1x only. A 1x only category plays at normal speed with the speed button dimmed, and your chosen speed comes back on the next video
- Long-pressing Automix starts from the checked categories, and a category's own Automix still plays it
- Long videos: playlists can be 1x only, and Back Up When Resuming starts a video 5, 10 or 30 seconds before where you left off
- These settings and the Time Limit are shared with the Mac and other phones: the newest change on any device wins

## 2026-11-05 · Settings fills the screen, in tabs or two panes

- Settings now covers the whole screen. An upright phone or a Fold's cover screen gets tabs along the bottom. A phone on its side and an unfolded Fold, either way up, get the pages on the left and the chosen one on the right
- The version moved to the bottom of the Sync page

## 2026-11-05 · Open a creator in YouTube or TikTok

- Long-pressing a creator or playlist now offers Open in YouTube or Open in TikTok. Vine authors and the Suggestions playlist have no page, so they don't

## 2026-11-05 · Hand-picked long videos come first

- Long videos you picked on the Mac from a creator's older videos come first in Latest, Automix and the creator's gallery until you've watched them. Then they go back to their place by date

## 2026-11-05 · Add creators and pick older videos, on the Mac from here

- Add Creator on the Sync page shows the same options as the Mac, whichever the Mac offers. The Mac checks them and answers: added, or what's wrong beside the field. A Mac too old for it asks to be updated
- Older Videos, in a long creator's long-press menu and gallery, or Request Older Videos on the Sync page for any creator with long videos on, lists what's not downloaded yet, 40 at a time. Pick some and your Mac downloads them; skip some and they're marked watched. They arrive with your next sync of long videos

## 2026-11-05 · Requested videos come by themselves, and + on Home

- Long videos you pick from a creator's older videos now come to this device on their own once the Mac finishes, or the next time you open Curated if it was closed. Only those videos, so a device that syncs short videos doesn't start on the whole long library
- A + on Home adds a creator on your Mac, the same form as on the Sync page. It shows once you're paired

## 2026-11-05 · A simpler Sync page

- Paired Mac is now just the Mac and Unpair
- Sync shows how the last one went beside it, and syncs what the new Sync: menu says (Short, Long or All Videos) instead of asking each time
- Sync Automatically comes under that, then Update Mac (what Force Download was), with when it last downloaded beside it
- Add Creator is on its own at the bottom, above the version
- Request Older Videos is gone from Settings. A long creator's long-press menu and gallery still have Older Videos

## 2026-11-07 · Android Auto (on the android-auto branch)

- Curated now works in the car with Android Auto: Mixes, Categories and Creators, in grids of colorful mix tiles, category glyphs (each category its own color), creator pictures and video thumbnails. Short videos get a frame from the video as their thumbnail
- Now Playing has speed, back 15 seconds, bookmark and Watch Later, and the video's thumbnail. Only the sound plays in the car
- Up Next in Mixes shows what's coming and jumps to any of it, and search finds creators and videos, by voice too
- In the car, videos always go on to the next one, whatever the autoplay settings, and the sound carries on when you leave the app on the phone. Disconnecting pauses it unless the phone is in use. The end of a mix shows the same message as the phone, sunshine included
- The media notification and lock screen now show the video's thumbnail too

## 2026-11-10 · A calmer sunshine panel

- The end of a time-limited or Top mix, or of a creator's videos, is now a quiet daybreak: a twilight sky with a few stars warms to morning as a soft sun rises from behind layered hills, then the message fades up in the system font. The smiling sun, birds, flowers and bouncing letters are gone. With animations turned off it shows the finished scene, standing still
