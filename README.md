# Olek

Your time. Your balance.

Olek is a small native macOS menu bar app for tracking working time. You are either working or not working: one toggle. It records sessions locally, compares them against expected working hours, and keeps a running overtime/undertime balance.

No accounts, no cloud, no telemetry. All data stays on your Mac.

## Status

Milestone 1 (foundation) is in progress.

| Area | State |
|---|---|
| Menu bar app with Start/Stop | Done |
| Persistent sessions (SQLite) | Done |
| Live session timer and today's total | Done |
| Recovery after sleep, crash, or quit | Done |
| Expected hours, Estonian holidays, balance | Milestone 2 |
| History window and editing | Milestone 3 |
| Idle and activity reminders | Milestone 4 |
| Settings, export, backup | Milestone 5 |

## Requirements

- macOS 14 Sonoma or later
- Xcode Command Line Tools (`xcode-select --install`). The full Xcode app is not required.

## Build and run

```sh
scripts/run.sh       # build a debug bundle and launch "Olek Dev"
scripts/test.sh      # run the test suite
scripts/install.sh   # build a release bundle and install/update /Applications/Olek.app
scripts/package.sh   # build a release zip in dist/ for sharing
```

`swift build` works directly. For tests, use `scripts/test.sh`: with only Command Line Tools installed, Swift Testing sits outside the compiler's default search paths, and the script adds them.

### Development and release builds are separate

| | Debug (`run.sh`) | Release (`install.sh`) |
|---|---|---|
| App name | Olek Dev | Olek |
| Bundle ID | `ee.olek.app.dev` | `ee.olek.app` |
| Data folder | `~/Library/Application Support/Olek Dev/` | `~/Library/Application Support/Olek/` |

Both can run at the same time. Development never touches your real tracking data.

## Installing and updating

Run `scripts/install.sh`. It builds a release bundle, quits the running copy, replaces `/Applications/Olek.app`, and relaunches it.

Updating works the same way: pull the latest code and run `scripts/install.sh` again. Your data is stored outside the app bundle, so replacing the app never touches it. If a new version changes the database schema, it is migrated automatically on first launch.

## Sharing with others

`scripts/package.sh` produces `dist/Olek-<version>.zip`. The app is ad-hoc signed, not notarized, so macOS Gatekeeper blocks it on first open when downloaded from the internet. The recipient can do either of these:

- Right-click Olek.app, choose Open, then confirm.
- Remove the quarantine flag:

  ```sh
  xattr -dr com.apple.quarantine /Applications/Olek.app
  ```

This repeats for each new version. Proper signing and in-app updates would need an Apple Developer account and are out of scope for now.

## How tracking works

- Each session stores a start and end timestamp in UTC. Durations are always computed from timestamps, never from a running timer.
- Only one session can be open at a time, and sessions never overlap.
- Daily totals split sessions at local midnight, so DST days and time zone changes are handled correctly.

### Sleep, crashes, and forgotten sessions

While tracking, Olek records a heartbeat every minute and when the Mac goes to sleep or Olek quits. When Olek wakes up or relaunches with a session still open, it looks at how long it was away:

| Away for | What happens |
|---|---|
| Under 15 minutes | Nothing. The session continues. |
| 15 minutes to 4 hours | The session continues, and Olek asks whether you were working. You can keep the time or stop at the moment it went away. |
| 4 hours or more | The session is stopped at the moment Olek went away. An undo button reopens it if you were in fact working. |

Olek never invents working time it could not observe.

## Project layout

```
Sources/OlekCore/   business logic and SQLite persistence, no UI
Sources/Olek/       the menu bar app
Tests/              Swift Testing tests for OlekCore
Resources/          Info.plist template
scripts/            build, bundle, run, install, package, test
```

## Data location

`~/Library/Application Support/Olek/olek.sqlite`

It is a standard SQLite database and can be inspected with `sqlite3`.
