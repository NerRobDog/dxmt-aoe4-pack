#!/bin/bash
# Everything this pack can check without the game, the engine, Steam or the
# network.
#
# There was no tests/ in this pack before this file: dxmt-aoe4-pack's own repo
# (both main and contract-v1-preflight, checked 2026-09-16) has never carried
# one, on any branch. This is the first suite, ported from prime-world-pack's
# test conventions (mktemp'd fixtures, a `check` helper, a suite that has been
# seen to fail against a deliberate mutation - decoration otherwise) rather
# than invented from scratch.
set -u
cd "$(dirname "$0")"

fail=0
for t in test-migrate-prefix-user.sh; do
    echo "== $t"
    bash "$t" || fail=1
    echo
done

for s in ../setup.sh ../aoe4.sh ../uninstall.sh ../bootstrap.sh ../migrate-prefix-user.sh \
         ../tools/check-version.sh ../tools/make-pack.sh; do
    bash -n "$s" || { echo "FAIL  $s does not parse"; fail=1; }
done
[ "$fail" = 0 ] && echo "All shell scripts parse."

for p in ../patch-profile.py ../counters.py; do
    python3 -m py_compile "$p" || { echo "FAIL  $p does not compile"; fail=1; }
done
[ "$fail" = 0 ] && echo "All Python scripts compile."

exit "$fail"
