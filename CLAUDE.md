# ViewSelected - Marble World mod

Architecture, build/deploy, game-API reference, and verification steps live in
**[DEVELOPING.md](DEVELOPING.md)**. User-facing description, installation, and
usage are in **[README.md](README.md)**. Read those first - the notes below only
call out things that are easy to get wrong.

## Notes for agents

- **Never recompile the game.** This is a BepInEx plugin that calls the game's
  existing public methods at runtime; the game's `Assembly-CSharp.dll` is never
  rebuilt. See "What this project is" in [DEVELOPING.md](DEVELOPING.md).
- **Do not pursue the AssetRipper "rebuild the whole game" approach** - it is an
  abandoned dead end (see "Background" in [DEVELOPING.md](DEVELOPING.md)). The
  decompiled scripts under `AssetRipperExports\...` are a read-only API reference
  only; prefer dnSpyEx / ILSpy on the real `Assembly-CSharp.dll`.
- **Build/deploy:** `./build.ps1` to build, `./deploy.ps1` for a full-cycle test
  install. All build output goes under the gitignored `.build\`. Full details,
  including first-time `.build\lib` provisioning, are in
  [DEVELOPING.md](DEVELOPING.md#build-and-deploy).
