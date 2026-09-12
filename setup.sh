#!/bin/bash
# dxmt-aoe4-pack: one-time setup.
# Builds a self-contained launch environment for Age of Empires IV on Apple Silicon:
#   - this pack's own Wine engine (Engine/: CrossOver 26.3 / Wine 11.0 + the AoE IV Rosetta patch, LGPL) and
#     its own build of the x87sidecar helper (Helpers/, MIT) — see THIRD_PARTY.md; nothing else is downloaded
#   - this pack's DXMT (D3D12 -> Metal) instead of D3DMetal
#   - this pack's bundled x86_64 libraries (freetype, gnutls, ... — see deps/DEPS-MANIFEST.txt); CrossOver is NOT needed at runtime
#   - a Wine prefix with Steam + the game. Two ways to get one:
#       clone mode (default when a CrossOver bottle with AoE IV exists): the bottle is cloned,
#                  game files are symlinked, not copied;
#       fresh mode (no CrossOver at all, or `setup.sh --fresh`): a new prefix is created with the
#                  pack's engine, the official Steam installer is downloaded from Valve and run
#                  silently, and game files are reused from an existing Steam library if one is
#                  found (AOE4_STEAMAPPS=/path/to/steamapps) — otherwise Steam downloads the game.
# Nothing inside /Applications is modified.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
DEST="${SATORU_GAME_HOME:-${AOE4_PACK_HOME:-$HOME/aoe4-pack}}"
BOTTLE="${AOE4_BOTTLE:-}"
MODE="${AOE4_MODE:-auto}"     # auto | clone | fresh
PREFLIGHT_ONLY=0
for a in "$@"; do case "$a" in --preflight) PREFLIGHT_ONLY=1 ;; --fresh) MODE=fresh ;; --clone) MODE=clone ;; -h|--help) echo "usage: setup.sh [--preflight] [--fresh|--clone]   env: AOE4_PACK_HOME AOE4_BOTTLE AOE4_STEAMAPPS AOE4_STEAM_SETUP AOE4_PACE"; exit 0 ;; *) echo "unknown flag $a" >&2; exit 2 ;; esac; done
STEAM_SETUP_URL="https://cdn.cloudflare.steamstatic.com/client/installer/SteamSetup.exe"
EXE_SHA_EXPECTED="5380c577805565817f528af6eac385263413fa6815553f9a31fa62561cb45e8c"

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
# The umbrella reads the exit code to tell a machine that cannot run the game
# (10) from a pack that arrived broken (12) from an unexpected failure (1).
# Everything used to be exit 1, which told it nothing.
die()  { echo "ERROR: $2" >&2; exit "$1"; }

preflight() {
  # ---- host checks ----
  # uname -m answers about this process, and a process can be translated: run
  # from a Rosetta shell or an x86_64 interpreter it says x86_64 on an M1.
  # hw.optional.arm64 is a property of the hardware.
  [ "$(sysctl -n hw.optional.arm64 2>/dev/null)" = "1" ] || die 10 "Apple Silicon required."
  OSV=$(sw_vers -productVersion); case "$OSV" in 26.*|27.*) ;; *) die 10 "macOS 26 or newer required (you have $OSV). Rosetta AVX + the helper's hooks are validated on 26.x only.";; esac
  [ -f "$HERE/deps/Frameworks/libgnutls.30.dylib" ] && [ -f "$HERE/deps/Frameworks/libinotify.dylib" ] || die 12 "pack is incomplete: deps/Frameworks is missing. Re-download the archive."
  [ -x "$HERE/Engine/bin/wine" ] && [ -f "$HERE/Engine/lib/wine/x86_64-unix/ntdll.so" ] || die 12 "pack is incomplete: Engine/ is missing. Re-download the archive."
  [ -f "$HERE/Helpers/x87sidecar" ] || die 12 "pack is incomplete: Helpers/x87sidecar is missing. Re-download the archive."
  /usr/bin/arch -x86_64 /usr/bin/true 2>/dev/null || die 10 "Rosetta is not installed. Run: softwareupdate --install-rosetta"

  # ---- locate an existing install of the game (CrossOver bottle) and pick the mode ----
  if [ -z "$BOTTLE" ]; then
    shopt -s nullglob
    for b in "$HOME/Library/Application Support/CrossOver/Bottles"/*; do
      [ -f "$b/drive_c/Program Files (x86)/Steam/steamapps/common/Age of Empires IV/RelicCardinal.exe" ] && { BOTTLE="$b"; break; }
    done
    shopt -u nullglob
  fi
  if [ "$MODE" = auto ]; then
    if [ -n "$BOTTLE" ]; then MODE=clone; else MODE=fresh; fi
  fi
  STEAMAPPS="${AOE4_STEAMAPPS:-}"
  if [ "$MODE" = clone ]; then
    [ -n "$BOTTLE" ] && [ -d "$BOTTLE/drive_c" ] || die 10 "No CrossOver bottle with Age of Empires IV (Steam) found. Set AOE4_BOTTLE=/path/to/bottle, or run setup.sh --fresh to install Steam without CrossOver."
    echo "Mode: clone of CrossOver bottle $BOTTLE"
    STEAMAPPS="$BOTTLE/drive_c/Program Files (x86)/Steam/steamapps"
  else
    echo "Mode: fresh (no CrossOver; the pack's engine + the official Steam installer)"
    if [ -z "$STEAMAPPS" ] && [ -n "$BOTTLE" ]; then STEAMAPPS="$BOTTLE/drive_c/Program Files (x86)/Steam/steamapps"; fi
    if [ -n "$STEAMAPPS" ]; then
      [ -d "$STEAMAPPS/common" ] || die 10 "AOE4_STEAMAPPS=$STEAMAPPS has no common/ folder"
      echo "Game files: reusing the Steam library at $STEAMAPPS (linked, not copied)"
    else
      echo "Game files: none found on this Mac - Steam will download the game (~45 GB) on first launch"
    fi
  fi
  EXE=""; EXE_SHA="(game not installed yet)"
  [ -n "$STEAMAPPS" ] && [ -f "$STEAMAPPS/common/Age of Empires IV/RelicCardinal.exe" ] && EXE="$STEAMAPPS/common/Age of Empires IV/RelicCardinal.exe"
  if [ -n "$EXE" ]; then
    bold "Verifying game build (the Wine patch is hard-wired to one exe build)..."
    EXE_SHA=$(shasum -a 256 "$EXE" | awk '{print $1}')
    [ "$EXE_SHA" = "$EXE_SHA_EXPECTED" ] || die 10 "RelicCardinal.exe sha256 is $EXE_SHA, expected $EXE_SHA_EXPECTED. The game was updated; the softfault/code-cache patch will NOT engage for this build (it disables itself). Wait for an updated pack."
  fi

  if pgrep -q wineserver; then die 10 "wineserver is running. Quit CrossOver / the bottle's Steam first."; fi


  # The helper is probed here, against the unpacked pack, rather than after the
  # engine has been copied: a refusal has to cost nothing. satoru clears the
  # quarantine flag before calling us, but a person running setup.sh by hand has
  # no-one to do it for them, and an ad-hoc-signed binary that still carries the
  # flag is killed by Gatekeeper rather than answering.
  xattr -d com.apple.quarantine "$HERE/Helpers/x87sidecar" 2>/dev/null || true
  bold "Checking the Rosetta helper against your Rosetta runtime..."
  # || true: under `set -euo pipefail` a sidecar that crashes here would abort the
  # script with its own exit code, before the next line can turn that into a 10.
  "$HERE/Helpers/x87sidecar" --probe 2>&1 | tail -3 || true
  "$HERE/Helpers/x87sidecar" --probe 2>&1 | tail -1 | grep -q '^supported' \
    || die 10 "x87sidecar --probe did not report 'supported' - your Rosetta runtime differs from the tested one. Not proceeding."

  # Facts the umbrella shows before anything is written.
  echo "satoru: mode=$MODE"
  [ -n "$BOTTLE" ] && echo "satoru: bottle=$BOTTLE"
  echo "satoru: game_files=$([ -n "$STEAMAPPS" ] && echo linked || echo download)"
  echo "satoru: home=$DEST"
}

preflight
# Set by the flag loop, which accepts --preflight anywhere. Reading $1 here meant
# `setup.sh --clone --preflight` answered the question by doing the whole thing.
if [ "$PREFLIGHT_ONLY" = 1 ]; then exit 0; fi

# ---- build $DEST ----
bold "Setting up $DEST"
mkdir -p "$DEST/Helpers" "$DEST/deps/Frameworks" "$DEST/telemetry/counters" "$DEST/logs"
# The engine is copied (not symlinked) so the pack home stays self-contained; it is refreshed
# when missing or when any file of the pack's Engine/ differs from what was installed (new pack version).
ENGINE_ID=$(cd "$HERE" && find Engine -type f ! -name '.DS_Store' | LC_ALL=C sort | xargs shasum -a 256 | shasum -a 256 | awk '{print $1}')
DEST_ENGINE_ID=$(cat "$DEST/Engine/.engine-id" 2>/dev/null || true)
if [ ! -x "$DEST/Engine/bin/wine" ] || [ "$DEST_ENGINE_ID" != "$ENGINE_ID" ]; then
  echo "Copying Wine engine (~420 MB)..."; rm -rf "$DEST/Engine"; cp -R "$HERE/Engine" "$DEST/Engine"; echo "$ENGINE_ID" > "$DEST/Engine/.engine-id"
else
  echo "Wine engine already installed (same build), keeping it"
fi
cp "$HERE/Helpers/x87sidecar" "$DEST/Helpers/x87sidecar"; chmod +x "$DEST/Helpers/x87sidecar" "$DEST/Engine/bin/"*
rm -rf "$DEST/deps/Frameworks"; mkdir -p "$DEST/deps"
# Pack ships deps/Frameworks/*.dylib. Copy that directory, not deps/ itself —
# `cp -R deps Frameworks` would nest as Frameworks/Frameworks/.
if [ -d "$HERE/deps/Frameworks" ]; then
  cp -R "$HERE/deps/Frameworks" "$DEST/deps/Frameworks"
else
  # Older flat layout: dylibs directly under deps/
  mkdir -p "$DEST/deps/Frameworks"
  cp -R "$HERE/deps"/. "$DEST/deps/Frameworks/"
fi
rm -rf "$DEST/dxmt"; cp -R "$HERE/dxmt" "$DEST/dxmt"
# A downloaded archive carries the quarantine flag; the engine is ad-hoc signed (no Apple
# notarization), so strip the flag from the copies in the pack home or Gatekeeper kills wine.
xattr -dr com.apple.quarantine "$DEST/Engine" "$DEST/Helpers" "$DEST/dxmt" "$DEST/deps" 2>/dev/null || true

# ---- system detection -> frame pacing rate ----
# Default follows the panel: a 120 Hz ProMotion display (MacBook Pro) gets 120 with the
# in-game Image Quality on Low; a 60 Hz panel (MacBook Air) gets 60 with High settings
# (fanless Airs stay cool, and 60 is the sweet spot of the CPU-side pacer there).
# Override with AOE4_PACE=<fps>. Only rates <= the panel refresh make sense.
REFRESH=$(system_profiler SPDisplaysDataType -json 2>/dev/null | python3 -c '
import json,re,sys
try:
    for g in json.load(sys.stdin)["SPDisplaysDataType"]:
        for s in g.get("spdisplays_ndrvs",[]):
            if s.get("spdisplays_main")=="spdisplays_yes":
                m=re.search(r"@ ([0-9.]+)Hz", s.get("_spdisplays_resolution",""))
                print(int(float(m.group(1))) if m else 60); sys.exit()
except Exception: pass
print(60)' 2>/dev/null || echo 60)
CHIP=$(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo "Apple Silicon")
MODEL=$(sysctl -n hw.model 2>/dev/null || echo "?")
GPUCORES=$(system_profiler SPDisplaysDataType -json 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin)["SPDisplaysDataType"][0].get("sppci_cores","?"))' 2>/dev/null || echo "?")
if [ "$REFRESH" -ge 120 ] 2>/dev/null; then DEFAULT_PACE=120; QUALITY_HINT="Image Quality Low (120 fps target)"; else DEFAULT_PACE=60; QUALITY_HINT="Image Quality High; on a fanless Air use Gameplay Resolution Scale 80%"; fi
PACE="${AOE4_PACE:-$DEFAULT_PACE}"
[ "$PACE" -le "$REFRESH" ] 2>/dev/null || { echo "WARNING: AOE4_PACE=$PACE exceeds the panel refresh ($REFRESH Hz); using $REFRESH"; PACE=$REFRESH; }
echo "Detected: $CHIP ($MODEL), $GPUCORES GPU cores, main display $REFRESH Hz -> pacing $PACE fps; in-game: $QUALITY_HINT"
if [ ! -f "$DEST/aoe4.conf" ]; then
  cat > "$DEST/aoe4.conf" <<CONF
# aoe4-pack settings - edit and relaunch (flags: aoe4.sh --pace N --plain --hud off --metalfx X --pending N)
pace = $PACE             # frames per second the layer paces to; 0 = uncapped. Keep <= your panel ($REFRESH Hz).
patches = on           # Rosetta patches (softfault + code cache). off = the old stalls, for A/B.
hud = on               # Metal performance HUD overlay.
metalfx = 0            # MetalFX spatial upscale factor (e.g. 1.33) if GPU-bound; 0 = off.
pending_presents = 2   # present queue depth: 1 = lowest latency, 2 = default, higher = more buffering.
CONF
  echo "Settings written to $DEST/aoe4.conf"
else
  echo "Keeping your existing $DEST/aoe4.conf"
fi
cp "$HERE/dxmt.conf" "$DEST/dxmt.conf.reference"
cp "$HERE/counters.py" "$DEST/counters.py"; cp "$HERE/patch-profile.py" "$DEST/patch-profile.py"
sed "s|__DEST__|$DEST|g" "$HERE/aoe4.sh" > "$DEST/aoe4.sh"; chmod +x "$DEST/aoe4.sh"; cp "$DEST/aoe4.sh" "$DEST/aoe4.command"

PREFIX="$DEST/prefix"
# Same environment aoe4.sh uses at runtime (engine, bundled x86_64 libs, no Mono/Gecko prompts).
export WINEPREFIX="$PREFIX" WINEARCH=win64 WINELOADER="$DEST/Engine/bin/wine" WINESERVER="$DEST/Engine/bin/wineserver"
export WINEDLLPATH="$DEST/dxmt:$DEST/Engine/lib/wine"
export WINEDLLOVERRIDES="winemenubuilder.exe=;mscoree,mshtml=;gameoverlayrenderer,gameoverlayrenderer64="
export WINEDEBUG=-all WINEMSYNC=1 WINEESYNC=0 ROSETTA_ADVERTISE_AVX=1
export DYLD_LIBRARY_PATH="$DEST/deps/Frameworks" DYLD_FALLBACK_LIBRARY_PATH="$DEST/deps/Frameworks:/usr/lib"
STEAMDIR="$PREFIX/drive_c/Program Files (x86)/Steam"

if [ "$MODE" = clone ]; then
  # The contract has no update command: an update is this script run again, and
  # MODE=auto finds the same bottle every time. A prefix that is already here has
  # been played in, and rsyncing the bottle over it puts the bottle's months-old
  # user.reg, Steam configuration and game profile back on top of the player's.
  # The fresh branch below has always kept an existing prefix; this one did not.
  if [ -f "$PREFIX/system.reg" ]; then
    echo "Prefix $PREFIX already exists - keeping it (delete the folder to clone the bottle again)"
  else
  bold "Cloning the bottle prefix (game files are symlinked, ~2-3 GB copied)..."
  mkdir -p "$PREFIX"
  rsync -a --exclude "drive_c/Program Files (x86)/Steam/steamapps/common" "$BOTTLE/" "$PREFIX/"
  ln -sfn "$STEAMAPPS/common" "$STEAMDIR/steamapps/common"
  ln -sfn "$HOME" "$PREFIX/dosdevices/y:" 2>/dev/null || true
  # CrossOver links the bottle user's Documents/Downloads/... to the macOS home. If the bottle
  # came from another machine or user those links dangle: replace them with real folders so the
  # game gets a working profile directory (the original bottle is untouched).
  for u in "$PREFIX"/drive_c/users/*/; do
    for d in Documents Downloads Music Pictures Videos Desktop; do
      L="$u$d"
      if [ -L "$L" ] && [ ! -e "$L" ]; then
        T=$(readlink "$L"); rm "$L"; mkdir -p "$L"
        echo "  WARNING: $L pointed to $T (not on this Mac) - replaced with a real folder; copy your game profile there if you have one"
      fi
    done
  done
  fi
else
  if [ -f "$STEAMDIR/steam.exe" ]; then
    echo "Prefix $PREFIX already has Steam - keeping it (delete the folder to start over)"
  else
    bold "Creating a new Wine prefix with the pack's engine ($PREFIX)..."
    mkdir -p "$PREFIX"
    "$DEST/Engine/bin/wine" wineboot -u >/dev/null 2>&1 || die 1 "wineboot failed (run with WINEDEBUG=err+all for details)"
    "$DEST/Engine/bin/wineserver" -w
    [ -f "$PREFIX/system.reg" ] || die 1 "wineboot did not produce a prefix"
    # Official Steam installer, straight from Valve. AOE4_STEAM_SETUP=/path/SteamSetup.exe skips the download.
    mkdir -p "$DEST/downloads"
    SETUP="${AOE4_STEAM_SETUP:-$DEST/downloads/SteamSetup.exe}"
    if [ ! -f "$SETUP" ]; then
      bold "Downloading the Steam installer from $STEAM_SETUP_URL ..."
      curl -fL --progress-bar -o "$SETUP.part" "$STEAM_SETUP_URL" || die 1 "download failed - check the connection or put SteamSetup.exe at $SETUP"
      mv "$SETUP.part" "$SETUP"
    fi
    head -c 2 "$SETUP" | grep -q 'MZ' || die 12 "$SETUP is not a Windows executable"
    xattr -d com.apple.quarantine "$SETUP" 2>/dev/null || true
    bold "Installing Steam silently (SteamSetup.exe /S) ..."
    "$DEST/Engine/bin/wine" "$SETUP" /S >/dev/null 2>&1 || true
    "$DEST/Engine/bin/wineserver" -w
    [ -f "$STEAMDIR/steam.exe" ] || die 1 "Steam did not install (no $STEAMDIR/steam.exe). Run: WINEDEBUG=err+all $DEST/Engine/bin/wine $SETUP"
    echo "  Steam installed in $STEAMDIR (it updates itself on first launch, then asks you to sign in)"
  fi
  if [ -n "$STEAMAPPS" ]; then
    bold "Linking the existing game files into the new prefix..."
    mkdir -p "$STEAMDIR/steamapps"
    if [ -e "$STEAMDIR/steamapps/common" ] && [ ! -L "$STEAMDIR/steamapps/common" ]; then
      die 10 "$STEAMDIR/steamapps/common already exists as a real folder; move it away or unset AOE4_STEAMAPPS"
    fi
    ln -sfn "$STEAMAPPS/common" "$STEAMDIR/steamapps/common"
    n=0; for m in "$STEAMAPPS"/appmanifest_*.acf; do [ -f "$m" ] || continue; cp "$m" "$STEAMDIR/steamapps/"; n=$((n+1)); done
    echo "  common/ -> $STEAMAPPS/common, $n app manifest(s) copied - Steam sees the game as installed (it may validate files once)"
  fi
fi

# ---- in-game settings: V-Sync off, framerate limit unlimited, fullscreen desktop ----
# The layer paces the frame; the game's own V-Sync (SyncInterval=1) would hold
# drawables on refresh slots and its limiter is far jittier than ours.
bold "Setting in-game V-Sync = Off and Framerate Limit = Unlimited in the game profile..."
python3 "$DEST/patch-profile.py" "$PREFIX"

cat > "$DEST/README-local.txt" <<LOCAL
aoe4-pack profile - $(date '+%Y-%m-%d %H:%M')
Machine: $CHIP ($MODEL), $GPUCORES GPU cores, macOS $OSV, main display $REFRESH Hz
Pacing: $PACE fps (aoe4.conf: pace), CPU-side; in-game V-Sync Off + Limit Unlimited written to the game profile
Engine: dxmt-aoe4-pack own Wine build (CrossOver 26.3 / Wine 11.0 + AoE IV Rosetta patch), ntdll.so sha256 $(shasum -a 256 "$DEST/Engine/lib/wine/x86_64-unix/ntdll.so" | cut -c1-12); DXMT: $( (strings "$DEST/dxmt/x86_64-windows/d3d12.dll" | grep -m1 'v0.80-') 2>/dev/null || true)
Mode: $MODE; game files: ${STEAMAPPS:-downloaded by Steam}
Game: ${EXE:-not installed yet} (sha256 $EXE_SHA)
Settings: $DEST/aoe4.conf   Advanced: $DEST/dxmt.extra.conf   Resolved view: $DEST/aoe4.sh --print-env
Recommended in-game: $QUALITY_HINT. V-Sync Off + Framerate Limit Unlimited are set in the profile.
LOCAL
bold "Done."
cat <<EOF
Launch (from Terminal, or double-click aoe4.command in Finder):
  $DEST/aoe4.sh
A/B without the Rosetta patches (same engine, same DXMT):
  $DEST/aoe4.sh --plain

Steam opens inside the pack's prefix (first launch: Steam updates itself first); sign in if asked, the game auto-launches.
$( [ "$MODE" = fresh ] && [ -z "$STEAMAPPS" ] && echo "No game files were found on this Mac: Steam will download the game (~45 GB) into $DEST/prefix on first launch." || true )
Frame pacing: $PACE fps by the layer. Settings: $DEST/aoe4.conf (pace/patches/hud/metalfx/pending_presents); profile summary: $DEST/README-local.txt
Frame log: $DEST/telemetry/framelog-aoe4-d3d12-<pid>.csv, patch counters: python3 $DEST/counters.py $DEST/telemetry/counters
EOF
