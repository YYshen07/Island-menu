# Island Menu

macOS performance monitor that expands out of the Dynamic Island on the PROLED MacBook Pro.

## Commands

- Build (debug): `swift build`
- Build the app bundle: `./scripts/bundle.sh` → `build/Island Menu.app` (ad-hoc signed)
- Run with the card already open: `open "build/Island Menu.app" --args --open`
- Install to /Applications and launch (needed for the fan helper): `./scripts/install.sh`
- Build a distributable zip: `./scripts/package.sh` → `build/IslandMenu-<version>.zip`
- Toggle the card from a script: `pkill -USR1 -x IslandMenu`. Do not post synthetic mouse clicks to test it;
  the machine is in use and a stray click lands in whatever app is in front.
- Quit: `pkill -x IslandMenu` (or the menu bar icon → 退出)

No tests or linter are set up yet. Plain `swift build` needs `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer`.

## Layout

- `Sources/IslandMenu/Island/` — panel over the Dynamic Island, open/close, geometry.
- `Sources/IslandMenu/Metrics/` — samplers (one file per subsystem) and `MetricsEngine`.
- `Sources/IslandMenu/UI/` — SwiftUI card and sections.
- `Sources/IslandMenu/Control/` — things the app changes: logo light (CoreBrightness), charge limit (PowerUI), audio meter.
- `Sources/IslandShared/` — SMC client and the XPC protocol, shared by the app and the helper.
- `Widgets/` — widget extension with the Live Activity views. Built by xcodegen + xcodebuild from `bundle.sh`,
  because SwiftPM cannot produce an app extension; it compiles `Sources/IslandShared/MonitorActivity.swift` directly.
- `Sources/IslandMenuHelper/` — root launch daemon that writes fan speeds (registered with `SMAppService.daemon`).
- `Sources/IslandMenu/Settings/` — preferences store and the settings window.
- `Sources/IslandMenu/Drop/` — AirDrop drop zone.
- `mockup/` — static web design mockup with simulated data.
- `docs/3d-model-brief.md` — spec for the 3D machine model (built separately in Blender, lives in `assets/model/`).
- `refs/` — cloned reference repos (git-ignored): logoctl, LogoLight, DynamicNotchKit, stats, macmon.

## 3D model

- `bundle.sh` copies `assets/model/macbook-pro-14.usdz` into the app's `Contents/Resources`. A plain
  `swift build` binary has no model and the machine section renders without it.
- Check camera and lighting without launching the UI:
  `.build/debug/IslandMenu --render-model assets/model/macbook-pro-14.usdz /tmp/model.png`
- `MachineScene` looks nodes up by the names in `docs/3d-model-brief.md`; renaming them breaks the bindings.
- SceneKit calls the renderer delegate on its render thread, not the main actor.

## Hardware notes (Mac17,13, macOS 27.3)

- Native island: macOS 27.3 opens Live Activities (ActivityKit) to Mac apps. It needs the 27.3 SDK, i.e.
  Xcode 27.3 beta at `/Applications/Xcode-beta.app`; `bundle.sh` selects it through `DEVELOPER_DIR`. The 27.2
  SDK marks the same APIs unavailable, which is why an earlier check wrongly concluded there was no API.
- `Activity.request` is refused unless the app is frontmost ("Requester is not foreground" in
  `liveactivitiesd` logs), so `LiveActivityController` activates the app briefly before asking.
- A Live Activity cannot host the full panel (static WidgetKit views, no SceneKit, no scrolling), so the
  activity shows headline numbers and links to `islandmenu://panel`, which opens the overlay card.
- The system island draws above every window level; the overlay card cannot cover it.
- Charge limit: `PowerUISmartChargeClient` (`setMCLLimit:error:`, limits 80/85/90/95/100) works without root.
  The legacy SMC charge keys (CH0B, CH0C, CHTE) do not exist on this machine.
- Fans: `FNum` = 2, `F{n}Ac`/`F{n}Mn`/`F{n}Mx`/`F{n}Tg` are `flt`, mode key is lowercase `F{n}md` (ui8). Writing needs root.
- Logo light: hardware fades via `LEPWMFactorFadeDuration` + `DisplayLogicalState`; per-frame brightness
  writes cost about 12% CPU in corebrightnessd, fades about 2.6%.
- Commit with `git commit -F <file>`: the system bash (3.2) cannot parse an apostrophe inside a heredoc
  inside `$(...)`, and it runs the earlier commands in the same call before failing.
- Test a logo mode without the UI: `defaults write dev.yan.islandmenu logoMode breathe` then relaunch;
  `refs/logoctl/.build/release/logoctl status --json` reads the live output.

## Conventions

- The target is the Dynamic Island (a floating pill below the top edge), not a notch. The card is a
  floating rounded rectangle that morphs out of the pill; closed, the app draws nothing over the island.
- Island clicks are handled by `NSEvent` monitors in `IslandController`, not SwiftUI gestures; the
  closed panel is fully transparent and SwiftUI would never see the click.
- The fast sampling loop must only run while the card is open. Closed, only the 60 s activity tick runs.
- Stage files by path when committing; `assets/` and `tools/` receive files from other tools mid-session.
- Do not show a metric the app cannot actually read; leave it out until the sampler exists.
- Functions ≤ 50 lines, files ≤ 500 lines. Code and comments in English, UI strings in Chinese.
