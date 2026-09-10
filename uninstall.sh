#!/bin/bash
# dxmt-aoe4-pack: remove what this pack installed, and nothing else.
#
#   ./uninstall.sh --dry-run     list what would go, with sizes, and exit
#   ./uninstall.sh --yes         actually remove it
#
# The pack owns exactly one directory: the home it was given. The game's own
# files are not in it. They live in a Steam library — a CrossOver bottle, a
# native Steam install, or a library satoru manages — and reach the prefix as a
# symlink. Removing a symlink removes the link, so those files are never at
# risk here; `du` is told not to follow them either, or the report would claim
# 45 GB is about to be deleted.
set -u

DEST="${SATORU_GAME_HOME:-${AOE4_PACK_HOME:-$HOME/aoe4-pack}}"
MODE=""
for a in "$@"; do
    case "$a" in
        --dry-run) MODE=dry ;;
        --yes)     MODE=yes ;;
        -h|--help) sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown flag $a" >&2; exit 2 ;;
    esac
done

if [ -z "$MODE" ]; then
    echo "refusing to remove anything without --dry-run or --yes" >&2
    exit 2
fi

if [ ! -d "$DEST" ]; then
    echo "nothing to remove: $DEST does not exist"
    exit 11
fi

# One line per thing, largest first, so the number that matters is at the top.
echo "This would remove:"
for entry in "$DEST"/*; do
    [ -e "$entry" ] || continue
    size=$(du -sh "$entry" 2>/dev/null | cut -f1)
    printf '  %-8s %s\n' "${size:-?}" "$entry"
done
total=$(du -sh "$DEST" 2>/dev/null | cut -f1)
printf '  %-8s %s\n' "${total:-?}" "$DEST (total)"

# Anything the prefix links out to belongs to someone else, and saying so is
# more useful than staying quiet about it.
# No `case` here: its closing paren would end the $( ) substitution early, which
# is a syntax error bash reports on a later line than the one that caused it.
links=$(find "$DEST" -maxdepth 8 -type l 2>/dev/null | while read -r l; do
    t=$(readlink "$l")
    if [ "${t#/}" != "$t" ] && [ -e "$t" ]; then
        echo "  $t"
    fi
done | sort -u)
if [ -n "$links" ]; then
    echo
    echo "Not touched (linked from the prefix, not ours):"
    echo "$links"
fi

if [ "$MODE" = dry ]; then
    exit 0
fi

rm -rf "$DEST"
echo
echo "Removed $DEST"
