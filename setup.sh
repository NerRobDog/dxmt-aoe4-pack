#!/bin/bash
# dxmt-aoe4-pack: one-time setup.
# Builds a self-contained launch environment for Age of Empires IV on Apple Silicon:
#   - this pack's own Wine engine (Engine/: CrossOver 26.3 / Wine 11.0 + the AoE IV Rosetta patch, LGPL) and
#     its own build of the x87sidecar helper (Helpers/, MIT) — see THIRD_PARTY.md; nothing else is downloaded
#   - this pack's DXMT (D3D12 -> Metal) instead of D3DMetal
#   - this pack's bundled x86_64 libraries (freetype, gnutls, ... — see deps/DEPS-MANIFEST.txt); CrossOver is NOT used, at setup or at runtime
#   - a Wine prefix with Steam + the game. Two ways to get one:
#       fresh mode (the default): a new prefix is created with the pack's engine, the official
#                  Steam installer is downloaded from Valve and run silently, and game files are
#                  reused from an existing Steam library - AOE4_STEAMAPPS=/path/to/steamapps, or
#                  the first ~/Games/*/steamapps holding the game - otherwise Steam downloads it;
#       clone mode (AOE4_BOTTLE=/path/to/prefix): an existing Wine prefix with Steam and the game,
#                  such as a former CrossOver bottle, is cloned; game files are symlinked, not copied.
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
# Preflight reads the home's prefix (is the game already in it, is the install
# finished) as well as install building it, so both names come before either.
PREFIX="$DEST/prefix"
STEAMDIR="$PREFIX/drive_c/Program Files (x86)/Steam"

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
# The umbrella reads the exit code to tell a machine that cannot run the game
# (10) from a pack that arrived broken (12) from an unexpected failure (1).
# Everything used to be exit 1, which told it nothing.
die()  { echo "ERROR: $2" >&2; exit "$1"; }

# Which pack built a home. The tarball's SHA256SUMS changes with any file in it;
# a working tree has none, so there the scripts that land in the home stand in
# for it. Missing scripts hash as nothing rather than aborting under set -e: this
# runs as the very last step of an install.
pack_id() {
  if [ -f "$HERE/SHA256SUMS" ]; then
    shasum -a 256 "$HERE/SHA256SUMS"
  else
    { cat "$HERE/setup.sh" "$HERE/aoe4.sh" "$HERE/patch-profile.py" "$HERE/counters.py" "$HERE/migrate-prefix-user.sh" 2>/dev/null || true; } | shasum -a 256
  fi | cut -d' ' -f1
}

# The game is already in the prefix: Steam downloaded it into its own library,
# or an earlier run linked a library in and the link still leads somewhere. A
# real common/ folder counts even before the exe is there - it is Steam's, a
# download may be under way in it, and a link cannot replace it anyway.
prefix_has_game() {
  [ -f "$STEAMDIR/steamapps/common/Age of Empires IV/RelicCardinal.exe" ] && return 0
  [ -d "$STEAMDIR/steamapps/common" ] && [ ! -L "$STEAMDIR/steamapps/common" ]
}

# What aoe4.sh needs to launch, and proof that the run which laid it down got to
# the end. .pack-id is written last, so an install that died half-way - or one
# from an older pack - is not mistaken for this pack's finished home. Game files
# are not required: Steam downloads them on first launch. A link to a library
# is: one that leads nowhere is a repair to run, and so is a link to a library
# other than the one this run was told or found to use.
home_is_complete() {
  [ "$(cat "$DEST/.pack-id" 2>/dev/null)" = "$(pack_id)" ] || return 1
  [ -x "$DEST/aoe4.sh" ] && [ -f "$DEST/aoe4.conf" ] && [ -f "$DEST/patch-profile.py" ] || return 1
  [ -x "$DEST/migrate-prefix-user.sh" ] || return 1
  [ -x "$DEST/Engine/bin/wine" ] && [ -f "$DEST/Engine/lib/wine/x86_64-unix/ntdll.so" ] || return 1
  [ -x "$DEST/Helpers/x87sidecar" ] || return 1
  [ -f "$DEST/deps/Frameworks/libgnutls.30.dylib" ] && [ -f "$DEST/deps/Frameworks/libinotify.dylib" ] || return 1
  [ -f "$DEST/dxmt/x86_64-windows/d3d12.dll" ] || return 1
  # Every library and DXMT dll the pack ships, by name: a home missing one of them
  # is what "re-run setup.sh" in INSTALL.md is there to repair, and a rerun that
  # answered 11 would never get to. The engine is covered by its .engine-id.
  [ -f "$DEST/Engine/.engine-id" ] || return 1
  local f
  while IFS= read -r f; do
    [ -e "$DEST/$f" ] || return 1
  done < <(cd "$HERE" && find deps/Frameworks dxmt -type f ! -name '.DS_Store' 2>/dev/null)
  [ -f "$PREFIX/system.reg" ] && [ -f "$STEAMDIR/steam.exe" ] || return 1
  local common="$STEAMDIR/steamapps/common"
  if [ -L "$common" ] && [ ! -d "$common" ]; then return 1; fi
  if [ "$MODE" = fresh ] && [ -n "$STEAMAPPS" ] && [ "$(readlink "$common" 2>/dev/null)" != "$STEAMAPPS/common" ]; then
    return 1
  fi
  return 0
}

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

  # ---- pick the mode and locate an existing install of the game ----
  # Nothing goes looking for a CrossOver bottle: CrossOver is not part of this pack.
  # A prefix to clone is only ever the one named in AOE4_BOTTLE.
  if [ "$MODE" = auto ]; then
    if [ -n "$BOTTLE" ]; then MODE=clone; else MODE=fresh; fi
  fi
  STEAMAPPS="${AOE4_STEAMAPPS:-}"
  if [ "$MODE" = clone ]; then
    [ -n "$BOTTLE" ] && [ -d "$BOTTLE/drive_c" ] || die 10 "Clone mode needs AOE4_BOTTLE=/path/to/prefix (a Wine prefix with Steam and Age of Empires IV). Or run setup.sh --fresh to install Steam into a new prefix."
    echo "Mode: clone of the prefix $BOTTLE"
    STEAMAPPS="$BOTTLE/drive_c/Program Files (x86)/Steam/steamapps"
  else
    echo "Mode: fresh (the pack's engine + the official Steam installer)"
    if [ -z "$STEAMAPPS" ] && [ -n "$BOTTLE" ]; then STEAMAPPS="$BOTTLE/drive_c/Program Files (x86)/Steam/steamapps"; fi
    if [ -z "$STEAMAPPS" ] && prefix_has_game; then
      # A rerun over a home that already has the game. Looking under ~/Games again
      # would force that library on it: its app manifests over Steam's newer ones,
      # a link refused over Steam's own common/, a different exe build there
      # refusing an update that never needed it. Only an explicit AOE4_STEAMAPPS
      # relinks an existing prefix.
      echo "Game files: already in the prefix ($STEAMDIR/steamapps) - kept, ~/Games not searched"
    elif [ -z "$STEAMAPPS" ]; then
      # Where a Steam library sits once it has been moved out of a CrossOver bottle:
      # ~/Games/<bottle name>/steamapps. Reading it is all that happens here.
      shopt -s nullglob
      for g in "$HOME/Games"/*/steamapps; do
        [ -f "$g/common/Age of Empires IV/RelicCardinal.exe" ] && { STEAMAPPS="$g"; break; }
      done
      shopt -u nullglob
    fi
    if [ -n "$STEAMAPPS" ]; then
      [ -d "$STEAMAPPS/common" ] || die 10 "AOE4_STEAMAPPS=$STEAMAPPS has no common/ folder"
      echo "Game files: reusing the Steam library at $STEAMAPPS (linked, not copied)"
    elif ! prefix_has_game; then
      echo "Game files: none found on this Mac - Steam will download the game (~45 GB) on first launch"
    fi
  fi
  EXE=""; EXE_SHA="(game not installed yet)"
  [ -n "$STEAMAPPS" ] && [ -f "$STEAMAPPS/common/Age of Empires IV/RelicCardinal.exe" ] && EXE="$STEAMAPPS/common/Age of Empires IV/RelicCardinal.exe"
  # A rerun keeps the game already in the prefix and no longer reads ~/Games, but
  # the patch is still wired to one build: the prefix's own exe is the one to check,
  # or a Steam update would pass unnoticed.
  if [ -z "$EXE" ] && [ -z "$STEAMAPPS" ] && [ -f "$STEAMDIR/steamapps/common/Age of Empires IV/RelicCardinal.exe" ]; then
    EXE="$STEAMDIR/steamapps/common/Age of Empires IV/RelicCardinal.exe"
  fi
  if [ -n "$EXE" ]; then
    bold "Verifying game build (the Wine patch is hard-wired to one exe build)..."
    EXE_SHA=$(shasum -a 256 "$EXE" | awk '{print $1}')
    [ "$EXE_SHA" = "$EXE_SHA_EXPECTED" ] || die 10 "RelicCardinal.exe sha256 is $EXE_SHA, expected $EXE_SHA_EXPECTED. The game was updated; the softfault/code-cache patch will NOT engage for this build (it disables itself). Wait for an updated pack."
  fi

  # Refuse only over a wineserver that serves the prefix this run is about to
  # touch: this home's own prefix (a session still running from an earlier
  # launch) or, in clone mode, the bottle being copied, whose registry must not
  # change under the copy. Wine homes of other packs and other games coexist on
  # one Mac, and a wineserver of theirs is no reason to refuse this one. Which
  # prefix a wineserver serves is read from its own WINEPREFIX, as
  # migrate-prefix-user.sh does. The value is resolved to a physical directory
  # before comparing, because Wine takes the same prefix with a trailing slash
  # or through a symlink. Matching on the wineserver binary's path would miss
  # the clone case: the bottle's wineserver is never this pack's Engine/ copy.
  wineserver_serving() {
    local real pid line wp
    [ -d "$1" ] || return 1
    real="$(cd "$1" && pwd -P)"
    for pid in $(pgrep -f 'wineserver' 2>/dev/null); do
      line=" $(ps eww -o command= -p "$pid" 2>/dev/null) "
      case "$line" in *" WINEPREFIX="*) ;; *) continue ;; esac
      wp="${line#* WINEPREFIX=}"; wp="${wp%% *}"
      wp="$(cd "$wp" 2>/dev/null && pwd -P)" || continue
      [ "$wp" = "$real" ] && return 0
    done
    return 1
  }
  wineserver_serving "$PREFIX" && die 10 "wineserver is running against $PREFIX. Quit the other Wine session (and its Steam) first."
  if [ "$MODE" = clone ]; then
    wineserver_serving "$BOTTLE" && die 10 "wineserver is running against the bottle $BOTTLE being cloned. Quit the other Wine session (and its Steam) first."
  fi


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
  echo "satoru: game_files=$([ -n "$STEAMAPPS" ] && echo linked || { prefix_has_game && echo prefix || echo download; })"
  echo "satoru: home=$DEST"

  # Already finished by this very pack is a success, and the contract has a
  # number for it: satoru skips install only on 11, so answering 0 here made
  # every Update fetch Steam's installer, relink and repatch all over again.
  # Finished by another pack is an update waiting to happen, not a success.
  if home_is_complete; then
    echo "Already installed by this pack and complete; nothing to do (delete $DEST/.pack-id to run setup again anyway)."
    exit 11
  fi
}

preflight
# Set by the flag loop, which accepts --preflight anywhere. Reading $1 here meant
# `setup.sh --clone --preflight` answered the question by doing the whole thing.
if [ "$PREFLIGHT_ONLY" = 1 ]; then exit 0; fi

# ---- build $DEST ----
bold "Setting up $DEST"
# A run that fails past this point must not leave a home the previous run called
# finished: home_is_complete trusts .pack-id, so it goes before anything changes.
rm -f "$DEST/.pack-id"
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
cp "$HERE/migrate-prefix-user.sh" "$DEST/migrate-prefix-user.sh"; chmod +x "$DEST/migrate-prefix-user.sh"
sed "s|__DEST__|$DEST|g" "$HERE/aoe4.sh" > "$DEST/aoe4.sh"; chmod +x "$DEST/aoe4.sh"; cp "$DEST/aoe4.sh" "$DEST/aoe4.command"

# Same environment aoe4.sh uses at runtime (engine, bundled x86_64 libs, no Mono/Gecko prompts).
export WINEPREFIX="$PREFIX" WINEARCH=win64 WINELOADER="$DEST/Engine/bin/wine" WINESERVER="$DEST/Engine/bin/wineserver"
export WINEDLLPATH="$DEST/dxmt:$DEST/Engine/lib/wine"
export WINEDLLOVERRIDES="winemenubuilder.exe=;mscoree,mshtml=;gameoverlayrenderer,gameoverlayrenderer64="
export WINEDEBUG=-all WINEMSYNC=1 WINEESYNC=0 ROSETTA_ADVERTISE_AVX=1
export DYLD_LIBRARY_PATH="$DEST/deps/Frameworks" DYLD_FALLBACK_LIBRARY_PATH="$DEST/deps/Frameworks:/usr/lib"

# A prefix kept from an earlier run (clone mode: "already exists - keeping it";
# fresh mode: "already has Steam - keeping it") can still be one an old,
# crossover-answering engine built or last touched. Migrating it here, before
# wineboot or Steam ever runs against it below, is what keeps a half-broken
# kept prefix (system.reg present, steam.exe missing) from having wineboot -u
# build a second, empty "satoru" profile beside the old one. A prefix that does
# not exist yet, or one this pack's own engine already created, costs one
# directory test. The name comes from the engine just laid out in $DEST, not
# from this script: under an engine that still answers "crossover" this file
# is absent and nothing is renamed.
PROFILE_USER="$(tr -d '[:space:]' < "$DEST/Engine/.profile-user" 2>/dev/null || true)"
bash "$HERE/migrate-prefix-user.sh" "$PREFIX" "$PROFILE_USER" \
  || die 1 "the prefix at $PREFIX could not be migrated to the $PROFILE_USER profile"

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
    # A manifest already in the prefix that is newer than the library's is Steam's
    # record of an update made through this prefix; the library's older copy would
    # tell Steam the game is back at the old build. Only missing or older ones go in.
    n=0; kept=0
    for m in "$STEAMAPPS"/appmanifest_*.acf; do
      [ -f "$m" ] || continue
      t="$STEAMDIR/steamapps/$(basename "$m")"
      if [ -f "$t" ] && [ ! "$m" -nt "$t" ]; then kept=$((kept+1)); continue; fi
      cp "$m" "$t"; n=$((n+1))
    done
    echo "  common/ -> $STEAMAPPS/common, $n app manifest(s) copied, $kept newer one(s) in the prefix kept - Steam sees the game as installed (it may validate files once)"
  fi
fi

# The prefix just built or cloned above: a fresh wineboot -u already answers
# "satoru" and this is a no-op, but a clone just rsynced in a former CrossOver
# bottle's C:\users\crossover. Left alone, the first launch of this engine
# would still boot into that prefix, grow a second, empty "satoru" profile next
# to it and leave the player's saves behind, unseen - so this runs before
# patch-profile.py's users/* glob below ever looks for a profile to patch. Same
# engine-declared name as above; re-read in case anything reinstalled Engine/
# between the two calls.
PROFILE_USER="$(tr -d '[:space:]' < "$DEST/Engine/.profile-user" 2>/dev/null || true)"
bash "$HERE/migrate-prefix-user.sh" "$PREFIX" "$PROFILE_USER" \
  || die 1 "the prefix at $PREFIX could not be migrated to the $PROFILE_USER profile"

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
# Last, once everything above has landed: this is what lets the next preflight
# answer 11 instead of doing all of it again.
pack_id > "$DEST/.pack-id"
bold "Done."
cat <<EOF
Launch (from Terminal, or double-click aoe4.command in Finder):
  $DEST/aoe4.sh
A/B without the Rosetta patches (same engine, same DXMT):
  $DEST/aoe4.sh --plain

Steam opens inside the pack's prefix (first launch: Steam updates itself first); sign in if asked, the game auto-launches.
$( [ "$MODE" = fresh ] && [ -z "$STEAMAPPS" ] && ! prefix_has_game && echo "No game files were found on this Mac: Steam will download the game (~45 GB) into $DEST/prefix on first launch." || true )
Frame pacing: $PACE fps by the layer. Settings: $DEST/aoe4.conf (pace/patches/hud/metalfx/pending_presents); profile summary: $DEST/README-local.txt
Frame log: $DEST/telemetry/framelog-aoe4-d3d12-<pid>.csv, patch counters: python3 $DEST/counters.py $DEST/telemetry/counters
EOF
