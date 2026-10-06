# Unreasonable Timer

A native macOS version of the `/timer` page: the same look, the same keys, and the same
options, plus the things only a Mac app can do. It lives in the Dock and the menu bar, keeps
the display awake while it runs, and can go fullscreen on a projector.

Requires macOS 14 (Sonoma) or later.

## Using it

The setup screen is laid out like System Settings: saved and recent timers in the sidebar, and
the timer's options in a grouped form under a live preview of the countdown: the web form's
options, plus each timer's accent color (Unreasonable's colors first; point at one for its name) and sound (None, Classic, Singing bowl or Marimba, with
buttons to hear them; the singing bowl rings three times at zero). The sounds are made by
`scripts/make-sounds.py`. Pick a duration with the fields or the 1–60 minute buttons. **Open Timer** (or
Return) opens the countdown paused, as the web page does; double-click a timer in the sidebar to
open it straight away. The countdown keeps the web page's look.

| Key | Action |
| --- | --- |
| Space or click | Start / pause. After zero, press twice to reset (the first press asks) |
| ↑ / ↓ | Add / remove 15 seconds; hold to keep going (holding ↓ stops just above zero) |
| R | Reset |
| F | Fullscreen on the selected display |
| Esc | Leave fullscreen; otherwise back to editing the timer (while counting, press twice) |
| ⌘+ / ⌘- / ⌘0 | Zoom the countdown in / out / back to actual size (⌘= works too) |
| ⌘E | Back to the setup form |

Click or drag along the progress bar to jump to that point; hovering it shows the time.
Right-click the countdown for a menu of all of these, with their keys. The cursor and window
buttons hide after 2.5 seconds of stillness.

### Saved timers

Use **Save as Timer…** at the bottom of the setup screen. Saved timers appear in its sidebar,
the menu bar menu, the Dock menu and the Timer menu, where the first nine get ⌘1 to ⌘9. Select
one to edit it, then **Update** to keep the change; right-click to start or delete it. The five
most recent runs are kept under **Recent**, newest first, without repeats.
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
The Mac app also reads `accent=E8743B` (accent color), `sound=none|classic|singing-bowl|marimba`,
`chime15=1` (also chime at 15 seconds left) and text sizes in percent, 50 to 200: `timersize`,
`leadsize`, `textsize` (the text at 15 seconds left), `donesize` and `peoplesize`. The web page
ignores them.

### Shortcuts, Spotlight and the global shortcut

- **Shortcuts / Spotlight:** *Start Saved Timer*, *Start Timer* (N minutes) and *Pause or Resume
  Timer*.
- **Show the timer from any app:** record a shortcut in Settings ▸ App (click the box, press the
  keys). None is set by default, so it can't collide with anything you already use. Every other
  key works while the app is in front; Settings lists them, and right-clicking the timer shows
  them too.

### Settings

The gear at the bottom left of the setup screen (or ⌘,) shows the app settings on one page:
keep the display awake while running (on by default), keep the timer above other windows, which
display to go fullscreen on, menu bar item, open at login, the shortcut to show the timer, a list
of the built-in keys, and updates. While a timer
is on screen, ⌘, opens them in their own window instead, so the countdown keeps going. Sound,
accent color and theme belong to each timer, on the setup screen.

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

`generate_appcast` gives every version in the feed the newest release's download prefix, so
`scripts/fix-appcast.swift` points each one back at its own release. It also removes delta
updates, which are turned off (`--maximum-deltas 0`): the full DMG is a few megabytes.

### Releasing from GitHub Actions

The **Release** workflow (`.github/workflows/release.yml`) runs `PUBLISH=1 scripts/release.sh` on a
macOS runner, so a release doesn't need a particular Mac. Bump the version as above, push to
`main`, then run the workflow from the Actions tab. It rebuilds the appcast history from the
earlier releases and checks the published links at the end.

One-time setup: in the repo's Settings ▸ Environments, create an environment named `release`,
limit its deployment branches to `main`, and add these secrets to it:

| Secret | What it is |
| --- | --- |
| `DEVELOPER_ID_P12` | Your Developer ID Application certificate and key, exported from Keychain Access as .p12, base64-encoded |
| `DEVELOPER_ID_P12_PASSWORD` | The password you gave that export |
| `NOTARY_KEY`, `NOTARY_KEY_ID`, `NOTARY_ISSUER_ID` | An App Store Connect API key (the .p8 file's contents), its key ID and the issuer ID |
| or `NOTARY_APPLE_ID`, `NOTARY_PASSWORD` | Your Apple ID and an app-specific password, instead of the API key |
| `SPARKLE_PRIVATE_KEY` | The contents of the file `generate_keys -x <file>` writes |

```sh
base64 -i DeveloperID.p12 | gh secret set DEVELOPER_ID_P12 --env release --repo unreasonable/timer
gh secret set DEVELOPER_ID_P12_PASSWORD --env release --repo unreasonable/timer
gh secret set NOTARY_APPLE_ID --env release --repo unreasonable/timer
gh secret set NOTARY_PASSWORD --env release --repo unreasonable/timer
"$(find release/DerivedData -name generate_keys -type f | head -n 1)" -x sparkle-key
gh secret set SPARKLE_PRIVATE_KEY --env release --repo unreasonable/timer < sparkle-key && rm sparkle-key
```

Anyone who can run workflows on `main` can then sign releases as you, so keep write access to
this repo to people you'd trust with the certificate.

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
