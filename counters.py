#!/usr/bin/env python3
"""Read AoE lab diagnostic counters written by the AoE IV Rosetta patch in the pack's own Wine build (AOELAB_COUNTERS_DIR)."""
import glob, os, struct, sys
D = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser('~/aoe4-pack/telemetry/counters')
DIAG = ['PROTECT_CALLS','PROTECT_EXEC_REQUESTED','PROTECT_SUCCESS','PROTECT_EXEC_CHANGED','PROTECT_BYTES',
 'WRITE_CALLS','WRITE_BYTES','ROSETTA_TOGGLE_BATCHES','FLUSH_CALLS','SEGV_SIGNALS','ILLEGAL_TRAPS',
 'GENERAL_PROTECTION_TRAPS','PAGE_FAULTS','PAGE_READ_FAULTS','PAGE_WRITE_FAULTS','PAGE_EXECUTE_FAULTS',
 'SIGNAL_EXCEPTIONS_FORWARDED','FORWARDED_ACCESS_VIOLATIONS','FORWARDED_ILLEGAL_INSTRUCTIONS','GSBASE_REPAIRS',
 'TRAP_SIGNALS','FPE_SIGNALS','RAISE_EXCEPTION_CALLS']
CACHE = {0:'lookups',1:'redirected',2:'hits',3:'inserted',4:'unkeyable',6:'full_or_emit_fail',7:'logical_pc_mapped',8:'used_slots'}
for f in sorted(glob.glob(os.path.join(D, '*.bin')), key=os.path.getmtime):
    b = open(f,'rb').read()
    if len(b) < 32: continue
    hdr = struct.unpack_from('<4Q', b, 0)
    vals = struct.unpack_from('<%dQ' % ((len(b)-32)//8), b, 32)
    print('==', os.path.basename(f), 'pid', hdr[2], 'size', len(b))
    if os.path.basename(f).startswith('codecache'):
        for i,n in CACHE.items(): print('  %-18s %d' % (n, vals[i]))
    else:
        for i,n in enumerate(DIAG): print('  %-28s %d' % (n, vals[i]))
        tab = vals[28:28+256]
        top = sorted([(tab[i*2+1], tab[i*2]) for i in range(128) if tab[i*2]], reverse=True)[:8]
        if top: print('  illegal-trap PC histogram (x1024):', ', '.join('%#x:%d' % (pc,c) for c,pc in top))
