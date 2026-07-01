# ViewSelected - Marble World mod

A BepInEx plugin for the Unity game **Marble World**. It adds a **V** hotkey
(pressed with Ctrl NOT held) that moves the camera to view ("frame") the
currently selected object.

## What this project is

- A small C# class-library (`.csproj`) that compiles to `ViewSelected.dll`, a
  BepInEx plugin. The game is left untouched; the plugin is injected at runtime
  by BepInEx and calls the game's existing public methods. We do NOT recompile
  the game's `Assembly-CSharp.dll`.
- Current scope is the simplest version: on V (Ctrl not held), find the selected
  object, compute its combined renderer-bounds center, and call the game's
  built-in `CameraController.instance.CenterOnPoint(...)` (fixed 5-unit pullback).
- **Key choice:** plain V is unused in-game (only the game's `Ctrl+V` = Paste is
  wired), so V is free to overload - mirroring how the game reuses `r` for
  QuickRotate while `Ctrl+R` is Redo. We explicitly bail when Ctrl is held so
  `Ctrl+V` stays Paste. (The earlier `Ctrl+F` chord was dropped because `f` is
  bound to the game's `SpawnMarbles`, which is not Ctrl-gated, so `Ctrl+F` also
  spawned marbles.)
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
- A planned future version computes the back-off distance from the object's
  bounding-box size + camera FOV (true "fit in frame"), and may use HarmonyX to
  intercept existing methods/input. Not needed for the current version.

## Key facts about the game (verified)

- **Engine:** Unity 2020.1.13f1, **Mono** scripting backend (has
  `Marble World_Data/Managed/Assembly-CSharp.dll`, no `GameAssembly.dll`). Mono
  is the friendly case for modding.
- It is a **DOTS / ECS** game (uses `Unity.Entities`, `Unity.Physics`,
  `Havok.Physics`, etc.). This matters only as background - see "AssetRipper"
  below.
- **Active Input Handling is "Both"**: the game itself uses legacy
  `Input.GetKeyDown` (e.g. `Flipper.cs`, `LogicInput.cs`) as well as the new
  Input System, so our legacy `Input` polling (`V`, plus `Ctrl` for the bail
  check) is safe to use.
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
  `UnityEngine.InputLegacyModule.dll`, ...).
- **BepInEx:** BepInEx 5 (Mono) is installed in the game folder. Core DLLs in
  `<game>\BepInEx\core`; plugins are loaded from `<game>\BepInEx\plugins`;
  runtime log is `<game>\BepInEx\LogOutput.log`.
- **Read-only decompiled game source** (for looking up game APIs):
  `C:\Projects\Games\Marble World\AssetRipperExports\AssetRipper_v1.3.14_export_20260629_165353\Assets\Scripts\Assembly-CSharp`.
  Line numbers cited below refer to these decompiled files. Prefer dnSpyEx /
  ILSpy on the real `Assembly-CSharp.dll` for authoritative reading.

## Game APIs this plugin relies on (all public)

- `CameraController.instance` - singleton. `CenterOnPoint(Vector3)`
  (`CameraController.cs:371`) smooth-damps the camera to
  `focusPoint - cameraForward * 5f`.
  - **Caveat:** `CenterOnPoint` no-ops unless `GameplaySettings.cameraFollowBuild != 0`
    (the in-game "camera follow build" setting). If the plugin loads but the
    camera does not move, this gate is the first thing to check.
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

## Build and deploy

Requires the .NET SDK (`dotnet`; 5.0.416 was used). The project targets
`netstandard2.0`. Game/BepInEx assemblies are referenced via `<HintPath>` with
`<Private>false</Private>` so they are not copied to output - only the plugin
DLL is produced.

```sh
# from the project root (C:\Projects\Games\Marble World\Mods\ViewSelected)
dotnet build -c Release
# then deploy:
cp "bin/Release/netstandard2.0/ViewSelected.dll" \
   "C:/Apps (x86)/Games/Steam/steamapps/common/Marble World/BepInEx/plugins/ViewSelected.dll"
```

Iterate: edit -> `dotnet build -c Release` -> copy DLL -> relaunch the game.

Build gotchas seen in this project:
- The csproj must reference the **`UnityEngine` facade assembly**
  (`UnityEngine.dll`), not just `CoreModule`. BepInEx's `BaseUnityPlugin`
  resolves `MonoBehaviour` through that facade, so without it the build fails to
  find `MonoBehaviour`.
- The MSBuild/`VBCSCompiler` server (and antivirus) can keep `bin`/`obj` or old
  folders locked ("Device or resource busy"). Run `dotnet build-server shutdown`
  before removing/renaming build output.

## Verify (needs the game running)

1. Launch Marble World; check `BepInEx\LogOutput.log` for
   `View Selected v1.0.0 loaded`.
2. Select an object, press V -> camera should smooth-pan to frame it; log shows a
   `viewing '<name>' at <pos>` line.
3. V with nothing selected -> no movement, no exception ("nothing selected").
4. Focus a text field (e.g. rename panel), type a word containing "v" -> camera
   does NOT move (typing guard). Defocus, then V works again.
5. `Ctrl+V` -> no framing (Ctrl bail); leaves the game's Paste intact.
6. Loads but no camera movement -> check the `cameraFollowBuild` setting.

## Background: the abandoned AssetRipper approach

This project started as an attempt to rebuild the entire game with AssetRipper
and edit it directly. That was a dead end - especially for a DOTS game (the
exports hang/crash on import in Unity 2020.1, and decompiled DOTS source throws
many compile errors). **Do not pursue the project rebuild.** The decompiled
scripts under `AssetRipperExports\...` are kept only as a read-only API
reference. Runtime patching via BepInEx is the correct, low-risk path (BepInEx
is fully removable and never modifies the game's own files).
