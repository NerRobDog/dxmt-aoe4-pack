# Third-party components and credits

Everything the pack runs is inside the pack: the Wine engine (`Engine/`), the Rosetta
helper (`Helpers/x87sidecar`), the DXMT binaries (`dxmt/`) and a set of x86_64 runtime
libraries (`deps/`). All of it is built from published source; the hashes below identify
the exact sources. `setup.sh` copies these into the pack home on your machine and never
modifies anything under /Applications.

| Component | Author | License | Source / how we got it |
|---|---|---|---|
| Wine 11.0 (CrossOver 26.3 tree) — `Engine/` | Wine project authors; CodeWeavers (CrossOver changes) | LGPL 2.1 — `LICENSE-Wine.txt` (full text: `LICENSE-LGPL-2.1.txt`) | CodeWeavers' CrossOver 26.3 source as published with GameToMac 0.1.5-alpha (`wine-source.tar.gz`, sha256 `7be5819017b34f09670293f2be7ed9f4476734b8f42dab121a8b74e6619c92a8`); our build: `https://github.com/NerRobDog/wine-aoe4`, commit `cf465d4bbe0fc0bdeeb1023a38bb98810901b547` (recorded in `Engine/.build-id`) |
| AoE IV Rosetta patch inside that Wine (softfault exception delivery + generated-code cache, `dlls/ntdll/unix/aoe_*`) | Marc Ibrahim | LGPL 2.1 (part of the Wine tree) | GameToMac 0.1.5-alpha, https://gametomac.com — zip sha256 `0dff45444531ac36ebf7705795e0470ae93e6ea7d67e4225295d2142bab6fa41`, patched tree = the `wine-source.tar.gz` above. The Wine-side fix is Marc Ibrahim's; we build it from his published source and extend it. |
| Relocator extension of the code cache (near `0F 8x rel32` conditional branches relocated; `AOELAB_CODE_CACHE_DUMP` diagnostics) | NerRobDog | LGPL 2.1 (same tree) | `THIRD_PARTY/wine-aoe-patch-relocator.diff` — diff against Marc Ibrahim's tree; applied in the build at `https://github.com/NerRobDog/wine-aoe4` |
| ntdll (Unix side): BOOLEAN syscall arguments zero-extended explicitly (`NtQueryDirectoryObject`, `NtQueryDirectoryFile`). The PE side writes only the low byte, the Unix side tested the whole register: `GetLogicalDrives` could spin forever inside Steam's hardware survey and Steam never signed in | NerRobDog | LGPL 2.1 (same tree) | `THIRD_PARTY/wine-aoe-patch-syscall-bool.diff` |
| wbemprox: `Win32_Processor.VirtualizationFirmwareEnabled` modelled, `IWbemClassObject::Get` never returns an uninitialized VARIANT (Steam's hardware survey read stack garbage and its connection-manager job spun forever — Steam could not sign in) | NerRobDog | LGPL 2.1 (same tree) | `THIRD_PARTY/wine-aoe-patch-wbemprox.diff` |
| HDE64 (disassembler used by the code cache) | Vyacheslav Patkov | BSD-style, notice in `dlls/ntdll/unix/aoe_hde*` | inside the Wine tree above |
| x87sidecar — `Helpers/x87sidecar` (cooperative Rosetta runtime hook used for the softfault path) | athei (fork of Lifeisawful/rosettax87_jit; the tree we build carries the softfault decoder hook shipped with GameToMac) | MIT — `LICENSE-x87sidecar-MIT.txt` | source `sidecar-source.tar.gz` as published with GameToMac 0.1.5-alpha, sha256 `50ad26b802a590b7c49a121da35ca632bc2676b2fcde40b663805e612d547ff0`; our arm64 build (`cmake -DCMAKE_OSX_ARCHITECTURES=arm64`, Release), binary sha256 `6c7801fb0a9f238146af2002dbd7228f352e8d4a09ead60accd915e2b1bae81e`; repo: `https://github.com/NerRobDog/x87sidecar`, a fork of `athei/x87sidecar` — that tarball is upstream commit `4e9c738` plus Marc Ibrahim's softfault hook, committed there as `4b6bad8` |
| DXMT (D3D11/D3D12 → Metal) — `dxmt/` | 3Shain (upstream), NerRobDog (fork, D3D12 fixes for AoE IV) | LGPL 2.1 — `LICENSE-LGPL-2.1.txt` (also as `LICENSE-DXMT-LGPL.txt`) | https://github.com/NerRobDog/dxmt, branch `aoe4-d3d12`, build `v0.80-227-gab639cd` (commit ab639cd on branch `perf/d3d12-pass-merge`: encoder-chain optimizer, submission batching, drawable prefetch, CPU pacing, pipeline telemetry) |
| x86_64 runtime libraries in `deps/`: freetype 2.14.3, libpng 1.6.58, gnutls 3.8.12, nettle/hogweed 3.10.2, gmp 6.3.0, libtasn1 4.21.0, libidn2 2.3.8, libunistring 1.4.2, p11-kit 0.26.2, gettext 1.0 | upstream projects, binaries from x86_64 Homebrew bottles | FTL, libpng-2.0, LGPL 2.1+/3+, BSD-3 — see `deps/Frameworks/DEPS-MANIFEST.txt` for each file's license and homepage | Homebrew formulae (sources at the listed homepages); nothing from CrossOver |
| libinotify-kqueue (inotify for wineserver) — `deps/libinotify.0.dylib` | Dmitry Matveev, Vladimir Kondratyev | MIT — `deps/LICENSE-libinotify-kqueue.txt` | built from https://github.com/libinotify-kqueue/libinotify-kqueue commit cc614f6 |

Not included, not distributed: Apple's D3DMetal / Game Porting Toolkit,
any game files, prefixes, saves, or shader caches (caches are derivative of game content).

Diagnosis behind this pack (Rosetta retranslation storm + never-evicted translations,
the exception-server profile, the standalone `smc_bench.c` reproduction) was done by
NerRobDog; the Wine-side fix is Marc Ibrahim's — we build it from his published source
and extend it. Thanks to both projects for shipping source.
