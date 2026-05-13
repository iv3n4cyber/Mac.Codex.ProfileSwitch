# Mac.Codex.ProfileSwitch

[English](README.md) | [中文](README.zh-CN.md)

Mac.Codex.ProfileSwitch is a lightweight macOS menu bar utility for managing multiple Codex Desktop profiles.

It lets you switch between OpenAI OAuth accounts and OpenAI-compatible provider configs while keeping one shared Codex session history under `~/.codex`.

The app only replaces:

```text
~/.codex/auth.json
~/.codex/config.toml
```

It does not move or split:

```text
~/.codex/sessions
~/.codex/archived_sessions
```

## Features

- macOS menu bar app for quick profile switching
- Management window for profile, general, backup, and about settings
- First-run profile registration from the current `~/.codex/auth.json` and `~/.codex/config.toml`
- OpenAI OAuth account login with local callback capture
- OAuth account deduplication by `account_id`
- OpenAI-compatible provider profile creation and editing
- Profile switching with automatic backup of the previously active `auth.json` and `config.toml`
- Shared session pool, so conversation history remains available after switching accounts
- OAuth usage refresh from the menu bar popover
- Compact menu bar usage indicator
- Local token usage summary for today, 30 days, and total usage
- Hover usage detail panel with a 14-day token usage chart
- English and Chinese UI language switch
- Codex client restart shortcut
- Backup page for exporting sessions, profiles, or the current auth/config files as zip archives

## How It Works

Profiles are stored as folders under:

```text
~/.codex/profiles/
```

Each profile contains:

```text
auth.json
config.toml
```

When you switch profile, the app:

1. Backs up the current active `auth.json` and `config.toml`.
2. Copies the selected profile's `auth.json` and `config.toml` into `~/.codex`.
3. Leaves `sessions` and `archived_sessions` untouched.
4. Records the active profile in the app state file.

App-local state and backups are stored under:

```text
~/.codex/mac-codex-profile-switch/
```

## Basic Usage

### Launch

Run the app. A menu bar icon appears in the macOS status bar.

Click the icon to open the quick switch popover.

### First Run

If no profiles exist yet, the app automatically registers the current Codex config as the first profile when it sees:

```text
~/.codex/auth.json
~/.codex/config.toml
```

For OpenAI OAuth profiles, the default profile name is based on the email prefix.

For provider profiles, the default profile name is based on the provider host.

### Add an OAuth Account

Use the OAuth button in the menu bar popover or the green add button in the management window.

The app opens the OpenAI OAuth flow in your browser, captures the local callback, saves the token into a profile, and deduplicates accounts by `account_id`.

### Add a Provider

Use the Provider add button and enter:

- Profile name
- Base URL
- API key

The model is not stored as a required field in the add-provider flow; Codex can manage model selection separately.

### Switch Profiles

Use the menu bar popover for quick switching.

In the management window, selecting a profile asks for confirmation before switching.

### View Usage

OAuth profiles can show current quota usage in the menu bar popover.

The app also scans local Codex session logs to summarize token usage:

- Today
- Last 30 days
- Total

Hover the token summary to view detailed token counts and a 14-day chart.

### Back Up Data

Open the management window and go to the Backup page.

Run a scan first. The page shows previews for:

- Sessions
- Profiles
- Current `auth.json` and `config.toml`

Then export any group as a zip file. You can choose the save location before the archive is created.

## Data Locations

Active Codex files:

```text
~/.codex/auth.json
~/.codex/config.toml
```

Profile storage:

```text
~/.codex/profiles/
```

Shared session history:

```text
~/.codex/sessions
~/.codex/archived_sessions
```

App state, backups, and local cache:

```text
~/.codex/mac-codex-profile-switch/
```

## Privacy Notes

This project is designed to work with local Codex files on your machine.

Do not commit or publish:

- `auth.json`
- `config.toml`
- OAuth tokens
- API keys
- `~/.codex/sessions`
- `~/.codex/archived_sessions`
- backup zip archives

The repository should only contain source code and project metadata.

## Requirements

- macOS 14 or later
- Swift 6 toolchain
- Codex Desktop using the standard `~/.codex` directory layout

## Tech Stack

- Swift
- SwiftUI
- AppKit
- Swift Package Manager
- macOS menu bar status item APIs
- Local file-based profile storage
- Native macOS save panels and workspace integration
- `/usr/bin/ditto` for zip archive creation

No third-party Swift package dependencies are required.

## Build

Build a release binary:

```sh
swift build -c release
```

Run from source:

```sh
swift run Mac.Codex.ProfileSwitch
```

The release executable is generated under:

```text
.build/release/Mac.Codex.ProfileSwitch
```

## Opening the App

If macOS prevents the app from opening after download, try:

1. Open the dmg.
2. Drag `Mac.Codex.ProfileSwitch.app` into Applications.
3. Right-click the app and choose `Open`.
4. Click `Open` again in the confirmation dialog.

If it still cannot open, run:

```sh
xattr -dr com.apple.quarantine /Applications/Mac.Codex.ProfileSwitch.app
```

Then open the app again.

## Project Structure

```text
Package.swift
Packaging/
  Info.plist
Sources/
  MacCodexProfileSwitch/
    AppDelegate.swift
    AppText.swift
    BackupService.swift
    CodexPaths.swift
    LocalTokenUsageService.swift
    MenuBarController.swift
    MenuBarPopoverView.swift
    OpenAIOAuthLoginService.swift
    OpenAIQuotaService.swift
    ProfileManagerView.swift
    ProfileSwitcherService.swift
    ProviderProfileService.swift
    ...
```

## Release Notes

For public release, include only source files and project metadata in the repository.

Do not include:

- `.build/`
- `.swiftpm/`
- `dist/`
- `.DS_Store`
- personal Codex configuration
- local session history
- generated backup archives

## Reference

- [codexbar](https://github.com/steipete/codexbar)
