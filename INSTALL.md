# Install — 10 minutes

## You need

- Mac with Apple Silicon, **macOS 26 or newer**, Rosetta installed.
- The game, one of two ways:
  - **CrossOver bottle** with **Age of Empires IV (Steam)** installed (clone mode, the
    default when such a bottle exists): the bottle is only read, game files are symlinked
    into a clone. CrossOver itself is not used at runtime — the engine's x86_64 libraries
    ship in `deps/`.
  - **No CrossOver** (fresh mode, automatic when no bottle is found, or `setup.sh --fresh`):
    setup.sh creates a Wine prefix with the pack's engine, downloads the official Steam
    installer from Valve (2.4 MB) and installs it silently. Game files are reused from any
    Steam library it finds (a CrossOver bottle, or `AOE4_STEAMAPPS=/path/to/steamapps`);
    otherwise Steam downloads the game (~45 GB) on first launch. You sign in to Steam once.
- ~4 GB free: the pack itself is ~450 MB unpacked (Wine engine + helper + DXMT +
  libraries), plus the engine copy and the prefix in `~/aoe4-pack` (~3 GB for a bottle
  clone, ~1.5 GB fresh; the 49 GB of game files are symlinked, or downloaded by Steam if
  you have none).

## Steps

1. Download the latest `dxmt-aoe4-pack` tarball from the Releases page and unzip it (double-click) → folder `dxmt-aoe4-pack`. (Or clone this repo and run `bash bootstrap.sh`: it downloads and verifies the archive and runs setup for you.)
2. Quit CrossOver completely (the bottle's Steam too). On a 16 GB Mac also close the browser before playing — the game needs 4–5 GB resident, and memory pressure shows up as multi-hundred-ms stalls.
3. Terminal:

   ```
   cd ~/Downloads/dxmt-aoe4-pack
   bash setup.sh
   ```

   It checks macOS/Rosetta, finds the game, verifies the game exe build, copies the
   pack's Wine engine (`Engine/`) + Rosetta helper (`Helpers/`) + bundled libraries
   into `~/aoe4-pack`, installs this pack's DXMT, probes the helper against your
   Rosetta runtime, and clones the bottle prefix — or, without CrossOver, creates a
   prefix and installs Steam into it (`bash setup.sh --fresh` forces this even if a
   bottle exists). Overrides if auto-detection misses: `AOE4_BOTTLE=…`,
   `AOE4_STEAMAPPS=…` (an existing Steam library to reuse), `AOE4_PACK_HOME=…`,
   `AOE4_STEAM_SETUP=…` (a SteamSetup.exe you already have, skips the download).

4. Launch:

   ```
   ~/aoe4-pack/aoe4.sh
   ```

   (or double-click `~/aoe4-pack/aoe4.command`). Steam opens inside the clone —
   sign in if asked — and the game starts. The DXMT HUD is on by default
   (`MTL_HUD_ENABLED=0 ~/aoe4-pack/aoe4.sh` to hide it).

5. Settings live in **one file**: `~/aoe4-pack/aoe4.conf` (written by setup.sh from your
   hardware; edit and relaunch):

   ```
   pace = 120             # fps the layer paces to (0 = uncapped); setup picks 120 on a 120 Hz panel (Low settings), 60 on a 60 Hz one (High), or AOE4_PACE=<fps>
   patches = on           # Rosetta patches; off = the old stalls (A/B)
   hud = on               # Metal HUD overlay
   metalfx = 0            # MetalFX spatial upscale factor, e.g. 1.33, when GPU-bound
   pending_presents = 2   # present queue depth (1 = lowest latency)
   ```

   One-off overrides: `~/aoe4-pack/aoe4.sh --pace 120 --hud off`; `--print-env` shows what
   will be used without launching. `~/aoe4-pack/README-local.txt` summarizes your profile.
   The in-game V-Sync Off / Framerate Limit Unlimited / Fullscreen Desktop are written
   to the game profile by setup.sh, or before the next launch if the game has not run yet
   (fresh mode) — leave them. Graphics quality is yours: Low for the 120 fps target on a ProMotion Pro, High at 60 (on a fanless Air add Gameplay Resolution Scale 80%).

## A/B

`~/aoe4-pack/aoe4.sh --plain` runs the same engine and DXMT with the Rosetta patches
off — you get the old stalls back. Useful to confirm what the patch does on your machine.

## Telemetry

- Frame times: `~/aoe4-pack/telemetry/framelog-aoe4-d3d12-<pid>.csv`
  (`frame,dt_us,inflight,compiles,encode_us,submits,encoders,qdepth`).
- Patch counters (kernel traps, in-process exceptions, cache hits):
  `python3 ~/aoe4-pack/counters.py ~/aoe4-pack/telemetry/counters`
- Do **not** run `vmmap` on the game while playing — it freezes the process for
  seconds. `top -pid <pid>` is fine.

## FAQ

- **"RelicCardinal.exe sha256 … expected …"** — the game updated; the patch is
  build-specific and would disable itself. Wait for an update.
- **"x87sidecar --probe did not report supported"** — your Rosetta runtime differs
  from the tested macOS 26.5. Not proceeding is the safe choice.
- **"pack is incomplete: Engine/ is missing"** — the archive was not fully unpacked
  (the engine is ~420 MB); unpack it again and re-run `setup.sh`.
- **Steam shows no text / boxes** — `~/aoe4-pack/deps/Frameworks` is missing or
  incomplete; re-run `setup.sh` from a freshly unpacked archive.
- **Launched over SSH and nothing appears** — Wine needs the GUI session; run it from
  Terminal on the Mac itself or `open ~/aoe4-pack/aoe4.command`.
- **Undo** — `rm -rf ~/aoe4-pack`. Nothing else was changed.
