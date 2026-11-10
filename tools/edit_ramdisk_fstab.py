#!/usr/bin/env python3
"""Rewrite one file inside a gzip'd newc cpio, keeping every other entry byte-identical."""
import gzip
import sys

src, dst, path, drop_prefix = sys.argv[1:5]
data = gzip.decompress(open(src, 'rb').read())
out = bytearray()
pos = 0
changed = 0


def pad(n):
    return (4 - n % 4) % 4


while True:
    header = data[pos:pos + 110]
    assert header[:6] == b'070701', f'not newc at {pos}'
    fields = [int(header[6 + i * 8:14 + i * 8], 16) for i in range(13)]
    namesize, filesize = fields[11], fields[6]
    name_end = pos + 110 + namesize
    name = data[pos + 110:name_end - 1].decode()
    body_start = name_end + pad(110 + namesize)
    body = data[body_start:body_start + filesize]
    next_pos = body_start + filesize + pad(filesize)
    if name == path:
        lines = body.decode().splitlines(keepends=True)
        kept = [l for l in lines if not l.startswith(drop_prefix)]
        assert len(kept) == len(lines) - 1, 'expected exactly one line to drop'
        body = ''.join(kept).encode()
        header = header[:54] + f'{len(body):08X}'.encode() + header[62:]
        changed += 1
    out += header + data[pos + 110:body_start] + body + b'\0' * pad(len(body))
    pos = next_pos
    if name == 'TRAILER!!!':
        out += data[pos:]
        break
assert changed == 1, f'{path} not found'
open(dst, 'wb').write(gzip.compress(bytes(out), compresslevel=9, mtime=0))
