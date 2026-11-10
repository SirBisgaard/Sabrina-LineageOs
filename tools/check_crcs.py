#!/usr/bin/env python3
"""Check that stock modules' imported symbol CRCs match a newly built kernel.

Usage: check_crcs.py <Module.symvers> <llvm bin dir> <stock module dir>...
"""
import collections
import os
import pathlib
import struct
import subprocess
import sys
import tempfile

symvers, llvm = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
stock = sorted(p for d in sys.argv[3:] for p in pathlib.Path(d).rglob('*.ko'))
if not stock:
    sys.exit('no stock modules found')

vmlinux = {}
for line in symvers.read_text().splitlines():
    crc, sym, mod = line.split('\t')[:3]
    if mod == 'vmlinux':
        vmlinux[sym] = int(crc, 16)


def imports(ko):
    with tempfile.NamedTemporaryFile() as out:
        subprocess.run([str(llvm / 'llvm-objcopy'), '--dump-section', f'__versions={out.name}', str(ko), os.devnull],
                       check=True, capture_output=True)
        data = pathlib.Path(out.name).read_bytes()
    for i in range(0, len(data), 64):
        yield data[i + 8:i + 64].split(b'\0', 1)[0].decode(), struct.unpack('<Q', data[i:i + 8])[0]


def exports(ko):
    out = subprocess.run([str(llvm / 'llvm-nm'), '--defined-only', str(ko)], capture_output=True, text=True).stdout
    return {line.split()[-1][len('__ksymtab_'):] for line in out.splitlines()
            if line.split() and line.split()[-1].startswith('__ksymtab_')}


provided = set().union(*(exports(ko) for ko in stock))
mismatch, missing = collections.defaultdict(list), collections.defaultdict(list)
checked = 0
for ko in stock:
    for name, crc in imports(ko):
        checked += 1
        if name in vmlinux:
            if vmlinux[name] != crc:
                mismatch[ko.name].append(name)
        elif name not in provided:
            missing[ko.name].append(name)

print(f'stock modules: {len(stock)}  imported symbols: {checked}  CRC mismatches: {len(mismatch)}  unresolved: {len(missing)}')
for label, found in (('mismatch', mismatch), ('unresolved', missing)):
    for ko, names in sorted(found.items()):
        print(f'  {label} {ko}: {", ".join(names[:6])}{" ..." if len(names) > 6 else ""}')
sys.exit(1 if mismatch or missing else 0)
