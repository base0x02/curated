# Curated

Watch the TikTok creators you chose, not the ones an algorithm chose for you.

Curated downloads recent videos from a list of creators you pick, on a schedule (overnight by default), and plays them in a plain Mac window with no feed and no recommendations. When the queue ends, it stops.

## Requirements

- macOS 14 or later
- `brew install yt-dlp ffmpeg` (keep yt-dlp current with `brew upgrade yt-dlp`, since TikTok changes often)
- Xcode Command Line Tools to build (`xcode-select --install`)

## Build

```sh
./build.sh            # builds ./Curated.app
./build.sh --install  # also copies it to ~/Applications
```

## How it works

- **Creators & Downloads** is where you add a creator (`@name` or profile link) and choose how many recent days to keep. **Download All Now** runs immediately.
- **Automatic downloads** run from a LaunchAgent (`~/Library/LaunchAgents/local.curated.download.plist`), so they work even when the app is closed. If your Mac is asleep at that time, the download runs when it wakes. You set the time in Settings (⌘,).
- **Watching**: click a creator to see their videos, newest first. Playback moves to the next video automatically. Use ⌘→ to skip and ⌘← to go back.
- **Automix** starts with a random creator, then rotates through all the others, playing each creator's unplayed videos newest first.
- **Top 15** plays your 15 most-viewed unplayed videos, then stops with a reminder to go outside. View counts are refreshed on every download. If some videos have no view count, the list is filled Automix-style instead.
- **Categories** (optional): on the Creators page, click **New Category** (e.g. "News"), then pick a category from the menu on each creator's row. Each category gets its own sidebar section with "{Name} Automix", "{Name} Top 5", and its creators. The main Automix and Top 15 still draw from everyone. Each category has an icon you pick from a grid of built-in Mac icons (SF Symbols). Its sidebar section shows a count of unplayed videos and can be collapsed. Deleting a category keeps its creators and their videos. With no categories, the sidebar is unchanged.
- **Sidebar footer**: three icons at the bottom of the sidebar. The clipboard icon opens Creators & Downloads, ▶︎ goes to the Now Playing video in its queue, and the gear opens Settings. When a video is loaded, Creators & Downloads also shows a Now Playing bar with play/pause and **Go to Video**.
- **Played**: a video is marked Played as soon as it starts, even if you don't finish it. Automix never plays Played videos. In a creator's tab you can still click a played video to rewatch it, but auto-advance and Skip only go to unplayed videos. Right-click a video, or use the circle button under the player, to switch it between Played and Unplayed. To mark all of a creator's videos Played or Unplayed at once, use the **Mark All** menu in the creator's tab, right-click the creator in the sidebar, or use the ⋯ menu on the Creators page.

Files are stored in:

| What | Where |
|---|---|
| Videos | `~/Movies/Curated/<username>/` (changeable in Settings) |
| Config, run state, played list | `~/Library/Application Support/Curated/` |
| Scheduled run log | `~/Library/Application Support/Curated/logs/scheduled.log` |

To keep downloads quick, Curated reads the profile's video list (which includes post dates) and stops as soon as it's past the date window. It then downloads only the new videos in range. Photo slideshow posts are skipped.

## Uninstall

Turn off automatic downloads in Settings (this removes the LaunchAgent), then delete the app, `~/Library/Application Support/Curated`, and your video folder.
