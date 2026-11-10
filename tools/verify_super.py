#!/usr/bin/env python3
"""Read every partition back out of a raw super image by its lpdump extents and compare hashes.

Usage: verify_super.py <raw super> <lpdump output> <image dir>
"""
import hashlib
import pathlib
import re
import sys

raw, dump, images = sys.argv[1], pathlib.Path(sys.argv[2]).read_text(), pathlib.Path(sys.argv[3])
table = dump.split('Partition table:', 1)[1].split('Super partition layout:', 1)[0]
spans, ok = [], True
with open(raw, 'rb') as stream:
    for name, body in re.findall(r'  Name: (\w+)\n(.*?)(?=  Name: |\Z)', table, re.S):
        digest, logical = hashlib.sha256(), 0
        for first, last, physical in re.findall(r'\s+(\d+) \.\. (\d+) linear super (\d+)', body):
            first, last, physical = int(first), int(last), int(physical)
            assert first == logical, name
            length = (last - first + 1) * 512
            spans.append((physical * 512, physical * 512 + length))
            stream.seek(physical * 512)
            left = length
            while left:
                chunk = stream.read(min(left, 1 << 20))
                digest.update(chunk)
                left -= len(chunk)
            logical = last + 1
        source = images / f'{name}.img'
        match = logical * 512 == source.stat().st_size and \
            digest.hexdigest() == hashlib.sha256(source.read_bytes()).hexdigest()
        ok &= match
        print(f'{name:12} {logical * 512:>11}  {"matches" if match else "DIFFERS"}')
spans.sort()
ok &= all(a[1] <= b[0] for a, b in zip(spans, spans[1:]))
sys.exit(0 if ok else 1)
