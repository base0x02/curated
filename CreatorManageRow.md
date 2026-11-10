# `CreatorManageRow`

Source: [`Curated/Sources/Curated/ManageView.swift:409`](Curated/Sources/Curated/ManageView.swift#L409)

This is one row in the Creators & Downloads list. Each tracked creator, YouTube channel or playlist gets one. It shows status on the left and the creator's per-creator download settings on the right.

## Inputs

```swift
@Environment(AppModel.self) private var model   // all state and mutations go through here
let library: CreatorLibrary                     // the creator plus their downloaded videos
let onRemove: () -> Void                        // the parent shows the confirmation
```

The parent list creates it in two places: the grouped-by-category layout (`ManageView.swift:128`) and the flat layout (`ManageView.swift:139`). In both, `onRemove` just sets `removing = lib`, and the parent then asks you to confirm. The row never deletes anything itself.

The row stores no state of its own. Every control is a `Binding` whose `get` reads from `creator` and whose `set` calls an `AppModel` setter (`setForms`, `setKeep`, `setMinViews`, `setCategory`, …). A change saves through the model, the model publishes it, and the row redraws.

## Layout, left to right

| # | Element | Notes |
|---|---|---|
| 1 | **Platform icon** (`:420`) | A `PlatformIcon`, or a `FormMark` for a YouTube playlist. Fixed at 26pt wide. |
| 2 | **Avatar** (`:428`) | 40pt. |
| 3 | **Name column** (`:431`) | Display name, with `@handle` under it. The handle is hidden when there's no nickname, for playlists, and for YouTube channels added by `UC…` ID, since that ID isn't a real handle. Fixed at 150pt. |
| 4 | **Stats column** (`:441`) | Three caption lines: `countsText`, `waitingText` and `checkedText` (see below). Flexible width, at least 150pt. Hovering shows the last error. |
| 5 | **Shorts / long-form toggles** (`:451`) | `VideoFormToggles`. Only for YouTube channels, not playlists. |
| 6 | **Resolution picker** (`:464`) | Only shown when long-form downloads are on. |
| 7 | **Keep rule** (`:474`) | `KeepButton` sets how many days or videos to keep. For playlists it's `PlaylistLimitPicker` instead, which sets how many of the newest videos to download, because a playlist has no day window. |
| 8 | **Min views** (`:484`) | `MinViewsPicker`. |
| 9 | **Category** (`:485`) | Only shown if any categories exist. Playlists get a dimmed fixed glyph because they always belong to Playlists. |
| 10 | **Download status** (`:495`) | Shows a spinner while downloading, a clock while queued, and a "Download now" button when idle. The button is disabled while any download is running. |
| 11 | **⋯ menu** (`:512`) | Show in Finder (plus the long-videos folder when long-form is on), Open on {platform}, mark-all items, a "Trim to N Unwatched" item when the creator keeps a fixed number of videos and some are over the limit, and Remove…. |

### Fixed-width slots keep the columns aligned

Columns 5 and 6 are always there. They're a `ZStack { Color.clear; if … { control } }` with a fixed frame. A TikTok creator has no form toggles, but its later controls still line up with the YouTube rows. The comment at `:462` explains why it's `Color.clear` and not an empty `Group`: an empty `Group` collapses to zero width.

The download button and the ⋯ menu share `RowControl.height` and `RowControl.iconSize`, so they render at the same size. The menu uses `.buttonStyle(.plain)` and `.menuIndicator(.hidden)` because the default menu style draws its icon at a small fixed size.

## The computed text

- **`countsText`** (`:551`): for example `"3 unplayed of 12 · long: 2 unplayed of 5"`. Each part only appears if that form is downloaded. Playlists say "unwatched" and drop the "long:" prefix.
- **`waitingText`** (`:562`): for example `"12 under 500K views"`. It only appears when a min-views filter is set and the last check skipped some videos for being under it.
- **`checkedText`** (`:569`): for example `"checked 13 hours ago, 0 new"`, or `"never downloaded"`. Any error is appended. It's **orange** if some new videos still downloaded (a partial failure) and **red** if none did. It's built by joining `Text` values with `+` so the two parts can have different colours on one line.

## Data sources at a glance

- `creator` / `library`: the creator's settings and video list
- `model.runState.creators[id]`: results of the last check (date, new count, error, how many were under the views threshold)
- `model.statuses[id]`: live download state (idle, queued or downloading)
- `model.library(for:form: .long)`: the separate library holding a creator's long-form videos
