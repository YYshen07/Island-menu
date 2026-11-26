# Island Menu

macOS performance monitor that expands out of the Dynamic Island on the PROLED MacBook Pro.

## Commands

- Build (debug): `swift build`
- Build the app bundle: `./scripts/bundle.sh` → `build/Island Menu.app` (ad-hoc signed)
- Run with the card already open: `open "build/Island Menu.app" --args --open`
- Build a distributable zip: `./scripts/package.sh` → `build/IslandMenu-<version>.zip`
- Quit: `pkill -x IslandMenu` (or the menu bar icon → 退出)

No tests or linter are set up yet.

## Layout

- `Sources/IslandMenu/Island/` — panel over the Dynamic Island, open/close, geometry.
- `Sources/IslandMenu/Metrics/` — samplers (one file per subsystem) and `MetricsEngine`.
- `Sources/IslandMenu/UI/` — SwiftUI card and sections.
- `mockup/` — static web design mockup with simulated data.
- `docs/3d-model-brief.md` — spec for the 3D machine model (built separately in Blender).
- `refs/` — cloned reference repos (git-ignored): logoctl, LogoLight, DynamicNotchKit, stats, macmon.

## Conventions

- The target is the Dynamic Island (a floating pill below the top edge), not a notch. The card is a
  floating rounded rectangle that morphs out of the pill; closed, the app draws nothing over the island.
- Island clicks are handled by `NSEvent` monitors in `IslandController`, not SwiftUI gestures; the
  closed panel is fully transparent and SwiftUI would never see the click.
- The fast sampling loop must only run while the card is open. Closed, only the 60 s activity tick runs.
- Do not show a metric the app cannot actually read; leave it out until the sampler exists.
- Functions ≤ 50 lines, files ≤ 500 lines. Code and comments in English, UI strings in Chinese.
