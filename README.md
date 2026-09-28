# Arcload

Arcload is a lightweight native download manager for macOS, built with SwiftUI and powered by aria2.

It is designed for a focused macOS experience: fast HTTP/HTTPS downloads, native task management, a compact menu bar presence, and a small application footprint.

## Features

- Native SwiftUI interface for macOS
- HTTP/HTTPS downloads powered by aria2
- Segmented downloads with up to 16 connections per server
- Configurable concurrent downloads and download speed limit
- Pause and resume individual tasks, selected tasks, or all tasks
- Native Command-click and Shift-click multi-selection
- Batch removal and batch file deletion
- Double-click completed tasks to open downloaded files
- Reveal downloaded files in Finder
- Menu bar status indicator while downloads are active
- Automatic aria2 process recovery
- Launch at login support
- Configurable local aria2 RPC port and secret

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

## Configuration

Arcload provides settings for:

- Default download directory
- Maximum simultaneous downloads
- Maximum connections per server
- Download speed limit
- aria2 RPC port and secret
- Launch at login

Arcload starts aria2 with an explicit runtime configuration and does not load the user's `~/.config/aria2/aria2.conf`.

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
Resources/             aria2, Info.plist and app icon source
Tests/SmokeTests/      Lightweight regression tests
scripts/               Build, validation and release tooling
```

## License

Arcload is licensed under the MIT License. See [LICENSE](LICENSE).

Third-party notices are listed in [NOTICE.md](NOTICE.md).
