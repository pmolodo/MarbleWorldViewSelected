# View Selected - Marble World mod

A [BepInEx](https://github.com/BepInEx/BepInEx) plugin for the Unity game
**Marble World** that adds two camera helpers:

- **V** (pressed *without* Ctrl) moves the camera to view ("frame") the currently
  selected object.
- **Middle-mouse drag** orbits the camera (3D-modeler style) around the selection.

The game itself is never modified - the plugin is loaded at runtime by BepInEx.

## Installation

Downloads are on the
[Releases page](https://github.com/pmolodo/MarbleWorldViewSelected/releases).
Pick **one** of the two packages.

First, find your Marble World install folder. In Steam: right-click **Marble
World** -> **Manage** -> **Browse local files**.

### Option A: All-in-one (recommended if you don't already have BepInEx)

This bundles BepInEx together with the plugin.

1. Download `ViewSelected-AllInOne-v<version>_win-x64.zip`.
   (Marble World is 64-bit; only use the `win-x86` build if you are on a 32-bit
   install.)
2. Extract the zip directly into your Marble World install folder, so that the
   `BepInEx` folder and `winhttp.dll` land next to `Marble World.exe`.
3. Launch the game once so BepInEx finishes setting itself up.

### Option B: Plugin only (if BepInEx 5 is already installed)

1. Download `ViewSelected-BepInExPluginOnly-v<version>_win-dotnet.zip`.
2. Extract it and copy `ViewSelected.dll` into
   `<Marble World>/BepInEx/plugins/`.

### Confirming it loaded

After launching the game, open `<Marble World>/BepInEx/LogOutput.log` and look
for a line like:

```
View Selected v1.1.0 loaded
```

To uninstall, delete `ViewSelected.dll` from `BepInEx/plugins` (or remove the
whole `BepInEx` folder + `winhttp.dll` to remove BepInEx as well). The game's own
files are never touched.

## Usage

- **Frame the selection:** select an object, then press **V** (Ctrl not held).
  The camera smoothly pans to look at it. With nothing selected, V does nothing.
- **Orbit:** hold the **middle mouse button** and drag. Horizontal drag orbits
  left/right (azimuth), vertical drag orbits up/down (elevation). It pivots around
  the selected object; with nothing selected it orbits a point straight ahead. If
  the object is off-screen when you start, the view first snaps to face it.
- **Ctrl+V** is left alone - it remains the game's Paste.
- Typing is safe: while a text field is focused (e.g. renaming an object),
  pressing V types a "v" instead of moving the camera.

## Building from source

Requires the .NET SDK. From the project root:

```sh
dotnet build -c Release
```

`make-release.ps1` builds the plugin and produces the two release zips described
above. See [CLAUDE.md](CLAUDE.md) for full build, deploy, and implementation
details.

## License

View Selected is released under the [MIT License](LICENSE). The all-in-one
package also bundles BepInEx, which is likewise MIT-licensed; its license and an
attribution notice are included in that archive.
