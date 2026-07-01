# Developing ViewSelected

Implementation and development details for the plugin: a BepInEx camera helper
for the Unity game **Marble World** (a **V** hotkey that frames the selected
object, plus a **middle-mouse drag** orbit). See [README.md](README.md) for the
user-facing description, installation, and usage.

## What this project is

- A small C# class-library (`.csproj`) that compiles to `ViewSelected.dll`, a
  BepInEx plugin. No original game installation files are altered; the plugin is
  injected at runtime by BepInEx and calls the game's existing public methods. We
  do NOT recompile the game's `Assembly-CSharp.dll`.
- On V (Ctrl not held), the plugin finds the selected object, computes its
  combined renderer-bounds center, and drives the game's built-in camera move
  (SmoothDamp to `focusPoint - cameraForward * 5f`, a fixed 5-unit pullback).
- **Bypasses the `cameraFollowBuild` gate:** `CameraController.CenterOnPoint(...)`
  no-ops unless the in-game "camera follow build" setting is on, but the actual
  move (`CameraController.Update`) is gated only on the private
  `isMovingToCenterOnObject`, not on the setting. So instead of calling
  `CenterOnPoint`, the plugin arms `CenterOnPoint`'s two private fields directly
  via reflection (`focusObjectPosition`, `isMovingToCenterOnObject`) so V works
  regardless of that setting. If those fields cannot be resolved (game update), it
  falls back to the public `CenterOnPoint` (which respects the setting) and logs a
  one-time warning in `Awake`.
- **Ctrl bail:** the plugin does nothing when Ctrl is held, so the game's
  `Ctrl+V` (Paste) is untouched.
- **Typing guard:** before framing, the plugin mirrors the game's own input gate
  (`MWInputManager.Update`) by reading two private bools off
  `MWInputManager.instance` via reflection - `isDoingTextInput` (true while a
  text field is focused; set by `InputFieldHandler` on EventSystem
  select/deselect) and `shouldTakeInput` (false while input is globally
  suppressed, e.g. during level loads). If either gate is active, V does nothing,
  so typing a "v" while renaming an object will not move the camera. If a game
  update renames those fields, reflection yields null, a one-time warning is
  logged in `Awake`, and the guard degrades to "accepting" so the core hotkey
  still works.
- **Orbit (middle-mouse drag):** the game's camera is free-fly / FPS-style
  (right-mouse = in-place look, no orbit). This adds 3D-modeler orbit on MMB drag,
  which is unbound in-game so it never conflicts. Pivot = the selection's focus
  point, or (nothing selected) a point `OrbitFallbackPivotDistance` (5u) straight
  ahead. Math is spherical (azimuth around world-up, elevation clamped to +/-89deg,
  radius fixed); sensitivity mirrors `CameraController.rotateSpeed` (2f) times
  `GameplaySettings.cameraRotateSpeed` and honors `cameraYAxisInverted`. Each frame
  it writes `transform.position`/`rotation` directly, which coexists with the
  game's `Update` because that only writes rotation while the look key is held and
  otherwise adds ~0 movement.
  - **Pre-orbit re-aim:** on MMB-down, if the pivot is more than
    `OrbitReaimThresholdDegrees` (~1deg) off-center or behind the camera, the view
    is snapped to face it first (via `LookRotation`) so we never orbit around an
    off-screen point. An already-centered pivot is left alone.
  - **Conflict handling:** skips starting while right-mouse look is held; cancels
    any in-flight V focus move (`isMovingToCenterOnObject = false`); respects the
    typing / `shouldTakeInput` gate; locks+hides the cursor during the drag and
    restores it on release.
  - **Look-angle writeback:** orbiting moves the camera behind the game's back, so
    on release it writes the resulting orientation into the game's private
    `yaw`/`pitch`/`yawSmoothed`/`pitchSmoothed` (reflection) - otherwise the next
    right-mouse look would snap to the stale angles. Degrades to a one-time warning
    (orbit still works) if those fields cannot be resolved.
  - **Tuning caveat:** the exact scale of `MWInputManager.GetMouseDelta()` is
    unknown, so `OrbitRotateSpeed` and the yaw/pitch signs may need adjustment to
    taste.

## Key facts about the game (verified)

- **Engine:** Unity 2020.1.13f1, **Mono** scripting backend (has
  `Marble World_Data/Managed/Assembly-CSharp.dll`, no `GameAssembly.dll`). Mono
  is the friendly case for modding.
- **Active Input Handling is "Both"**: the game itself uses legacy
  `Input.GetKeyDown` (e.g. `Flipper.cs`, `LogicInput.cs`) as well as the new
  Input System, so our legacy `Input` polling (`V`/`Ctrl`, and the mouse buttons
  for orbit) is safe to use.
- **Mouse bindings:** the input asset binds `leftButton` (Fire/select),
  `rightButton` (AlternateFire = look), `scroll` (zoom/move object), and `delta`
  (look), but **not `middleButton`** - so MMB is free for our orbit gesture.
- **No user-facing keybinding/rebind UI**: bindings are hardcoded JSON in the
  new Input System's `InputActionAsset` (parsed via `MWControls`), with no
  in-game remap screen or persistence. So a hotkey cannot be "managed by the
  game's keybinding config" in the player-reassignable sense. If a configurable
  hotkey is wanted later, the standard path is BepInEx
  `Config.Bind<KeyboardShortcut>`.

## Important paths

- **Game install:** `C:\Apps (x86)\Games\Steam\steamapps\common\Marble World`
- **Managed DLLs (reference assemblies):** `<game>\Marble World_Data\Managed`
  (`Assembly-CSharp.dll`, `UnityEngine.dll`, `UnityEngine.CoreModule.dll`,
  `UnityEngine.InputLegacyModule.dll`, ...). The build does NOT reference these
  in place; `provision-refs.ps1` copies them into the repo-local `.build\lib` (see
  "Build and deploy"). The game install is only auto-discovered (via Steam) to
  populate `.build\lib` the first time.
- **BepInEx:** BepInEx 5 (Mono). NOTE: it is not assumed to be installed in the
  game folder - a Steam update can wipe it. `provision-refs.ps1` downloads the
  pinned BepInEx zip and extracts `BepInEx.dll` into `.build\lib` for the build. At
  runtime BepInEx still lives in the game folder (plugins in `<game>\BepInEx\plugins`,
  log at `<game>\BepInEx\LogOutput.log`); the AllInOne release zip bundles it.
- **Read-only decompiled game source** (for looking up game APIs):
  `C:\Projects\Games\Marble World\AssetRipperExports\AssetRipper_v1.3.14_export_20260629_165353\Assets\Scripts\Assembly-CSharp`.
  Line numbers cited below refer to these decompiled files. Prefer dnSpyEx /
  ILSpy on the real `Assembly-CSharp.dll` for authoritative reading.

## Game APIs this plugin relies on (all public)

- `CameraController.instance` - singleton. `CenterOnPoint(Vector3)`
  (`CameraController.cs:371`) sets `focusObjectPosition = focusPoint - cameraForward * 5f`
  and `isMovingToCenterOnObject = true`; the controller's `Update`
  (`CameraController.cs:314`) then smooth-damps `transform.position` toward
  `focusObjectPosition` while that flag is set.
  - **Note:** `CenterOnPoint` no-ops unless `GameplaySettings.cameraFollowBuild != 0`
    (the in-game "camera follow build" setting). The plugin sidesteps this gate by
    setting the two **private** fields directly via reflection
    (`focusObjectPosition` `:63`, `isMovingToCenterOnObject` `:61`) - the `Update`
    move itself has no `cameraFollowBuild` check. So this setting no longer affects
    the hotkey (except in the reflection-failure fallback path). `cameraFollowBuild`
    is `public static int` (`GameplaySettings.cs:54`, default 1, PlayerPrefs-backed).
  - Orbit also reads/writes these **private** `CameraController` fields by
    reflection: `yaw` (`:27`), `pitch` (`:29`), `yawSmoothed` (`:37`),
    `pitchSmoothed` (`:39`) - the game's free-fly look angles, written back after an
    orbit so the next right-mouse look does not snap.
- `SelectableManager.instance` - singleton. `GetHasSelectablesSelected()` and
  `GetFirstSelected()`. `GetFirstSelected()` indexes `_selectedSelectables[0]`
  with no empty-check, so only call it after `GetHasSelectablesSelected()` is true.
- `Selectable` - per-object selection component; we read its child `Renderer`
  bounds for the focus point.
- `MWInputManager.instance` - singleton (public static). The typing guard reads
  its **private** `isDoingTextInput` (`MWInputManager.cs:16`) and `shouldTakeInput`
  (`MWInputManager.cs:20`) by reflection; the game's own `Update` (`:66`, `:70`)
  gates gameplay input on these. Only setters are public (`ShouldTakeInput`:478,
  `SetIsDoingTextInput`:498), hence reflection. `isDoingTextInput` is also
  mirrored onto `CameraController` (`CameraController.cs:53`).
  - `GetMouseDelta()` (`MWInputManager.cs:493`, public) - orbit reuses this for the
    mouse delta so it matches the game's look input.

## Build and deploy

Requires the .NET SDK (`dotnet`; 5.0.416 was used). The project targets
`netstandard2.0`. **All build-generated files live under a single gitignored
`.build\` folder** (`Directory.Build.props` redirects `bin`->`.build\bin` and
`obj`->`.build\obj`; the scripts put `dist`, `cache`, and `lib` there too), so the
repo root stays clean. The build's reference assemblies (`BepInEx.dll`,
`UnityEngine*.dll`, `Assembly-CSharp.dll`) are vendored into `.build\lib`, and the
csproj references them via `<HintPath>$(MSBuildThisFileDirectory).build\lib\...</HintPath>`
with `<Private>false</Private>` (not copied to output). No machine-specific path
is committed; there is no dependency on where (or whether) BepInEx is installed
in the game folder at build time.

**Provision `.build\lib` once** with `provision-refs.ps1`:
- Downloads + SHA256-verifies the pinned BepInEx zip (cached in `.build\cache\`)
  and extracts `BepInEx.dll`.
- Auto-discovers the Marble World install from Steam (registry `Valve\Steam` +
  `libraryfolders.vdf`, AppID `1491340`) and copies the Unity + `Assembly-CSharp`
  DLLs. A game install is only needed here, and only until `.build\lib` is
  populated; `Assembly-CSharp.dll` is proprietary and cannot be downloaded, so it
  must come from an install. If a required DLL is missing, a csproj `<Target>`
  fails the build early telling you to run this script.

```sh
# from the project root (C:\Projects\Games\Marble World\Mods\ViewSelected)
./build.ps1                 # provisions .build\lib (idempotent) then dotnet build
# then deploy:
cp ".build/bin/Release/netstandard2.0/ViewSelected.dll" \
   "C:/Apps (x86)/Games/Steam/steamapps/common/Marble World/BepInEx/plugins/ViewSelected.dll"
```

Script chain (each dot-sources the previous to reuse its constants/functions):
`deploy.ps1` / `make-release.ps1` -> `build.ps1` (`Invoke-PluginBuild`: provision +
`dotnet build`) -> `provision-refs.ps1` (`Initialize-BuildReferences`, Steam
discovery `Find-MarbleWorldInstallDir`, the `$BuildDir` layout, BepInEx download
constants, `Get-BepInExArchive`). You can also run `dotnet build -c Release`
directly once `.build\lib` is provisioned, or `./provision-refs.ps1` to just
populate it.

For a full-cycle test install, run **`./deploy.ps1`**: it runs `make-release.ps1`,
finds the Steam install (`Find-MarbleWorldInstallDir`, cached in
`.build\cache\marble-world-install.txt`), runs the previous copy's uninstaller if
one is present, then extracts the fresh AllInOne zip into the game folder. Then
just launch the game.

Iterate: edit -> `./build.ps1` -> copy DLL (or `./deploy.ps1`) -> relaunch the game.

Build gotchas seen in this project:
- The csproj must reference the **`UnityEngine` facade assembly**
  (`UnityEngine.dll`), not just `CoreModule`. BepInEx's `BaseUnityPlugin`
  resolves `MonoBehaviour` through that facade, so without it the build fails to
  find `MonoBehaviour`.
- The MSBuild/`VBCSCompiler` server (and antivirus) can keep `.build\bin` /
  `.build\obj` or old folders locked ("Device or resource busy"). Run
  `dotnet build-server shutdown` before removing/renaming build output.

## Verify (needs the game running)

1. Launch Marble World; check `BepInEx\LogOutput.log` for
   `View Selected v<version> loaded` (the `PluginVersion` from `ViewSelectedPlugin.cs`).
2. Select an object, press V -> camera should smooth-pan to frame it; log shows a
   `viewing '<name>' at <pos>` line. This works with the in-game "camera follow
   build" setting either on or off (the plugin bypasses that gate).
3. V with nothing selected -> no movement, no exception ("nothing selected").
4. Focus a text field (e.g. rename panel), type a word containing "v" -> camera
   does NOT move (typing guard). Defocus, then V works again.
5. `Ctrl+V` -> no framing (Ctrl bail); leaves the game's Paste intact.
6. Loads but no camera movement -> check `BepInEx\LogOutput.log` for the
   reflection-failure warning; if present, the plugin fell back to `CenterOnPoint`
   and is again subject to the `cameraFollowBuild` setting.
7. Orbit: select an object (even with the view turned away from it), hold **MMB**
   and drag -> view first snaps to face it, then orbits; horizontal = azimuth,
   vertical = elevation, no flip past the poles. Release, then right-mouse look ->
   no snap. With nothing selected, MMB drag orbits a point straight ahead.
