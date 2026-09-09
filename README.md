# dxmt-aoe4-pack v0.1 — Age of Empires IV on Apple Silicon, open-source graphics

Age of Empires IV (D3D12-only, Arxan-protected) at a **flat 60 fps on a MacBook Air M5**
(95–130 uncapped) and a **flat 60 on an M1 Pro 16 GB** (p99 18.7 ms), with memory
staying at ~4.5–5.5 GB instead of growing 600 MB/min.

Three pieces, all with source, all inside the pack (~450 MB unpacked):

1. **DXMT with the experimental D3D12 layer** (this pack, LGPL) — D3D12 → Metal.
   Fork fixes for this game: tiled-resource probing survives, rect-bounded clears,
   pass-through geometry shaders folded into the VS, disk shader cache, Metal
   encoding off the game thread, per-frame CSV log.
2. **Wine engine with the AoE IV Rosetta patch** (`Engine/`, LGPL 2.1) — our own
   build of CodeWeavers' CrossOver 26.3 / Wine 11.0 source carrying **Marc Ibrahim's
   patch** (published under LGPL), the part that makes the game
   *playable* under Rosetta: invalid-opcode exceptions the anti-tamper uses as control
   flow are delivered in-process instead of through the kernel and Rosetta's exception
   server (~14k kernel traps/s → ~200 per session), and the generated code fragments
   it continues into are de-duplicated into a fixed cache so Rosetta translates each
   one once (this also stops the memory growth). On top of it, our extension of the
   fragment relocator: near conditional branches (`0F 8x rel32`) leaving a fragment
   are relocated too, so more of the anti-tamper's fragments qualify for the cache.
   The Wine-side fix is Marc Ibrahim's; we build it from his published source and
   extend it. Source: `https://github.com/NerRobDog/wine-aoe4`; our diff on top of his tree ships as
   `THIRD_PARTY/wine-aoe-patch-relocator.diff`, plus two small fixes without which Steam could
   not sign in under this engine (`THIRD_PARTY/wine-aoe-patch-syscall-bool.diff`,
   `THIRD_PARTY/wine-aoe-patch-wbemprox.diff`).
3. **x87sidecar** (`Helpers/`, MIT, by athei — fork of Lifeisawful/rosettax87_jit)
   — our build from the MIT source that carries the softfault decoder hook. Attaches cooperatively to the game process and hooks
   Rosetta's decoder in that process only. No SIP changes, no root, nothing
   system-wide. Source: `https://github.com/NerRobDog/x87sidecar`.

You bring: a Mac with Apple Silicon on macOS 26+ and the game — either a CrossOver
bottle where AoE IV (Steam) is installed (used only as the source of the game files), or
nothing at all: without CrossOver, setup.sh creates the prefix and installs the official
Steam client into it, and Steam downloads the game. CrossOver is never needed at runtime.
The engine, the helper and the x86_64 libraries the engine needs (freetype, gnutls,
inotify, …, in `deps/`) are in the pack; the only download is Valve's own Steam
installer in the no-CrossOver case. See `INSTALL.md`.

## Numbers (1v1 skirmish vs AI; the multi-hour runs: online 2v2 between two Macs on this pack vs AI — DXMT HUD + frame log)

| | CrossOver 26.3 + DXMT d3d12 (before) | this pack |
|---|---|---|
| M5 Air, uncapped (`pace = 0`) | 14–18 fps effective, 300–550 ms stall every ~10th frame | p50 9.5 ms (~105 fps), p99 36 ms, avg 95 fps, `Metal: Direct` |
| M5 Air, pack default (pace 60, High, res scale 80%) | — | flat 16.7 ms (54% of frames 16–18 ms), GPU 13–15 ms, present queue depth 0 |
| M1 Pro, pack default (pace 60) | 10–27 fps, same stalls | p50 16.7 / p95 18.1 / p99 18.7 ms, GPU 11 ms, stalls only on map load |
| M1 Pro, `pace = 120`, Low (default on its 120 Hz panel) | — | p50 10.9 / p95 16.0 / p99 65.6 ms over 30 min (105 → 82 fps as the match grows: CPU-bound under Rosetta, GPU 7 ms); `--pace 60` is the flatter line on this chip |
| M1 Pro, earlier build, in-game cap 30 | — | flat 35.7 ms, 29-min match, 0 stalls >150 ms after warm-up |
| memory | +600 MB/min, 13–15 GB in 30–40 min | 4.2 → 4.5 GB (M5, 15 min); 4.7 → 5.45 GB (M1, 29 min); 3.3 → 4.3 GB (M1, pace 60, 10 min) |

Pacing is CPU-side (`d3d12.cpuPacing`) with the in-game V-Sync off: with vsync-slot
pacing (`presentDrawableAfterMinimumDuration`) any rate that is not a divisor of the
panel refresh collapses (50 on a 60 Hz panel → 30 fps); the CPU pacer does not.

## Known limits

- **Tied to one game build.** The Wine patch hard-codes addresses for `RelicCardinal.exe`
  sha256 `5380c577…`; `setup.sh` refuses other builds. A game update means waiting for
  an updated patch + pack.
- The engine is built from Marc Ibrahim's published patch source (hashes in
  `THIRD_PARTY.md`); the pack needs nothing outside itself and Steam.
- Residual 10–15 ms blips ~1/s on the HUD: code fragments the cache refuses. Our
  relocator extension (near conditional branches) shrinks the refused set; its
  in-game effect is not measured yet.
- **Display mode: keep Fullscreen Desktop (or Windowed).** Switching to Exclusive fullscreen in the game's settings crashes it at the transition (`Passed invalid size for a target "Final Target"`); setup.sh resets the profile to Fullscreen Desktop if it finds Exclusive saved.
- Online play works: 2v2 over the network, an M1 Pro and an M5 Air both on this pack, vs two AI, 2–3 hours at a stretch (fresh prefixes, no CrossOver). Ranked or vs humans: not tested.
- Frame pacing is done by the layer (CPU-side, `d3d12.cpuPacing`). setup.sh picks the rate from the panel: 120 Hz ProMotion (MacBook Pro) → 120 fps with in-game Image Quality **Low**; 60 Hz (MacBook Air) → 60 fps with **High**. Keep in-game V-Sync Off and Framerate Limit Unlimited (setup.sh sets both). All knobs in `~/aoe4-pack/aoe4.conf` (pace / patches / hud / metalfx / pending_presents) or as flags (`aoe4.sh --pace 60`); `AOE4_PACE=<fps> bash setup.sh` overrides the default.
- **16 GB Macs: close the browser.** The game wants 4–5 GB resident; with a browser and a few apps open a 16 GB M1 Pro fell to 59 MB free, macOS compressed the game's pages and every burst of compression showed up as a 200–1000 ms stall (11 in 30 min, all in one 8-minute episode). With memory free the same match runs p95 18 ms with zero stalls.
- **Firewalls.** Little Snitch / LuLu will ask about `Engine/bin/wine` (a new binary in a new place) the first time Steam connects; allow it, or Steam sits offline and the game never launches. If you already denied it, fix the rule and relaunch (`aoe4.sh` after `WINEPREFIX=~/aoe4-pack/prefix ~/aoe4-pack/Engine/bin/wineserver -k`).
- **Plug in.** On battery macOS throttles the GPU as the charge gets low: on an M2 Pro a flat 8.3 ms turned into 22 ms GPU frames and 200–500 ms stalls at ~10% battery, and recovered the moment it was charging.
- The Air is fanless: stay at 60. Recommended M5 Air profile: Image Quality High, **Gameplay Resolution Scale 80%** (100% late-game costs 24 ms GPU → 40 fps; 80% brings GPU to 13–15 ms and a flat 60), V-Sync Off, Limit Unlimited (set by setup.sh).

## Rollback

Nothing is installed system-wide. Delete the pack home (default `~/aoe4-pack`).
Your CrossOver bottle (or the Steam library the game files were linked from) is not
modified, with one honest exception: Wine links the prefix's `Documents` to your real
`~/Documents`, so the game profile
(`~/Documents/My Games/Age of Empires IV/configuration_system.lua`) is shared between
the bottle and the pack. The pack edits three values there (V-Sync Off, Framerate Limit
Unlimited, Exclusive → Fullscreen Desktop) and leaves a backup next to it
(`configuration_system.lua.aoe4-pack.bak`); restore it if you go back to plain CrossOver
and want the old values.

## Support

Free and open; if it saved you a licence, see [](DONATE.md) (crypto — card processors are not available where I live) or https://github.com/NerRobDog/satoru/blob/main/DONATE.md.

## Source, credits, licenses

`THIRD_PARTY.md`. DXMT fork: https://github.com/NerRobDog/dxmt (branch `aoe4-d3d12`,
build `v0.80-227-gab639cd`). Wine engine source: `https://github.com/NerRobDog/wine-aoe4` (Marc Ibrahim's
patched CrossOver 26.3 / Wine 11.0 tree + the three diffs in `THIRD_PARTY/`).
x87sidecar source: `https://github.com/NerRobDog/x87sidecar`. No game files, shader caches or Apple
D3DMetal are distributed.
