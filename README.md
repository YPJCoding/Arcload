# Arcload

Arcload is a lightweight native download manager for macOS, built with SwiftUI and powered by the pinned **aria2-next 2.8.6** engine.

It is designed for a focused macOS experience: fast HTTP/HTTPS downloads, native task management, a compact menu bar presence, and a small application footprint.

## Features

- Native SwiftUI interface for macOS
- HTTP/HTTPS file downloads powered by aria2-next (including HTTP/2 when negotiated)
- Multiline link input with validation, duplicate removal, per-link results, and retry of failed submissions
- Adaptive range downloads with a configurable per-task connection ceiling
- Configurable concurrent downloads, overall download speed limit and per-task download speed limit
- Pause and resume individual tasks, selected tasks, or all tasks
- Native Command-click and Shift-click multi-selection
- Batch removal and batch file deletion
- Copy source links in any task state, including ordered, deduplicated multi-selection
- Re-download completed or failed tasks without removing old records or overwriting existing files
- Completed and failed download history retained across application restarts
- Opt-in macOS notifications for newly completed or failed downloads, with permission status and a test notification
- Double-click completed tasks to open downloaded files
- Reveal downloaded files in Finder
- Menu bar progress indicator with a brief completion checkmark
- Automatic aria2 process recovery
- Launch at login support
- Automatic prevention of idle system sleep while downloads are active
- Configurable local aria2 RPC port and secret

### Adding multiple downloads

Paste one HTTP/HTTPS link per line in the New Download window. Blank lines and duplicate links are ignored; invalid lines are listed separately. Press Command-Return to submit valid links. Partial failures stay in the window and can be retried without resubmitting successful links.

If a request times out, aria2 may already have accepted it. Check the task list before retrying to avoid duplicate downloads. Submissions require a ready engine; this is not a durable offline queue.

### Sidebar categories

The sidebar shows All, In Progress (downloading and waiting), Paused, Completed, and Failed. Each category displays its full task count, including retained history; searching only filters the list and does not change these counts.

### List sorting

Click File Name or Size to cycle through ascending, descending, and default incoming order. Clicking another sortable column starts in ascending order. The native sort arrow disappears in default order, and header tooltips describe the next click. File names use natural sorting (file2 before file10), and sizes use numeric bytes matching the displayed size (downloaded bytes when the total is unknown). Only the active column sorts, with ties retaining incoming order. Other columns are not sortable. The third click clears sorting without clearing search, changing category, or dropping selected tasks; no separate restore button is needed. Sorting is applied after category/search filtering, survives polling within the window, and does not change the aria2 queue or selected task identities. A new window session starts in the original task order.

### Toolbar action scope

With no task selected, Pause All and Resume All apply to eligible tasks across all categories, including tasks hidden by search. With a selection, the buttons become Pause Selected and Resume Selected; only eligible selected tasks are affected. The window subtitle shows the selection count. Selecting only completed or failed tasks disables pause/resume instead of falling back to a global action. Remove Selected and Delete Selected Files always require a selection. Explicit global and selected actions also remain available in the Download menu.

### Task context menu

Copy Download Link is available in every state when the source is known. Multiple selected links are copied one per line in displayed order, with duplicates removed. Completed and failed tasks also offer Re-download; a mixed selection submits only eligible tasks. The original records and files remain, and aria2 automatically renames conflicting files instead of resuming or overwriting them. Requests preserve the source, destination and supported transfer options; unknown sources disable the action. Older history falls back to its recorded destination. Authentication headers, passwords and proxy credentials are not archived for replay. Signed source URLs may contain sensitive tokens: copy and share them carefully. If submission times out, check the list before retrying.

### Menu bar

While downloading, the menu bar displays the same circular pie fill as the task list. Its progress is the arithmetic mean of downloading tasks, without weighting by file size; waiting, paused, completed and failed tasks are excluded. A task leaving the active set can change the average in either direction.

When all tasks in the last active set reach the completed state, the icon displays `checkmark.circle.fill` for one second, then returns to `arrow.down.circle.fill`. A new active download immediately restores the pie. A displayed percentage of 100% alone does not trigger the checkmark; pause, failure, removal and retained history do not trigger it either.

The menu bar item occupies 26 points horizontally and uses 17-point icons. Its height is managed by macOS. The menu provides Show Window, Settings and Quit.

### Download notifications

Notifications are off by default. Enable them in Settings → General → Notifications to request macOS permission. If permission is denied, the panel provides a System Settings link; returning to the app refreshes permission without prompting again. A test notification is available when permission is granted. Foreground notifications are also supported; Focus and system banner/sound preferences can still suppress presentation.

Only newly observed live-to-terminal transitions, or confirmed submissions made by Arcload, generate notifications. Existing completed/failed rows are treated as a baseline and do not produce historical notifications; events observed while disabled are not replayed on enable. Polling does not repeat the same completion/failure notification. Fast submissions are tracked even if they finish before the next active snapshot. For externally submitted tasks that finish before Arcload ever observes them, the app cannot reliably distinguish new work from old stopped results and does not notify. Notifications show the filename, not the source URL, full path, or raw server error. Delivery errors remain visible in the notification settings. Closing the app does not change the saved opt-in choice.

### Preventing sleep during downloads

Arcload automatically holds one `PreventUserIdleSystemSleep` assertion while a running engine reports at least one downloading task; there is no setting or opt-in requirement. It does not keep the display awake or override lid-close, manual sleep, or critical-battery policies. Searching, changing category, or hiding the main window does not affect the assertion. Waiting/paused tasks and retained history do not activate it; it is released after the engine reports no active downloads, on engine recovery/failure/stop, and on app termination. Optimistic resume UI changes alone do not acquire it. A fresh engine snapshot must confirm active work after startup or recovery. The sidebar footer identifies aria2-next and its live status; its tooltip shows the bundled version and any sleep-assertion error.

### Download history

Completed and failed tasks are saved as soon as Arcload observes their terminal state. On startup, local history is merged with aria2's current results without duplicate rows, and remains visible under All and the Completed or Failed category even when aria2 no longer returns it. Missing or moved files do not erase history; file actions are disabled when the file is unavailable.

History is stored in `~/Library/Application Support/Arcload/history.sqlite3` (SQLite/WAL). Removing a task also removes its history, but does not delete the downloaded file unless explicitly requested. Read/write errors are surfaced; unreadable databases are not replaced with empty history. This is terminal-task history, not an offline submission queue or a replacement for aria2 session recovery. Lost records cannot be reconstructed, and a completion that the app never observed cannot be guaranteed to appear.

## Requirements

- macOS 26 or later
- Apple Silicon (arm64)

## Download

Prebuilt releases are distributed as DMG images:

```text
Arcload-<version>-macos.dmg
```

Drag `Arcload.app` from the mounted DMG into Applications.

## Build from source

Requirements:

- Swift 6.2 or later
- macOS 26 SDK
- Apple command-line developer tools

Build and validate:

```sh
make validate
make test
make build
```

The assembled application is written to:

```text
build/Arcload.app
```

Launch the local build with:

```sh
make run
```

### Toolchain troubleshooting

Errors mentioning missing `SwiftUIMacros.StateMacro` or `TestingMacros.TestDeclarationMacro` indicate an SDK or macro-plugin discovery problem. Use a matching SDK/toolchain installation. For Apple Command Line Tools installations containing the macOS 26.5 SDK and Testing plugins, the following configuration is verified:

```sh
export SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
TESTING_PLUGIN='/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing#/Library/Developer/CommandLineTools/usr/bin/swift-plugin-server'

make validate
swift test --arch arm64 --sdk "$SDKROOT" \
  -Xswiftc -external-plugin-path -Xswiftc "$TESTING_PLUGIN"
swift run --arch arm64 --sdk "$SDKROOT" SmokeTests
make build
```

These paths are specific to Command Line Tools; Xcode installations have a different toolchain layout. Selecting the SDK does not change the application's macOS 26 deployment requirement.

## Configuration

Settings use three compact top tabs: **General** (launch at login and notifications), **Downloads** (destination, task concurrency/connections/range limits and speed limits), and **Connection** (RPC port/secret and HTTPS certificate verification). Switching tabs masks a revealed RPC secret. About is a separate panel; automatic sleep prevention requires no setting.

The settings toolbar colors follow the system appearance:

| Appearance | Background | Bottom separator |
| --- | --- | --- |
| Dark | `#33312E` | `#4A4845` |
| Light | `#FFFFFF` | `#D9D9D9` |

The separator is one physical pixel thick. The settings content area is 480 × 420 points; the native title bar and toolbar contribute to the total window height.

Arcload provides settings for:

- Default download directory
- Maximum simultaneous downloads
- Native per-task stream connection ceiling
- Native maximum byte-range request size (or automatic planning)
- Overall and per-task download speed limits
- HTTPS certificate verification (enabled by default)
- aria2 RPC port and optional, manually entered secret
- Launch at login

Settings → Connection → HTTPS → Verify Certificates controls `check-certificate` and is enabled by default. The choice is saved and applied to the bundled engine at launch and to its new-task defaults without a process restart. New and re-downloaded tasks explicitly use the current choice, even before the next engine poll; existing active, waiting and paused tasks retain their original policy. To retry a certificate failure with a different choice, re-download the failed task. Disabling verification weakens protection against server impersonation and interception; re-enable it when no longer needed. There is no automatic fallback to disabled verification.

The RPC secret defaults to empty and is never generated automatically. Enter a secret manually to enable authentication; clearing it disables secret authentication after the engine restarts. Existing saved secrets are preserved. The RPC service listens only on loopback, even without a secret. The secret is stored in UserDefaults, not Keychain; do not reuse a password from another service. Without a secret, other local processes can control the RPC service.

The interface labels speeds **KB/s / MB/s** and range-request sizes **MB**, using binary (1024-based) conversion: 1 KB/s = 1024 bytes/s and 1 MB = 1024 × 1024 bytes (technically KiB/s and MiB). The range-request control's hover help explains its MB conversion. Download-list speeds use the same binary conversion. Speed limits are entered in **KB/s** (1024 KB/s = 1 MB/s); **0 means unlimited**, independently for each setting. The overall limit controls the combined throughput of all downloads via `max-overall-download-limit`. The per-task limit controls `max-download-limit`: it sets the default for new tasks, and changes are sent to active and waiting/paused tasks. Explicit options supplied for a new task (including a retained re-download snapshot) may override that per-task default, but never bypass the overall cap. When both limits are set, both apply. Changing only the overall limit does not rewrite task-specific options or history. Values are saved for the next launch, converted safely to bytes/s, and applied by the engine's normal polling loop without a process restart. Actual rates can take time to settle after a live change.

The settings use preset dropdowns: **1, 3, 5** simultaneous downloads (default 5); **1, 2, 4, 8, 16, 32, 64** per-task payload connections (application cap 64; default 16); **Automatic, 1, 2, 4, 8, 16, 32, 64 MB** maximum range-request size. Native options are `stream-max-connections` and `stream-max-range-size`. Existing non-preset values remain effective until a preset is explicitly selected. If the native connection preference is absent, the connection ceiling is derived from the smaller of the legacy connection and split ceilings, without rewriting those preferences. The range-size default is automatic (0). Maximum request size limits each HTTP range request; it is not a minimum chunk size. Connection changes are sent to active and waiting/paused tasks; range-size changes set the default for new tasks. Explicit/re-download options take precedence. Replay options translate legacy connection limits to native ceilings and omit legacy minimum-split-size options. Arcload submissions use current preferences even before the next engine poll. Aria2 Next owns range planning and file assembly.

`python3 scripts/test-download-splitting.py` (optionally `--aria2 /path/to/aria2-next`) verifies parallel HTTP range downloads and file checksums, the payload connection ceiling, maximum request size, unchanged paused-task defaults, and downloading from a non-range server. It uses loopback networking and temporary files without changing app preferences or history.

An isolated, loopback-only integration check is available with `python3 scripts/test-download-speed-limits.py` (optionally `--aria2 /path/to/aria2-next`). It checks measured throughput, removing limits, and active/paused option updates using temporary downloads without touching app preferences or history.

`python3 scripts/test-aria2-next-lifecycle.py` checks partial-progress persistence across pause/force shutdown/restart with the same GID, checksum-correct resumed downloads, safe collision-renaming, preserving unrelated files, and failure/removal RPC. All integration tests use isolated loopback servers and temporary engine state.

`python3 scripts/test-rpc-authentication.py` verifies both an empty secret and a manually supplied secret using isolated loopback engines. It checks RPC readiness, authentication rejection, task controls and a checksum-correct download without modifying app preferences or history.

`python3 scripts/test-download-certificates.py` uses a temporary self-signed HTTPS server to verify certificate rejection when enabled, checksum-correct downloads when disabled, re-enabling verification, and preservation of existing-task policies. It also checks a verified download using an explicitly trusted test CA. No app preferences or history are modified.

Arcload packages only the pinned Apple Silicon `Resources/aria2-next`, validates its published SHA-256 before signing, and never prefers a Homebrew `aria2c`. Version/provenance is recorded in `Resources/aria2-next-release.json`. Runtime RPC must identify the expected product/version; lifecycle RPC is not sent to an unverified service. The engine ignores user-level configuration, verifies HTTPS certificates by default, and explicitly uses `media=file` so HTTP manifests are not silently turned into media jobs. HLS/DASH, ED2K and BitTorrent features in the executable are not exposed by Arcload's HTTP/HTTPS interface.

### Switching from legacy aria2

**Legacy unfinished tasks are not automatically imported.** Aria2 Next does not import legacy session/native resume state or adjacent `.aria2` control files. The legacy `~/Library/Application Support/Arcload/aria2.session`, its input snapshot and payload/control files are left untouched. Records in `history.sqlite3` remain available. Re-add old unfinished source URLs when needed; automatic renaming prevents overwriting existing partial files, but this starts a new transfer rather than adopting old progress.

Session/input files and native recovery state live under `~/Library/Application Support/Arcload/aria2-next/` (`session`, `session.input`, `state/`). Keep both the session and state directory to resume aria2-next downloads. Native recovery supports resuming partial downloads across force shutdown/restart with the same GID. App termination saves the session before requesting force shutdown within a bounded quit deadline; a forced kill after that deadline still cannot guarantee saving every last byte. The legacy executable remains in the source repository for reference, but is not packaged or used as a fallback.

Application data is stored under:

```text
~/Library/Application Support/Arcload/
```

## Release

Signed distribution builds use the local release workflow:

```sh
CERT_NAME='Developer ID Application: Your Name (TEAMID)' \
NOTARY_PROFILE=arcload-notary \
make dist
```

The release workflow builds, signs, notarizes, staples, and checksums a DMG. No ZIP application archive is produced.

## Project layout

```text
Sources/AppCore/       Application state, UI features, domain and aria2 engine
Sources/Application/   App entry point, commands, menu bar and lifecycle
Sources/CSQLite/       System SQLite module (no bundled database dependency)
Tests/AppCoreTests/   Unit and persistence regression tests
Resources/             Pinned aria2-next, license/provenance, Info.plist and icon source
Tests/SmokeTests/      Lightweight regression tests
scripts/               Build, validation and release tooling
```

## License

Arcload is licensed under the MIT License. See [LICENSE](LICENSE).

Third-party notices are listed in [NOTICE.md](NOTICE.md).
