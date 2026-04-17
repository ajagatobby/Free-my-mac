# FreeUp

A fast, minimal macOS disk cleaner. Finds reclaimable space — caches, logs,
developer junk, duplicates — and removes it with a single keystroke.

Built with SwiftUI + Swift 6 strict concurrency. Inter for UI, SF Mono for
every number.

---

## Highlights

- **Scans a full Mac in seconds.** A BSD `fts(3)` walker, bulk metadata via
  `getattrlistbulk`, and parallel subtree traversal per top-level child.
- **Duplicate detection that doesn't read every byte twice.** Size-grouped →
  head + tail + size-salt partial hash → full SHA-256 only on survivors.
- **Deletes what it can, prompts for the rest.** Regular files go through
  `FileManager.trashItem` silently; root-owned system files trigger **one**
  native admin prompt via `osascript` with a whitelisted `xargs rm`.
- **Clone- and snapshot-aware.** Detects APFS clones (so cleaning a clone
  doesn't reclaim what you think) and warns if local Time Machine snapshots
  are holding reclaimable bytes hostage.
- **Keyboard first.** `⌘R` scans, `⏎` confirms, `⌘A` selects all, `⎋`
  cancels. Shortcut pills are rendered inline so the model is discoverable.

---

## Requirements

- macOS 14 (Sonoma) or later
- Xcode 16 or later
- Full Disk Access granted to the app (prompted on first launch)

---

## Installation

### From source

```bash
git clone https://github.com/ajagatobby/FreeUp.git
cd FreeUp
open FreeUp.xcodeproj
```

Press `⌘R` in Xcode to build and run. The first launch will prompt you to
grant Full Disk Access in **System Settings → Privacy & Security → Full Disk
Access**. Without it, scans of `~/Library` and `/Library` will be skipped.

### Release build

```bash
xcodebuild -project FreeUp.xcodeproj \
           -scheme FreeUp \
           -configuration Release \
           -destination 'platform=macOS' \
           build
```

The resulting `.app` lands in Xcode's DerivedData directory; drag it into
`/Applications`.

---

## How scanning works

FreeUp runs one of four scanners depending on the target. `ScanViewModel`
routes between them.

| Scanner              | When it runs                               | Core technique                                    |
| -------------------- | ------------------------------------------ | ------------------------------------------------- |
| **SmartScanner**     | Default — known-junk roots only            | `fts_open` + `FTS_PHYSICAL \| FTS_NOCHDIR`        |
| **UltraScanner**     | Custom folder (when BSD APIs are viable)   | `getattrlistbulk` bulk metadata, `fts` fallback   |
| **TurboScanner**     | Custom folder (fallback path)              | `FileManager.enumerator` with pre-fetched keys    |
| **ScannerService**   | Legacy / defensive fallback                | Standard `FileManager` enumeration                |

Heavy targets (`DerivedData`, `iOS DeviceSupport`, Simulators, `Caches`, npm /
gradle / cocoapods) are fanned out per immediate child directory through a
`TaskGroup` so subtrees scan in parallel. Loose files at the root are
`lstat`'d in their own task so nothing is dropped.

Progress is streamed to the view via `AsyncStream<ScanResult>` and throttled
to >1% deltas to keep the UI calm.

---

## How deletion works

`DeletionService` splits every batch by whether the current user can delete
the file without elevation. The test is `access(parent, W_OK | X_OK)`.

- **User-writable files** go through a parallel `FileManager.trashItem`
  `TaskGroup` (capped at 16 concurrent). No Apple Events, no Finder IPC, real
  per-file error codes. If the first 8 consecutive results come back with
  `permissionDenied`, the whole batch aborts and the UI opens the Full Disk
  Access walkthrough.
- **Root-owned files** (e.g. `/Library/Logs/DiagnosticReports/*`, `/var/log`)
  are NUL-delimited into a temp file and fed to a single `do shell script "..."
  with administrator privileges` invocation running `xargs -0 rm -rf`. That
  produces **one** macOS password prompt for the entire batch.
- Paths are validated against a whitelist of known reclaimable roots before
  any privileged operation. Arbitrary paths are refused elevation.

Default mode is **permanent delete** — moving cache junk to the Trash defeats
the point. Users can switch to **Move to Trash** in Settings.

---

## How duplicate detection works

The pipeline is three passes, each pass filtering candidates for the next:

1. **Group by size.** Files of different sizes are instantly ruled out.
2. **Partial hash** — 4 KB from the head + 4 KB from the tail + file-size
   salt, SHA-256'd together. Ruthlessly eliminates container formats and
   compiled binaries that share an identical header but differ later.
3. **Full SHA-256** — only on files that survived the partial hash. Streaming
   reader, 1 MB chunks.

Partial hashing runs at 32-way concurrency (4 KB reads are cheap); full
hashing runs at `ProcessInfo.activeProcessorCount`, capped to 16 to match
typical SSD queue depth.

The UI shows a **Keep** badge on the file that will be preserved — always
the first file by sorted path order. "Auto-select" marks every copy _except_
that keeper.

---

## Architecture

```
FreeUp/
├── Models/
│   ├── FileCategory.swift        # The canonical categories + categorize()
│   ├── ScannedItem.swift         # ScannedFileInfo + ScanResult + VolumeInfo
│   └── ScanSession.swift
├── Services/
│   ├── APFSService.swift         # Clone / snapshot detection (tmutil)
│   ├── DeletionService.swift     # Trash / permanent / admin-elevated paths
│   ├── DuplicateDetectionService.swift
│   ├── PermissionService.swift   # FDA probing, security-scoped bookmarks
│   ├── ScannerService.swift      # Fallback enumerator scanner
│   ├── SmartScannerService.swift # Primary scanner (fts + parallel subtrees)
│   ├── TurboScannerService.swift # Custom-dir fallback (enumerator)
│   └── UltraScannerService.swift # Custom-dir BSD (getattrlistbulk + fts)
├── ViewModels/
│   └── ScanViewModel.swift       # @Observable, drives the whole UI
├── Views/
│   ├── DashboardView.swift       # Custom sidebar + overview + CommandBar
│   ├── CategoryDetailView.swift  # Per-category file list with skeleton
│   ├── DuplicatesView.swift
│   ├── PermissionsView.swift     # FDA walkthrough sheet
│   ├── ScanProgressView.swift
│   └── Components/
│       ├── CategoryCard.swift    # SidebarCategoryRow
│       ├── FileRowView.swift
│       └── StorageBar.swift      # 3-segment disk gauge
├── Utilities/
│   ├── ByteFormatter.swift
│   ├── FontLoader.swift          # Registers bundled Inter at launch
│   ├── Theme.swift               # FUColors, FUFont, IconSquare, KBDPill...
│   └── WindowAccessor.swift      # NSWindow bridges (fullscreen, vibrancy)
├── Resources/
│   └── Fonts/                    # Inter Regular / Medium / SemiBold / Bold
├── FreeUpApp.swift
└── Info.plist
```

The view layer only reads `ScanViewModel`; services talk only to the model
layer. Swapping a scanner is a one-line change in `ScanViewModel.startScan`.

---

## Design system

A single accent color. Numerics use tabular SF Mono everywhere — counts,
sizes, keyboard glyphs. UI text uses Inter, bundled with the app (registered
via `ATSApplicationFontsPath` and a runtime `CTFontManager` pass in
`FontLoader`).

Reusable primitives in `Theme.swift`:

| Primitive          | Purpose                                                       |
| ------------------ | ------------------------------------------------------------- |
| `IconSquare`       | Tinted rounded square with monochrome glyph (category identity) |
| `KBDPill`          | Small monospaced keyboard-shortcut badge                      |
| `KBDAction`        | `Label ⏎` pair for the CommandBar                             |
| `CommandBar`       | Persistent bottom bar: leading status, trailing action hints  |
| `Hairline`         | 1px separator tuned for solid + translucent backgrounds       |
| `SkeletonBlock`    | Shimmering placeholder with a staggerable phase               |

Windows use `.windowStyle(.hiddenTitleBar)` with traffic lights overlaying
the sidebar's top padding. Full-screen is disabled via `disableFullScreen()`
(sets `.fullScreenNone` on the `NSWindow.collectionBehavior`).

---

## Keyboard shortcuts

| Shortcut  | Action                               |
| --------- | ------------------------------------ |
| `⌘R`      | Scan / rescan                        |
| `⌘.`      | Cancel scan                          |
| `⌘O`      | Scan a custom folder                 |
| `⌘A`      | Select all / deselect all            |
| `⌘D`      | Deselect all                         |
| `⏎`       | Confirm the primary action           |
| `⎋`       | Cancel the active sheet              |
| `⌘,`      | Open Settings                        |

---

## Development

Swift 6 strict concurrency is enabled (`SWIFT_DEFAULT_ACTOR_ISOLATION =
MainActor`). If you add a type that will be used off-actor, mark its
initializers and any `Equatable` conformance `nonisolated` — see
`DeletionError` for the pattern.

Every view file has a one-to-one correspondence with a section on screen —
no god-views. Services are actors; view models are `@MainActor @Observable`.

```bash
# Parse-check without a full build
swift -frontend -parse -target arm64-apple-macos14 FreeUp/**/*.swift

# Full debug build
xcodebuild -project FreeUp.xcodeproj -scheme FreeUp \
           -configuration Debug -destination 'platform=macOS' build
```

---

## Contributing

Pull requests welcome. Please keep the design language (Inter, SF Mono,
neutral palette, icon squares for identity) consistent. If you add a new
scanner, route it through `ScanViewModel.startScan` and emit
`AsyncStream<ScanResult>` like the others.

Before submitting, run the build; parse-only checks miss cross-file type
errors and strict-concurrency diagnostics.

---

## License

MIT. See `LICENSE` in the repository root.
