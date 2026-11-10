# Curated for Mac: changelog

Oldest first. Every commit adds an entry at the bottom; release commits are headed with their version.

## 1.0 · 2026-09-27

Native SwiftUI Mac app for intentional TikTok watching: pick creators, download their recent videos on a schedule with yt-dlp, and watch them without a feed.

- Per-creator download windows, an overnight LaunchAgent, and manual downloads
- Creator tabs, Automix, Top 15, and Time Limit mixes with a hard stop
- Played tracking, categories with icons, category Automix / Top 5
- Settings, About window, logo and Icon Composer app icon

## 1.1 · 2026-09-27

- Automix header shows the unwatched videos in the mix and the time left to watch them
- Time Limit is a toggle with a live countdown banner; turning it off returns to the full Automix without interrupting the current video
- Creators & Downloads shows the total number and length of downloaded videos
- New setting to download new videos when Curated opens

## 1.2 · 2026-09-27

- Built-in phone sync server (off by default): Bonjour discovery, 6-digit pairing, per-phone tokens, video and avatar downloads with Range support, and two-way watched-state merge (newest change wins)
- Phone Sync settings and a bottom-bar button with a Discoverable switch, pairing code and paired phones
- Share button in the player opens the macOS share sheet for the video file
- Watched history stores when each video's state changed (old lists upgrade automatically)
- `CURATED_DATA_DIR` override for testing against a separate data folder

## 2026-09-27 · Test sync port

- `CURATED_SYNC_PORT` override so test copies don't collide with the real app

## 2026-09-27 · Watched on finish or skip

- Starting a video no longer marks it watched; finishing it or skipping it does

## 2026-09-27 · Condensed sidebar

- Category icons sit beside Automix and Top 15 in the Watch section and open that category's Automix or Top 5; Settings chooses which appear
- Category headers carry their own Automix and Top 5 buttons instead of separate rows

## 2026-09-27 · Settings in tabs

- General, Storage, Sidebar, Phone Sync and Advanced tabs, so Settings fits on a laptop screen

## 1.3 · 2026-09-29

- Sidebar creators are a grid of larger avatars with compact unplayed counts (a checkmark once caught up), most unplayed first
- Each category is a collapsible Liquid Glass card with its unplayed count and its Automix and Top 5 buttons
- Downloads run three creators at a time, starting with never-downloaded creators, then whoever has gone longest without a successful refresh

## 1.4 · 2026-09-29

- YouTube Shorts creators: add a channel by @handle or link. Shorts come from the channel's Shorts-only feed, so full-length videos are never downloaded. They mix into Automix, Top lists and phone sync like TikToks
- Separate "download when Curated opens" switches for TikTok and YouTube Shorts
- Avatar rings: TikTok cyan-to-magenta, YouTube red; creator names in queues use the same colors
- Search field in Creators & Downloads filters by name or handle

## 1.5 · 2026-09-29

- Player shows the view count under an eye icon
- Watch Later: a player button (and ⌘L) saves the video and moves on without marking it watched. Saved videos get their own list, still play in Automix, leave the list once watched, and sync both ways with the phone
- Settings → Storage: Delete All Watched Videos (they're never downloaded again; phones drop them on their next sync)
- Updated logo and app icon artwork

## 2026-09-29 · Platform icons in Creators & Downloads

- Each creator row leads with a TikTok or YouTube icon instead of an inline "YouTube Shorts" tag

## 2026-09-29 · USB sync toggle, calmer creator grid

- Phone Sync popover has a USB Sync switch that keeps `adb reverse` set up on plugged-in phones; the sidebar sync button turns red while the USB port is open
- Creator cards show only creators with new videos, with count badges on their avatars; a header toggle adds the caught-up ones, dimmed. Cards with nothing to watch start collapsed

## 2026-09-30 · Liquid Glass queue controls

- The queue header floats as a glass panel the list scrolls under, with glass Reshuffle and Time Limit buttons
- The unwatched / time-left summary is a glass capsule over the player
- The sidebar blurs the windows behind it; a glass button on the player shows or hides the queue

## 2026-10-03 · Stable code signature

- `build.sh` signs with the Apple Development certificate when there is one. An ad-hoc signature changed with every build, so macOS stopped honoring Full Disk Access (needed for Firefox cookies) after each reinstall

## 2026-10-03 · Minimum views, category filter, sorting

- Each creator can be limited to videos with at least a set number of views (10K to 5M). Videos under it aren't recorded as downloaded, so every run rechecks them and downloads any that catch on while they're still inside the creator's window. The creator's status line shows how many are waiting
- Clicking a category chip in Creators & Downloads shows only its creators (All and No Category chips too); right-click a chip to edit or delete it
- Sort By menu in the toolbar: Oldest Added, Newest Added, Name, Most Unplayed, Recently Checked

## 2026-10-03 · Bookmarks, a player like the iPhone Duo's, a new Creators & Downloads bar

- Bookmarks: a player button (⌘B), a context-menu item and a Bookmarks list in the sidebar. Bookmarked videos stay out of Automix, play straight through in their list, and are never deleted automatically (by the window clean-up, the overnight run or Delete All Watched Videos); remove the bookmark and they go in the next routine deletion. Synced both ways with the phones through /played
- Move to Trash in a video's context menu deletes it by hand; it's never downloaded again
- Player: AVKit's controls are replaced by floating glass ones (previous, play/pause, next, scrubber, mute, full screen), centered and shown on hover. The bar under the video is gone: creator, date, views and caption sit over the video, and a column down the right holds, in the iPhone Duo's order, show/hide queue and Time Limit (circles), then share and a new speed button (1×, 1.5×, 2×), then Watch Later, bookmark and played together
- Watch Later toggles: on a saved video it takes it off the list and keeps playing
- The "n unwatched · time left" pill moved to the top left; while a time limit runs it turns blue and counts the limit down
- The queue list is see-through with a light tint, creator names in it are bold, and each entry has a TikTok or YouTube badge
- Creators & Downloads: a taller, rounder add field with gray TikTok and YouTube icons that light up from a pasted link (pick one for a bare username; Add Creator waits until there is one), and the form resets after adding. Categories are pills (no "All": nothing chosen shows everyone) with group, new and edit buttons. Edit mode wiggles the pills like iOS icons: click one to edit or delete it, drag it to reorder; the order is the sidebar's and the phones'. Group splits the list into a section per category. Pills shrink to their icon when there's no room for names
- Removing a creator: one confirmation dialog for the list, the search clears if it only matched that creator, and empty lists keep the bars at the top
- Settings: the Storage note says bookmarked videos are never deleted automatically

## 1.6 · 2026-10-03

Release of everything since 1.5: phone sync with the Fold and the new pairing screen on the phones, bookmarks, the iPhone Duo-style player, minimum views per creator and the new Creators & Downloads bar (see the entries above).

- The header above the queue is gone (title, Reshuffle / New List, Time Limit and the Time left bar); Time Limit lives in the player's side column, and the top-left pill turns blue with the countdown while it runs

## 2026-10-04 · App icon follows light and dark mode

- The icon's background now uses the system light and dark fills instead of fixed gray, and the red mark has a subtle gradient

## 2026-10-04 · Developer notes

- CLAUDE.md describes the project, how to build and test it safely, and exactly how and where data is stored
- Xcode's per-user `.swiftpm/` folder is ignored

## 2026-10-05 · Long videos and playlists

- Long YouTube videos: a creator's wide-video icon (beside the tall Shorts one) downloads their long videos too, at the resolution picked on their row (1080p, 720p, 480p or 144p). They're kept until watched or deleted, never for their age
- YouTube playlists: paste a playlist link to add one, with all its videos or only its newest few; it lands in the Playlists group, uses the playlist's own thumbnail, and keeps the playlist's order
- A long-video sidebar, switched with the logo between Now Playing and Phone Sync: Latest and Automix, its own Watch Later and Bookmarks, category cards, and a Playlists card last. Curated always opens on short videos
- A creator or playlist opens a gallery of thumbnails with length, progress, title and description; Manage Videos (the pencil) deletes videos and shows their sizes, and the gallery shows the total on disk
- Long videos play full width with Up Next sliding up from the bottom, pick up where they were left off, and stop at the end with an Up Next card unless Autoplay is on
- Creators & Downloads: a Long-only filter, sort by Platform, two info columns per creator, "Keep n days", a views squircle you click through, and a Short / Long / Total bar with its own download buttons
- Phone sync can send long videos and playlists to phones that ask for them; older phones still get short videos only

## 2026-10-06 · Long-video wordmark, glass player controls

- The sidebar shows the long-video wordmark (landscape cards) in long mode and the usual logo in short mode, in place of the "Long" tag
- Long videos: skip back and ahead 15 seconds in the glass controls over the video, in place of previous and next (⌘← / ⌘→ and Up Next still move between videos)
- Long videos' full screen button opens Apple's own full screen, with just the video and Apple's Liquid Glass controls
- Curated now builds against the current macOS SDK, so Apple's own controls use the Liquid Glass look
- A creator gallery's Manage menu is a checklist icon instead of a pencil in a circle

## 2026-10-07 · Fix crash starting a mix

- Fixed a crash when starting a mix (such as a category's Automix) while a video further down the current queue was playing. Also, the place in a long video is now saved for that video, not for whichever video sits at the same spot in the new queue

## 2026-10-07 · Vine (experimental)

- Settings has an Experimental tab with "Include Vine videos". Turned on, Curated downloads classic Vines from divine.video's archive, a batch at a time
- Creators & Downloads: a Vine row (with a round Vine logo where a creator's avatar would be) heads the creator list, where you choose how many Vines each download fetches (10, 25, 50 or 100), and the download bar has a Vine section between Long and Total, marked with the short-video cards in Curated red behind a Vine-green card. Total, and the overnight download, include Vine too
- The sidebar has a Vine card (with the Vine V as its glyph, like a category's) with the author of every Vine downloaded, each with a Vine-green ring (or a Vine-green circle with their initial when they have no picture), and a shuffle button for Vine Automix (every Vine, taking turns between their authors)
- Vines play in Automix and in the Funny category's Automix, taking about one creator's share of the mix. They stay out of Top lists and the age-based cleanup. Phones get them when they sync short videos (Short or All), with the newest Android and iOS builds; older phone builds never see them. Turning Vine off hides them; the files stay on disk

## 2026-10-07 · Open without playing

- Curated opens on Automix with its queue listed and nothing playing: the Curated logo and "Pick a video to start watching" sit where the video goes until you pick one. Opening a mix after that plays it straight away, as before

## 2026-10-07 · Autoplay for short videos

- A round button in the short-video player turns autoplay on or off. On (an arrow with a dashed stem), the next video starts when one ends, as before. Off (the arrow slashed), each video plays on a loop; it counts as watched the first time it ends

## 2026-10-10 · Mix tiles, keep n videos, tidier creator rows

- The sidebar's mixes are tiles, as on iOS: Automix and Top 15 (Latest and Automix for long videos), the open one filled with its color. Holding a mix (or Option-clicking it) picks which category cards it plays from. Watch Later and Bookmarks are small buttons side by side, shown while something is saved. The category shortcut icons, and Settings' Sidebar tab, are gone
- Creators & Downloads: a creator's short videos can be kept by count instead of by age. The Keep button (a download icon with a clock and the number of days, or a stacked download icon and the number of videos) opens a small popover: videos from the last n days, or the newest n unwatched. Kept by count, each download fetches only enough to get back to n unwatched: new posts first, oldest of them first, never a watched video. With Historical on, older videos not yet downloaded fill in when there aren't enough new ones. These creators are left out of the age-based cleanup; long videos still use the day window
- Long-video resolution is a squircle to the right of the long-video icon, like the views one: Best (the highest H.264, usually 1080p), then 1080p down to 144p. Click for the next, Option-click for the one before
- Minimum views: All, 5K, 10K, 20K, 35K, 50K, 75K, 100K, 200K, 500K and 1M. Option-click steps back down
- A creator's category is a button showing its glyph; clicking it opens a popover of every category as a tile with its name
- Every button on a creator's row is the same height
- The Log button is gone: File → Show Download Log (⇧⌘L) opens the log in its own window

## 2026-10-10 · Download progress, Trim, Vine top-up, iOS-style saved buttons

- Creators & Downloads: while any download runs, the line above the download bar fills from left to right in the accent color, then fades out when it's done
- File → Trim Creators Kept by Count… (and Trim in a creator's … menu) keeps each count-kept creator's oldest unwatched videos, up to its count, and moves the rest to the Trash. They come out of the download history, so they download again later in their turn. Watched and bookmarked videos stay
- Bookmarked videos no longer count toward a creator's "keep n videos"
- Vine keeps a number of unwatched Vines (5, 10, 15, 25, 50 or 100) instead of fetching a batch every time: each download tops it back up. Trim covers Vine too (also in the Vine row's … menu); trimmed Vines are the first to download again
- The sidebar's Watch Later and Bookmarks are square glass buttons on the right, as on iOS. Clicking one lists its videos in a popover; picking one plays that list from there
- The Vine mark in the download bar has its outlined cards in the logo cyan (near-black in light mode), like the other marks

## 2026-10-11 · Creator row errors on their own line

- Creators & Downloads: a creator's last download error is on its own line under "checked …", still orange if some videos came down and red if none did. Hovering the error shows all of it

## 2026-10-11 · Automix tile not filled at launch

- The Automix tile isn't filled in when Curated opens on its queue; it fills once it's clicked (or anything else in the sidebar is picked)

## 2026-10-11 · Sidebar backgrounds: see-through when inactive, drifting colors in full screen

- The sidebar and the queue beside the player stay blurred and see-through when Curated isn't the front app, instead of turning flat gray
- In full screen, where there's nothing behind the window to see through to, the sidebar and the queue show the phones' slowly drifting red, cyan and blue colors instead

## 2026-10-11 · Swipe through short videos, movable controls, Aurora option

- Short videos are on a tape, as on the phones: a two-finger swipe up on the trackpad slides the next video up from below, following your fingers, and a swipe down brings back the previous one. Past a quarter of the player, or flicked, it switches; otherwise it springs back. A mouse wheel moves one video per notch
- The floating playback controls can be dragged anywhere over the video, like QuickTime's, and stay where they're put (between videos and launches). Double-click them to put them back above the caption
- Settings: Vine moved from Experimental to General, and the Experimental tab is gone
- Settings → Advanced → Appearance picks the sidebar and queue background: transparent glass or Aurora. Full screen is always Aurora

## 1.7 · 2026-10-11

- Phone view: the iPhone button in the player's controls swaps the window for a floating phone that plays the same queue the way the iPhone app does. Videos fill the screen, a two-finger swipe moves along the tape, a click plays or pauses, and the Up Next list slides up from the bottom. The laptop button on the phone brings the window back
- Drag the phone by its frame or anywhere along its status bar. Drag either bottom corner to resize it; it keeps its shape and remembers its size
- On a small phone the controls shrink with it, keeping their layout

## 2026-10-11 · Phone view: the Mac player's side buttons

- Phone view: the video's buttons (share, speed, Watch Later, bookmark, played) moved from the bottom into the Mac player's column of round buttons down the right, with Up Next, autoplay and Time Limit at its top. The top bar keeps the laptop button and the title

## 2026-10-13 · Even out short videos' volume, picture in picture

- Short videos (TikToks, Shorts, Vines) are evened out to the same loudness after they download, so a quiet one isn't drowned out by the loud one before it. Only the sound is rewritten; the picture is untouched. Videos already downloaded are done on the next download. Turn it off in Settings → Storage
- Long videos: a picture-in-picture button next to full screen floats the video over other apps; press it again (or the floating window's own button) to bring it back

## 2026-10-17 · Separate cookie browsers for TikTok and YouTube

- Settings → Advanced has a cookies picker for TikTok and another for YouTube, so each can read its sign-in from a different browser. YouTube starts out on whichever browser was already chosen

## 2026-10-17 · Open long videos in QuickTime Player

- Long videos: a button next to picture in picture opens the video in QuickTime Player, pausing it in Curated

## 1.8 · 2026-10-17

- Downloads keep a log, from the app and the overnight download alike: each creator's start and result, how long it took, and every error, with a summary at the end of each run of what was new and which creators failed and why
- Settings → Advanced → Download logging: Normal, Detailed (also what each listing found and yt-dlp's full error lines) or Debug (also every command run and all of its output). Show in Finder opens the log
- The window's minimum width depends on the screen: Creators & Downloads keeps room for its rows, and a short video with its queue hidden lets the window narrow to the video. The sidebar keeps a fixed width, so resizing only resizes what's beside it

## 2026-10-18 · Download progress in the sidebar; clear mode for long videos

- While a download runs, a bar above the sidebar's icons shows its progress, what it's doing and a Stop button, in the short and long sidebars alike
- Long videos: clear mode hides everything over the video (the caption, the buttons down the side and the controls) until you click it; then it all comes back for 3 seconds after the pointer last moves. It stays on from video to video until turned off
- Long videos' controls: Phone View, Open in QuickTime Player (a clear QuickTime Q), clear mode and picture in picture sit in a row under the scrubber, so the controls no longer overflow

## 2026-10-19 · More Aurora colors and a Holiday background

- The sidebar and queue background has a third choice, Holiday, beside Transparent Glass and Aurora. Aurora comes in Curated's colors (as before), Northern Lights, Ocean, Sunset, Forest or Blossom; Holiday in Halloween, Halloween 2, Thanksgiving or Christmas 1–3 colors. Each keeps its own pick
- In light mode the Aurora's colors are stronger and richer, so they don't wash out to pastel

## 2026-10-19 · A new Settings window; "watched" everywhere

- Settings is a sidebar of sections with colored icons: Downloads, Playback, Storage, Phone, Appearance and Advanced, each laid out as picture-led cards
- Downloads: the next and last download with a Download Now button; the daily schedule on one row; which platforms to check when Curated opens, as TikTok and YouTube Shorts cards; the TikTok and YouTube sign-in browsers side by side, with each browser's icon; and Classic Vines
- Playback: a round dial (and quick picks) for the Time Limit mix, and evening out short videos' volume
- Storage: what the videos take up, by kind; the folder; automatic cleanup; old and watched videos to delete, with how many and how much space; and Start Over: Delete the video library (every video and its download history to the Trash, keeping creators and settings) or Reset Curated (everything, including creators, history, paired phones and settings, after typing RESET; Curated starts again like new)
- Phone: sync's status at a glance, finding this Mac, USB sync, the address and paired phones
- Appearance: the background as preview cards and its colors as swatches. Advanced: yt-dlp and ffmpeg with their versions (and an Update button for yt-dlp), and logging
- New creators start with whatever keep setting the last one was added with, in place of a default in Settings
- Short videos are "watched" and "unwatched" too now, as long ones were: the mix tiles, creator counts, menus, the player and its tooltips

## 2026-10-19 · Holiday wordmarks

- Settings → Appearance → Holiday wordmarks swaps the sidebar's Curated wordmark (light and dark) for a holiday one through the season:
  - Halloween: October 1 – October 31
  - Thanksgiving: November 1 – Thanksgiving Day (the fourth Thursday of November)
  - Christmas: the day after Thanksgiving – January 5
- The long-video sidebar has its own holiday wordmarks too, with landscape cards. The rest of the year, and with the option off, each sidebar has its usual wordmark

## 2026-10-20 · Sidebar icons and Now Playing; when each kind last downloaded

- While a video is loaded and another screen is open, a Now Playing bar at the bottom of the sidebar shows the video playing live, with its creator and caption and previous, play/pause and next; clicking it goes back to the video. It replaces the one in Creators & Downloads
- The sidebar's icons are bigger, with new symbols: Creators & Downloads, phone sync (slashed and plain white while phones can't find this Mac) and Settings. The Creators & Downloads button toggles: from there it goes back to the video, or to where the sidebar was when nothing is playing
- Creators & Downloads grouped by category has bigger category names and icons
- Short | Long is a pill of both marks, the current one raised, in place of the other form's mark
- The sidebar's wordmark is bigger
- Creators & Downloads: the download bar's Short, Long and Vine show when each last downloaded beside their names ("32m ago", rounded to the hour past an hour and to the day past a day), and the line under the bar with the last result and the schedule is gone

## 2026-10-22 · Resolution and playlist menus update right away

- Creators & Downloads: changing a creator's long-video resolution, or how many of a playlist's newest videos to download, now shows the new choice straight away (it was saved, but the button kept showing the old one)

## 2.0 · 2026-10-30

- Creators & Downloads: the Long download button (and the download button of a creator with only long videos) first lists every new long video as a grid of thumbnails. Pick which to download, skip ones you don't want (they're marked watched and never downloaded), or leave them for later. The picker minimizes to the download bar while its download runs, and the Long button opens it again. The overnight download and Total still fetch everything
- The player's controls: a picture-in-picture button beside full screen, for short videos too (it was only for long videos, in the row under the scrubber)
- Phone View's button in the player's controls is a plain icon like the ones beside it, without a circle
- The Open in QuickTime Player button uses a standard symbol

## 2026-11-02 · Pick a resolution for each long video

- Long-video picker: each video has a resolution menu beside its creator and date. It starts at the creator's resolution, and picking another (Best, 1080p, 720p, 480p or 144p) applies to just that video. Changed ones are tinted, and still show their resolution while downloading

## 2026-11-02 · Suggested videos from your YouTube home feed

- Creators & Downloads: a Suggested button between Long and Vine in the download bar opens a picker of the long videos YouTube suggests on your home feed, read with the YouTube sign-in browser from Settings. Pick, skip (marked watched, never suggested again) or leave them, and choose each one's resolution, as in the Long picker
- A suggested video from a creator you follow (with long videos on) downloads with that creator's long videos; the rest go to a new Suggestions playlist, newest picks first, in the long sidebar's Playlists and on your phones
- Videos already downloaded, watched or skipped are left out of the suggestions

## 2.1 · 2026-11-02

- Suggested: pick from the long videos on your YouTube home feed; followed creators' ones go to their long videos, the rest to a Suggestions playlist
- Long-video picker: choose each video's resolution

## 2026-11-04 · Synced playback positions, several scheduled times, faster sync server

- Where you left off in a long video syncs with the phones and tablets (`POST /positions`, API 4). The newest change wins, and a paused player showing that video moves to a newer position
- Settings: the scheduled download can run at several times a day (Add a Time)
- The sync server uses plain sockets and `sendfile` instead of Network framework, whose send window held a real Wi-Fi link to 60-235 Mbps: about 350 Mbps over Wi-Fi and 600 over Ethernet to the same phone
- `/info` lists the Mac's addresses, wired first, so phones can find it by Bonjour and pick the wired one whatever its IP is

## 2026-11-04 · Now playing syncs between devices, more in the menus

- Long videos: the one last playing on any device is swapped with `/positions` (API 5). Switching to long videos, or a paused long player when a newer one arrives, loads it paused where it was left, instead of Latest starting by itself. Closing or finishing it clears it
- Playback menu: Playback Speed, Autoplay, Time Limit, Mark as Watched/Unwatched and Close Video, which stops the video and goes back to the launch screen with the queue still listed
- View menu: Show/Hide Queue, or a long video's Up Next panel. File menu: Share

## 2026-11-05 · Force Download from a phone, last download time

- Phones can start a total download on the Mac (`POST /download`, API 6). It doesn't start while a download is running or the long-video picker is open, and the phone is told why
- The manifest says when a download last finished (`lastDownloadAt`), from the app or the overnight job

## 2026-11-05 · Download progress for phones

- Phones can follow a download as it runs (`GET /download/progress`, API 7). The Mac closes the connection when the download ends

## 2026-11-05 · 1× only categories, Automix defaults

- Settings > Playback now has Short Videos and Long Videos groups, with Autoplay in each
- Each category can be left out of Automix by default, and set to 1× only. A 1× only category plays at normal speed with the speed button dimmed, and your chosen speed comes back on the next video
- Holding Automix starts from the checked categories, and a category's own Automix still plays it
- Long videos: playlists can be 1× only, and Back Up When Resuming starts a video 5, 10 or 30 seconds before where you left off
- These settings and the Time Limit are shared with your phones: the newest change on any device wins (`/positions`, API 8)

## 2026-11-05 · Pick older long videos

- Older Videos, in a long creator's gallery and its menu in Creators & Downloads, shows thumbnails of videos on their YouTube channel you haven't downloaded, watched or skipped, newest first, to pick some to download. It reads the channel's list once and shows 40 at a time; Load More reveals the next 40 straight away, and thumbnails only load as they come on screen
- Videos picked this way stay however old they are: long videos are never deleted for their age. They come first in Latest, Automix and the creator's gallery until you've watched them, on your phones too
- A hand-picked download no longer fails when YouTube's feed for that channel can't be read

## 2026-11-05 · Open a creator in YouTube or TikTok

- Right-clicking or holding a creator or playlist in the sidebar now offers Open in YouTube or Open in TikTok. Vine authors and the Suggestions playlist have no page, so they don't
- Videos a year old or more say how many years, not days

## 2026-11-05 · Add creators and pick older videos from a phone

- Phones can add a creator on the Mac, with the same options as Creators & Downloads. The Mac describes the form, checks what comes back and says how it went, down to the field (API 10)
- Phones can browse a creator's older long videos and send picks here to download. They come first until watched, as when picked here
- Thumbnails for this come through the Mac, so phones still never talk to YouTube

## 2026-11-07 · iPod exports

- Settings has a new iPod section, for an iPod nano (7th generation) or iPod classic (6th generation), each with its own picture
- Video Mix: pick a length and some categories, and Curated joins short videos (unwatched first) into one MP4 of about that length. For the nano it's 432×240, turned 270° as HandBrake does; for the classic, 320×560
- Long Videos: Select… lists your long videos by creator to pick one or more, and each becomes its own MP4 (432×240 for the nano, 560×320 for the classic)
- Every export is H.264 Baseline at about 700 kb/s with the iPod x264 settings, the source's own frame rate, and the iPod compatibility atom
- The export folder is checked whenever the section opens: if it's missing, it's outlined in red and Export stays off until you choose one
- While an export runs, its card, the top of the section and the sidebar show a spinner, the progress, the time left and a Stop button
- Exported videos are listed under a new iPod button beside Bookmarks in the sidebar, whose ⋯ menu has Mark All as Watched and Clear List

## 2026-11-10 · Original audio on YouTube

- YouTube downloads now keep the video's original audio. On channels YouTube auto-dubs, Curated could pick a dubbed track in another language (Russian, German, Arabic and others) because it ranked audio by bitrate alone
