# View Selected - Marble World mod

A [BepInEx](https://github.com/BepInEx/BepInEx) plugin for the Unity game
**Marble World**

Adds two camera helpers:

- **V** (pressed *without* Ctrl) moves the camera to view ("frame") the currently
  selected object.
- **Middle-mouse drag** orbits the camera (3D-modeler style) around the selection.

No original game installation files are altered - the mod is purely additive,
loaded at runtime by BepInEx.

## Installation

First, find your Marble World install folder. In Steam: right-click **Marble
World** -> **Manage** -> **Browse local files**.

Downloads are on the
[Releases page](https://github.com/pmolodo/MarbleWorldViewSelected/releases).
Pick **one** of the two packages.

### Option A: All-in-one (recommended if you don't already have BepInEx)

This bundles BepInEx (a unity modding utility) together with this plugin

1. Download `ViewSelected-AllInOne-v<version>_win-x64.zip`.
   (Marble World is 64-bit; only use the `win-x86` build if you are on a 32-bit
   install.)
2. Extract its **entire contents** into your Marble World install folder, so that
   the `BepInEx` folder and `winhttp.dll` land next to `Marble World.exe`.
3. Launch the game once so BepInEx finishes setting itself up.

### Option B: This plugin only (if BepInEx 5 is already installed)

1. Download `ViewSelected-BepInExPluginOnly-v<version>_win-dotnet.zip`.
2. Extract its **entire contents** into `<Marble World>/BepInEx/plugins/`.

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

### Confirming it loaded

After launching the game, open `<Marble World>/BepInEx/LogOutput.log` and look
for a line like:

```
View Selected v<version> loaded
```

### Uninstalling

Each archive includes an uninstaller that removes exactly what it added. From the
folder where you extracted the archive:

- **Double-click `ViewSelectedPlugin-uninstall.bat`** (or, from a terminal, run
  `ViewSelectedPlugin-uninstall.ps1`).

It reads `ViewSelectedPlugin-manifest.txt` (which lists every file the archive
added, including the uninstaller itself), deletes those files, then removes any
folders left empty - so a clean run leaves nothing behind. It never deletes a
folder that still contains other files, and never touches the folder you ran it
from or anything above it, so the game's own files (and, for the plugin-only
archive, your other BepInEx plugins) are left intact.

If you prefer to do it by hand, just delete every path listed in
`ViewSelectedPlugin-manifest.txt`.

## Building from source

See [DEVELOPING.md](DEVELOPING.md) for full build, deploy, and implementation details.

## License

View Selected is released under the [MIT License](LICENSE). The all-in-one
package also bundles BepInEx, which is likewise MIT-licensed; its license and an
attribution notice are included in that archive.
