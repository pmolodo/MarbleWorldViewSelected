# ViewSelected - Marble World mod

Architecture, build/deploy, game-API reference, and verification steps live in
**[DEVELOPING.md](DEVELOPING.md)**. User-facing description, installation, and
usage are in **[README.md](README.md)**. Read those first - the notes below only
call out things that are easy to get wrong.

## Notes for agents

- **Never recompile the game.** This is a BepInEx plugin that calls the game's
  existing public methods at runtime; the game's `Assembly-CSharp.dll` is never
  rebuilt, only read for reference (prefer dnSpyEx / ILSpy on the real DLL, or the
  decompiled scripts under `AssetRipperExports\...`). See "What this project is"
  in [DEVELOPING.md](DEVELOPING.md).
- **Build/deploy:** `./build.ps1` to build, `./deploy.ps1` for a full-cycle test
  install. All build output goes under the gitignored `.build\`. Full details,
  including first-time `.build\lib` provisioning, are in
  [DEVELOPING.md](DEVELOPING.md#build-and-deploy).
