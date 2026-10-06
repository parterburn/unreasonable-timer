# Unreasonable Timer

A native macOS version of the `/timer` page: the same look, the same keys, and the same
options, plus the things only a Mac app can do. It lives in the Dock and the menu bar, keeps
the display awake while it runs, and can go fullscreen on a projector.

Requires macOS 14 (Sonoma) or later.

## Using it

The setup form matches the web form: minutes and seconds, the text for zero, the text under
the timer, the text at 15 seconds left, people in the room, keep counting after zero, and a
light or dark theme. **Start Timer** opens the countdown paused, as the web page does.

| Key | Action |
| --- | --- |
| Space or click | Start / pause (after zero, reset) |
| ↑ / ↓ | Add / remove 15 seconds; hold to keep going (holding ↓ stops just above zero) |
| R | Reset |
| F | Fullscreen on the selected display |
| Esc | Leave fullscreen |
| ⌘+ / ⌘- / ⌘0 | Zoom the countdown in / out / back to actual size (⌘= works too) |
| ⌘E | Back to the setup form |

Click or drag along the progress bar to jump to that point; hovering it shows the time.
Move the mouse to show the hint line; it and the cursor hide after 2.5 seconds of stillness.

### Saved timers

Use **Save as named timer…** under the Start button. Saved timers appear in the setup form,
the menu bar menu, the Dock menu and the Timer menu, where the first nine get ⌘1 to ⌘9. The
five most recent runs are kept under **Previous timers**, newest first, without repeats.
Timers started from the menu bar, Dock, hotkeys, Shortcuts or a link start running immediately;
timers opened from the setup form start paused.

Everything is stored in `~/Library/Application Support/Unreasonable Timer/timers.json`. There is
no sync with Eco.

### Links

Paste a copied Eco `/timer?…` link into any field of the setup form (or press ⇧⌘V) and the form
fills in. The app also answers to its own scheme, with the same parameters as the web page:

```
untimer://start?time=300&lead=Intro&text=Wrap%20up&done=Stop&over=0&people=12&theme=light
untimer://open?time=300        # opens paused
```

`time` is in seconds (1 to 86,400). `text` is the text at 15 seconds left (an empty `text=`
means none). `over=0` stops at zero. `people` is 1 to 10,000. `theme=light` selects light mode.

### Shortcuts, Spotlight and global hotkeys

- **Shortcuts / Spotlight:** *Start Saved Timer*, *Start Timer* (N minutes) and *Pause or Resume
  Timer*.
- **Global hotkeys:** Settings ▸ Shortcuts. None are set by default so they can't collide with
  anything you already use.

### Settings

Accent color (teal by default; also on the setup form), keep the display awake while running
(on by default), keep the timer above other windows,
which display to go fullscreen on, chimes at 15 seconds and at zero (Classic, Singing bowl or
Marimba, each with a preview button; the sounds are made by `scripts/make-sounds.py`), menu bar item, open at
login, and updates.

## Building

```sh
brew install xcodegen
xcodegen generate
open UnreasonableTimer.xcodeproj
```

The project is generated from `project.yml`; the `.xcodeproj` isn't committed. Debug builds
sign ad hoc and need no Apple account.

### Tests

The countdown logic lives in its own Swift package (`Package.swift`, `Sources/Engine`), so its
tests run anywhere Swift does:

```sh
swift test
```

In Xcode, use the `UnreasonableTimer` scheme (⌘U). The views and system integrations
(menu bar, Dock, power assertion, fullscreen, hotkeys, intents) are checked by hand.

## Releasing

Releases are Developer ID signed and notarized, shipped as a DMG on GitHub Releases, and
updated in place with [Sparkle](https://sparkle-project.org). The installed app fetches
`releases/latest/download/appcast.xml` without logging in, so **this repository must be public**
(the release script warns if it isn't).

### One-time setup

1. **Developer ID certificate.** In Xcode ▸ Settings ▸ Accounts ▸ Manage Certificates, add a
   *Developer ID Application* certificate. Find its name and your team ID with
   `security find-identity -v -p codesigning`.
2. **Notarization credentials.** Create an app-specific password at appleid.apple.com, then:

   ```sh
   xcrun notarytool store-credentials unreasonable-timer \
     --apple-id you@example.com --team-id ABCDE12345
   ```

3. **Sparkle update key (needed for self-updating).** Without it you still get a signed, notarized
   DMG, but installed copies can't update themselves. Run:

   ```sh
   scripts/setup-sparkle.sh
   ```

   It creates the EdDSA signing key in your login Keychain (or reuses the one there) and writes
   the public half into `project.yml` as `SUPublicEDKey`. The private key never touches the repo.
   **Back it up** with the `generate_keys -x <file>` command the script prints, and keep the file
   in your password manager: without that key you can never ship an update to copies that are
   already installed. Commit the `project.yml` change.

### Each release

1. Bump `MARKETING_VERSION` **and `CURRENT_PROJECT_VERSION`** in `project.yml`. Sparkle only offers
   an update whose build number (`CURRENT_PROJECT_VERSION`) is higher than the installed one, so the
   script refuses to build if it isn't higher than the newest build in `release/updates/appcast.xml`.
   Optionally write what changed in `release-notes/<version>.md`; it is shown in the update window.
2. Run:

   ```sh
   scripts/release.sh
   ```

   With one Developer ID Application certificate in your keychain, the script finds the identity
   and team ID itself; otherwise set `DEVELOPER_ID_APPLICATION` (and `TEAM_ID`). It checks your
   notarization profile first, then archives unsigned, signs the app inside out with
   `scripts/sign-app.sh` (hardened runtime, secure timestamp), notarizes and staples it, and builds,
   signs, notarizes and staples the DMG. Signing is done with `codesign` rather than by
   `xcodebuild` because an identity passed to `xcodebuild` is applied to every target, including
   the Swift package dependencies, and the archive then fails. If a Sparkle key is configured it
   also regenerates `release/updates/appcast.xml`; otherwise that step is skipped and you still
   get a DMG.
3. Publish with `PUBLISH=1 scripts/release.sh`. It uploads three files: the versioned DMG (what
   the appcast points at), the same DMG as `UnreasonableTimer.dmg`, and `appcast.xml`. If you
   upload by hand, include all three: the app reads `releases/latest/download/appcast.xml`, and
   the fixed name keeps this link pointing at the newest version:

   <https://github.com/unreasonable/timer/releases/latest/download/UnreasonableTimer.dmg>

Keep the `release/updates` folder between releases; it holds the older DMGs the appcast history
is built from. The first run after `setup-sparkle.sh` makes macOS ask whether `generate_appcast`
may use the key in your Keychain: choose Always Allow.

### Testing an update

CI checks that the appcast is generated and signed, but only a real install can prove the update
itself works. Release 1.0.0, install it from the DMG, then release a build with a higher
`CURRENT_PROJECT_VERSION` and choose **Check for Updates…** in the installed app. It should offer
the new version, download it, replace itself and relaunch.

## Layout

```
project.yml            XcodeGen project (app + test targets, Hardened Runtime)
Package.swift          the TimerCore package, for `swift test`
Sources/Engine/        TimerConfig, TimerEngine, history: pure logic, no UI
Sources/Store/         PresetStore: saved timers and recent runs (JSON)
Sources/Views/         Theme, CountdownView, SetupView, menu bar, Settings
Sources/System/        KeepAwake, Notifier, DockTile, DisplayPresenter, Hotkeys, Updater
Sources/Intents/       App Intents for Shortcuts and Spotlight
Sources/App/           app entry, TimerController, Dock menu, Timer menu
Resources/             asset catalog, bundled Inter (OFL) fonts
scripts/               release.sh, make_icon.py
Tests/                 TimerEngine unit tests
```
