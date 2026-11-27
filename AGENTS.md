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
- Script the card for screenshots: launch with `--pin` (outside clicks do not close it), then
  `open -g -a "$PWD/build/Island Menu.app" islandmenu://flip` (also `lid`, `top`, `bottom`). Always pass `-a`:
  without it LaunchServices may start the copy in /Applications. `scripts/screenshots.sh <dir> [--notch]` does the
  whole README set, capturing only the card's window (`screencapture -l`), so nothing else on screen leaks in.
  Crop out the network section before publishing: it shows the public and Tailscale IPs.
- Notch layout on this machine: `--notch` (or settings → 屏幕形态). The cutout here is a 59 pt camera hole, so the
  app draws a 185 x 32 pt stand-in notch. Not yet run on real notch hardware or on macOS 27.2.
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

- Five bodies (`MachineModel`): PROLED Pro 14, notch Pro 14 and 16, Air 13 and 15. The app picks one from the
  hardware (logo light, fans, panel diagonal) (not user-selectable; the hidden `machineModel` default previews another).
  Settings → 机模 only changes the shell colour (`MachineFinish`, grouped Pro / Air / Neo) and the open screen's
  picture (`ScreenContent`; the panel mesh has no UVs, so the picture is a plane laid over it on first lid open).
  Nodes differ per body (no `Fan_*`/`Heatpipe` on the Airs, `Die_Eff` instead of `Die_Super` on notch Pros), so
  look parts up optionally. Only the PROLED body has a lit logo; the rest get the mirror shader.
- Stickers (`Sources/IslandMenu/Stickers/`): VisionKit subject lifting (the Photos one; needs a running app,
  so command-line paths fall back to Vision), effects applied on top in `StickerMaker.styled`, saved as PNGs in
  Application Support; `MachineStickers.swift` lays them on `Shell_Lid` as planes. Try one offscreen with
  `--render-model <usdz> out.png --sticker "/Library/User Pictures/Animals/Eagle.heic" 0`.
- The wallpaper comes from the wallpaper service's store (`Wallpaper.swift`); `NSWorkspace.desktopImageURL`
  returns the default picture when an aerial is set.
- Preview any of them: `--render-model assets/model/macbook-air-15.usdz out.png --finish skyBlue 0`.
- `bundle.sh` copies the five `assets/model/*.usdz` into the app's `Contents/Resources`. A plain
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
- The Live Activity is raised only while an alert is active (`AlertMonitor`). To test one, lower a limit:
  `defaults write dev.yan.islandmenu alertRules -data $(printf '{"cpu":{"enabled":true,"limit":3}}' | xxd -p | tr -d '\n')`,
  relaunch, wait about 20 s, then `defaults delete dev.yan.islandmenu alertRules`.
- The system keeps the widget extension process alive across app updates. A stale one cannot decode a changed
  `ContentState` and the system drops the activity within milliseconds; `install.sh` kills it.
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

## Performance

- Budget: card closed, well under 0.5% CPU. Measured for 1.0.0 with the fan curve loop running: about 0.2% and
  20 MB fresh, 60 MB after the card has been opened once; open, 3-6% and about 180 MB (mostly SceneKit).
- Closed, the card's SwiftUI content is unmounted (`IslandState.isMounted`) and the allocator is asked to give
  back freed pages (`malloc_zone_pressure_relief`); without the latter the footprint stays near 105 MB.
- The background loops read the die temperature through `ThermalSampler.dieMax()`, which reads all die sensors
  only every tenth call and the three hottest in between. The fan loop skips it entirely in max mode.
- The user is usually working on this machine while you measure, and any click outside closes the card. For
  open-state numbers relaunch with `--open --pin`; for closed-state ones check the panel height stayed 39.
- The model is drawn on demand (`MachineScene.updatePlayback`). Two things silently turn that back into
  continuous rendering: a particle system attached to the scene, even with a birth rate of 0, and writing any
  material property on every sample, even with an unchanged value.
- Measure with CPU-time deltas, not single `top` samples, and check the card stayed closed for the whole window
  (the user opens it while you measure): `ps -o cputime= -p $(pgrep -x IslandMenu)` before and after a `sleep 60`.
- Known costs: one temperature sensor read is over 0.5 ms (so sensors are de-duplicated and background loops read
  only the die sensors); `volumeAvailableCapacityForImportantUsage` takes tens of ms (cached 30 s); the battery
  registry read and the process walk are the next most expensive.

## Conventions

- Two layouts (`IslandStyle`): the Dynamic Island (a floating pill; the card is a floating rounded rectangle and
  the app draws nothing over the island while closed) and the notch (the card hangs from the bezel with a square
  top and concave ears, `CardShape`). Auto-detection uses the logo light: only PROLED machines have one.
- The deployment target is macOS 27.0 so notch machines on 27.2 can run it; anything from the 27.3 SDK
  (ActivityKit, `AlertMonitor`) must sit behind `#available(macOS 27.3, *)`.
- Island clicks are handled by `NSEvent` monitors in `IslandController`, not SwiftUI gestures; the
  closed panel is fully transparent and SwiftUI would never see the click.
- The fast sampling loop must only run while the card is open. Closed, only the 60 s activity tick runs.
- Stage files by path when committing; `assets/` and `tools/` receive files from other tools mid-session.
- Do not show a metric the app cannot actually read; leave it out until the sampler exists.
- Functions ≤ 50 lines, files ≤ 500 lines. Code and comments in English, UI strings in Chinese.
