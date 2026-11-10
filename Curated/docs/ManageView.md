# ManageView.swift: a guide for editing it

`Sources/Curated/ManageView.swift` holds the **Creators & Downloads** screen, which is where you add creators, change their settings and start downloads. It's a single file of about 1,550 lines, but it's really about 20 small SwiftUI views stacked together. This guide shows what each one draws and where to find it.

Line numbers were correct when this was written. Search for the `struct` name if they've moved.

---

## 1. What's on screen, and which code draws it

```
┌──────────────────────────────────────────────────────────────────────────────┐
│ Toolbar:  [Search creators…]                                    [Sort ⇅]     │ ← .searchable + .toolbar   (ManageView.body)
├──────────────────────────────────────────────────────────────────────────────┤
│ [TT][YT] [▯][▭]  [ @username or link…           ] [Keep 3] [🏷] [Add Creator]│ ← addBar
│ (red error text, if adding failed)                                           │
├──────────────────────────────────────────────────────────────────────────────┤
│ (News 4) (Comedy 7) (No Category 2) (Playlists 1)          (▭) (▤) (+) (⚙)   │ ← CategoryBar
├──────────────────────────────────────────────────────────────────────────────┤
│ [V] (avatar) Vine        12 unplayed of 40 · 9 creators   [Keep 25▾]  ⬇  ⋯  │ ← VineManageRow (only if Vine is on)
│ [TT](avatar) Name        3 unplayed of 12                                    │
│    @handle     checked 2 hours ago, 1 new  [▯▭] [1080p] [⏱3] [5K+] [🏷] ⬇ ⋯ │ ← CreatorManageRow (one per creator)
│ …                                                                            │
├──────────────────────────────────────────────────────────────────────────────┤
│ (thumb) Now Playing · Name   caption…                   [▶] [Go to Video]   │ ← NowPlayingBar (only while a video is loaded)
├━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┤ ← Divider + DownloadProgressLine
│ [short] Short ⬇ │ [long] Long ⬇ │ [vine] Vine ⬇ │ [all] Total ⬇               │ ← downloadBar → downloadSection(…) ×3–4
│ Next automatic download tomorrow at 3:00 AM · last run 9 hours ago           │    (or [Stop] + progress text while downloading)
└──────────────────────────────────────────────────────────────────────────────┘
```

## 2. How the views nest

The tree below shows which view contains which, using the type names from the code. Indentation means "is inside".

```
ContentView (ContentView.swift:380)       ← shows ManageView when "Creators & Downloads" is picked in the sidebar
└── ManageView                            (line 4)
    └── VStack(spacing: 0)                (body, line 91)
        ├── addBar                        (line 187)  computed property, not its own struct
        │   ├── PlatformIcon buttons      TikTok / YouTube picker
        │   ├── VideoFormToggles          (line 1400) only for YouTube, not playlists
        │   ├── TextField                 the username/link box
        │   ├── PlaylistLimitPicker       (line 688)  for a playlist link…
        │   │   └─ or KeepButton          (line 766)  …otherwise
        │   ├── CategoryButton            (line 919)  only if categories exist
        │   └── "Add Creator" button      → add()
        ├── CategoryBar                   (line 1003) its own struct with its own @State
        │   ├── pills(showNames:)         category filter pills, inside a ViewThatFits
        │   │   ├── pill(…)               normal mode
        │   │   └── editablePill(…)       edit mode (wiggle with Wiggle, drag to reorder)
        │   ├── long-only toggle, group toggle, + (new), ⚙ (edit)
        │   ├── .sheet → CategoryEditor   (line 1302) new/edit category window
        │   └── .confirmationDialog       delete category
        ├── Divider
        ├── ONE of these (an if/else chain):
        │   ├── ContentUnavailableView    "No creators yet", "No results", etc.
        │   ├── List (grouped)            Section per category → CreatorManageRow
        │   └── List (flat)               VineManageRow? + CreatorManageRow ×N
        ├── NowPlayingBar                 (line 1364) only if showNowPlaying != nil
        ├── Divider + DownloadProgressLine (line 1488)
        └── downloadBar                   (line 251)
            └── downloadSection(…) ×N     (line 307) Short / Long / Vine / Total

CreatorManageRow (line 409), one HStack laid out left to right:
    platform icon │ AvatarView │ name/@handle (150pt wide) │ counts + "checked…" (flexible)
    │ VideoFormToggles slot │ ResolutionPicker slot │ KeepButton or PlaylistLimitPicker
    │ MinViewsPicker │ CategoryButton │ download button / spinner │ ⋯ Menu

VineManageRow (line 582) uses the same layout but has fewer controls.
```

### Shared building blocks (also in this file)

| View | Line | What it is |
|---|---|---|
| `StepSquircle` | 731 | A generic rounded-square button. Click steps forward, ⌥-click steps back, right-click opens a menu. It's the base for `ResolutionPicker` and `MinViewsPicker`. |
| `ResolutionPicker` | 672 | "Best / 1080p / …", for long videos |
| `MinViewsPicker` | 709 | "All / 5K+ / … / 1M+" |
| `KeepButton` + `KeepOptions` | 766, 818 | The "Keep" squircle and the popover that edits a `KeepRule` (keep by days, or by count) |
| `PlaylistLimitPicker` | 688 | "All videos / Newest N" |
| `CategoryButton`, `CategoryGlyph`, `CategoryChooser` | 919, 940, 959 | The category squircle, its icon, and the popover grid of categories |
| `VideoFormToggles`, `VideoFormGlyph` | 1400, 1433 | The red portrait/landscape "Shorts / Long" toggles |
| `RowControl` | 913 | **Shared sizes** (`height = 30`, `iconSize = 26`) for every button on a row |
| `DownloadLogView` | 1458 | Not on this screen. It's the separate "Download Log" window (opened from `CuratedApp.swift:55`). |
| `confirmTrim(_:)` | 1525 | A plain function that shows an `NSAlert` before trimming videos |
| `CreatorFilter`, `CreatorSort` | 389, 394 | Enums for the category filter and the sort menu |

### Views used here but defined in `ContentView.swift`

`AvatarView` (1612), `PlatformIcon` (1647), `ThumbnailView` (1718), `FormMark` (1818), `MarkAllMenuItems` (720), `formatLength` (893). `VineLogo` is in `Vine.swift`.

---

## 3. Where the data comes from

The screen draws its data from three sources:

1. **`@Environment(AppModel.self) private var model`**: the app's shared state (`AppModel.swift`). Everything real comes from here: `model.libraries`, `model.config.creators`, `model.categories`, `model.statuses`, `model.isDownloading`, `model.runState`… The views **read** `model` and **call methods** on it to make changes (`model.addCreator`, `model.setKeep`, `model.setCategory`, `model.download`, `model.removeCreator`…). Because `AppModel` is `@Observable`, the screen redraws itself automatically when the data changes.

2. **`@State`**: temporary UI state owned by the view. In `ManageView` (lines 8–24) it covers what's typed in the add bar (`newUsername`, `chosenPlatform`, `newKeep`, …), the search text, which creator is waiting on the "Remove?" dialog (`removing`), and the current filter. It isn't saved anywhere.

3. **`@AppStorage`**: small UI preferences saved in UserDefaults that survive relaunches. Here that's `creatorSort` (`sort`) and `groupCreatorsByCategory` (`grouped`). `CategoryBar` reads the same `groupCreatorsByCategory` key, so its toggle button and ManageView's list stay in sync.

**`@Binding`** is how a parent hands a piece of its state to a child to edit. For example, `CategoryBar(filter: $filter, …)` lets the bar change ManageView's `filter`. Many rows build a binding on the spot, like this:

```swift
Binding(get: { creator.minViews }, set: { model.setMinViews($0, for: id) })
```

Reading the value comes straight from the creator, and setting it calls the model method that saves to `config.json`.

### How the list is filtered and sorted

```
model.libraries
   → shownLibraries   (line 29)  filter by category pill, long-only, and search text
   → sorted(_:)       (line 60)  apply the Sort menu
   → groups           (line 48)  (only when "group by category" is on) split into sections
```

To change *which* creators show up, edit `shownLibraries`. To change their *order*, edit `sorted(_:)` and the `CreatorSort` enum.

---

## 4. Recipes: how to make common changes

**Add a new control to every creator row**
1. Find `CreatorManageRow.body` (line 418). The row is one `HStack`, so controls appear in the order they're written.
2. Add your view where you want it. Use `RowControl.height` for its height so it matches the others.
3. If it changes a creator setting, add a `setX(_:for:)` method to `AppModel` (copy `setMinViews`) and a field on `Creator` in `Models.swift`. The field must be optional or have a default, so config files saved by older builds keep loading.
4. If the control only shows up on some rows, wrap it in a fixed-width slot (`ZStack { Color.clear; if … { … } }.frame(width:)`) like the resolution slot at line 464. Otherwise the columns won't line up from row to row.

**Add an item to a row's ⋯ menu**: add a `Button` inside the `Menu { … }` at line 512.

**Add a new sort order**: add a case to `CreatorSort` (line 394), give it a `label`, and handle it in `sorted(_:)` (line 60). The toolbar picker lists it automatically.

**Change the add bar**: edit `addBar` (line 187). New form fields need a `@State` at the top of `ManageView`, need passing into `model.addCreator` in `add()` (line 365), and need resetting in `add()` after a successful add.

**Change the download bar**: edit `downloadBar` (line 251). Each section is a `downloadSection(…)` call, so adding a section means one more call plus a `Divider().frame(height: 44)` between sections.

**Change spacing or sizes**: most layout numbers are in the code itself: `HStack(spacing: 12)`, `.padding(12)`, `.frame(width: 150)`. Shared sizes are constants: `RowControl`, `KeepButton.width`, `MinViewsPicker.width`, `ResolutionPicker.width`, `VideoFormToggles.width`.

**Change the empty-list messages**: edit the `ContentUnavailableView` branches in `body` (lines 96–114).

---

## 5. SwiftUI patterns this file uses (and why)

- **Computed properties as sub-views** (`addBar`, `downloadBar`): these split `body` into readable pieces without making a new struct. They can use the parent's `@State` directly.
- **Separate `struct`s** (`CategoryBar`, `CreatorManageRow`): used when a piece needs its **own** `@State` (for example CategoryBar's drag state) or is repeated (one row per creator).
- **One dialog for the whole list** (line 155): the "Remove?" `confirmationDialog` sits on `ManageView`, not on each row. A row calls `onRemove`, which sets `removing = lib`. Rows redraw constantly during downloads, which would make per-row dialogs flicker.
- **`.help("…")`**: the tooltip shown on hover. Nearly every control has one, so keep adding them.
- **`.contentShape(…)`**: makes the whole frame clickable, not just the icon's pixels.
- **`.fixedSize()`**: stops a picker or menu from stretching or squashing.
- **`ViewThatFits`** (CategoryBar, line 1029): tries the pills with names, then icons only, then a scrolling row, and uses the first that fits.
- **`AnyShapeStyle(…)`**: needed whenever a `? :` picks between two *different* style types (for example `Color.accentColor` vs `.quaternary`).

## 6. Trying out your changes safely

Don't test against your real library. Run a debug build with a scratch data folder, as "Testing without touching real data" in `dev-readme.md` at the top of the repo describes. Add `CURATED_TEST_SELECT=manage` to open straight onto this screen.

Before the first run, put a `config.json` in the scratch folder whose `settings` has `"libraryPath"` set to a scratch folder too (plus `"syncEnabled": true`). Without it, the app uses its default library folder, `~/Movies/Curated`, which is your real one.

```sh
swift build && CURATED_DATA_DIR=/tmp/curated-test CURATED_SYNC_PORT=18765 \
  CURATED_TEST_SELECT=manage .build/debug/Curated
```
