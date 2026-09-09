#!/usr/bin/env python3
# dxmt-aoe4-pack: in-game settings the layer needs: V-Sync = Off, Framerate Limit = Unlimited,
# window mode = Fullscreen Desktop. Idempotent; called by setup.sh and before every launch by
# aoe4.sh (a fresh prefix has no profile until the game ran once). One-time backup next to the file.
#   patch-profile.py <wineprefix> [--quiet]
import glob, os, re, sys
prefix = sys.argv[1]
quiet = "--quiet" in sys.argv[2:]
files = glob.glob(os.path.join(prefix, "drive_c", "users", "*", "Documents", "My Games", "Age of Empires IV", "configuration_system.lua"))
if not files:
    if not quiet:
        print("  WARNING: no configuration_system.lua in this prefix yet (the game has not been launched from it).")
        print("           It is patched automatically before the next launch once it exists; until then set")
        print("           V-Sync Off + Framerate Limit Unlimited in Graphics settings yourself.")
    sys.exit(0)
for f in files:
    s = open(f, encoding="utf-8", errors="replace").read()
    orig = s
    n1 = len(re.findall(r'setting = "verticalsync",\s*variantBool = true', s))
    s = re.sub(r'(setting = "verticalsync",\s*variantBool = )true', r'\1false', s)
    s, n2 = re.subn(r'(setting = "frameratelimit",\s*variantUInt = )(?!0\b)\d+', r'\g<1>0', s)
    # Exclusive fullscreen (windowmode 1) crashes at the compositor transition ("Passed invalid
    # size for a target"): keep Fullscreen Desktop (3), the mode everything was tested in.
    s, n3 = re.subn(r'(setting = "windowmode",\s*variantUInt = )1\b', r'\g<1>3', s)
    if s == orig:
        if not quiet: print(f"  profile already set: {f}")
        continue
    # Documents may be linked to the real macOS home, so this can be the user's live game
    # profile (shared with a CrossOver bottle): keep a one-time backup next to it.
    bak = f + ".aoe4-pack.bak"
    if not os.path.exists(bak):
        open(bak, "w", encoding="utf-8").write(orig); print("  backup: " + bak)
    open(f, "w", encoding="utf-8").write(s)
    if n3: print("  windowmode: Exclusive -> Fullscreen Desktop (exclusive fullscreen crashes the game under this layer)")
    print(f"  patched {f}: verticalsync->false ({n1} changed), frameratelimit->0 ({n2} changed)")
