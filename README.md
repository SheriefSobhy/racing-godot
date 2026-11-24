# Highway Blitz (Godot edition)

A 3D arcade highway racer for phones, made in Godot 4.7 with GDScript. It is the same game as
the Three.js version, [racing-3d](https://github.com/SheriefSobhy/racing-3d), rebuilt so the
two engines can be compared. Free CC0 assets only (see [CREDITS.md](CREDITS.md)).

**Play:** https://sheriefsobhy.github.io/racing-godot/

## How to play

- The car accelerates by itself. Steer with the left / right buttons, or pick **TILT** on the start screen.
- **NITRO** gives a burst of speed (flames and a wider camera view). The bar fills slowly over time, from blue nitro pickups, from near misses, and by drifting.
- Hold **DRIFT** to slide the tail out through curves. It fills nitro fast and leaves smoke and skid marks.
- Dodge the traffic. A crash knocks the other car away with real physics; **3 crashes end the run**.
- Score comes from distance, coins, drifts and near misses (pass close to traffic; chain them for a combo).
- Spend coins in the **Garage** on 3 more cars.
- **CAM** switches the view: chase, far chase, hood, bumper.
- **SETTINGS**: camera view, field of view, distance, height, smooth follow, camera shake, speed FOV boost, graphics Low / High, FPS counter, sound and music volume, mute, and invert tilt. Settings and progress are saved on the device.

Keyboard: arrows / A D steer, Space / W nitro, Shift / S drift, C camera, Esc / P pause, Enter start.

## How it works

| Part | Script |
| --- | --- |
| Endless road: the same curve and hill formulas as racing-3d | `scripts/track.gd` |
| Road, guard rails, terrain, trees, buildings, lamps, sky, sun and fog, streamed in 80 m chunks with collision | `scripts/world.gd` |
| Player car: `VehicleBody3D` with 4 `VehicleWheel3D` (raycast suspension, tyre grip), auto-acceleration, nitro, drift, downforce and stability helpers | `scripts/player_car.gd` |
| Traffic: `RigidBody3D` cars that follow their lanes until hit, then become free physics bodies (they can knock each other) | `scripts/traffic.gd` |
| Coins and nitro pickups | `scripts/pickups.gd` |
| Tyre smoke, sparks, nitro flames, skid marks | `scripts/effects.gd` |
| Chase / far / hood / bumper camera, shake, FOV boost | `scripts/camera_rig.gd` |
| Engine and effect sounds, music | `scripts/sound.gd` |
| HUD and all screens; touch buttons | `scripts/ui.gd`, `scripts/touch_controls.gd` |
| Game flow and scoring | `scripts/main.gd` |
| Settings and progress | `scripts/save.gd` (autoload `Save`) |

Rendering: the **Mobile** renderer on Android, the **Compatibility** renderer for the web
build (exported without threads, so it runs on GitHub Pages). Graphics **High** adds sun
shadows, 2x MSAA, normal maps and more trees; **Low** turns those off and renders at 80 %
resolution. Phones start on Low. If a race runs under about 48 fps, the 3D resolution
steps down automatically (down to 60 %). Frame rate is capped at 60.

## Building

Godot 4.7.2 is expected at `C:\Godot\Godot_v4.7.2-stable_win64_console.exe`.

- **Web:** every push to `main` runs `.github/workflows/deploy.yml`, which exports the web
  build with Godot 4.7.2 and deploys it to GitHub Pages.
- **Android debug APK:** run `build_apk.bat`. The APK goes to
  `builds\HighwayBlitzGodot.apk` (git-ignored). It is signed with the Android debug keystore
  set in the Godot editor settings.

### Test tools

- `tools/test_drive.gd`: headless autopilot that drives the real physics car and reports lane
  keeping, lane-change time, drift angle and crashes.
  `godot --headless --path . --fixed-fps 60 -s res://tools/test_drive.gd -- secs=60 traffic=1`
- `tools/perf.gd`: frame-time test (run windowed; add `--rendering-method gl_compatibility`
  for the web renderer).
- `tools/screenshot.gd`: captures every screen to PNG files.
- `tools/bench_chunks.gd`: times road chunk generation.
