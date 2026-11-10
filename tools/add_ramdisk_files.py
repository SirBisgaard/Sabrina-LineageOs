#!/usr/bin/env python3
"""Append regular files (root-owned, 0644) to a gzip'd newc cpio before its trailer.

Usage: add_ramdisk_files.py <in> <out> <archive path>=<local file>...
"""
import gzip
import sys

src, dst, pairs = sys.argv[1], sys.argv[2], sys.argv[3:]
data = gzip.decompress(open(src, 'rb').read())


def pad(n):
    return b'\0' * ((4 - n % 4) % 4)


def entry(ino, mode, name, body):
    fields = [ino, mode, 0, 0, 1, 0, len(body), 0, 0, 0, 0, len(name) + 1, 0]
    header = b'070701' + b''.join(f'{v:08X}'.encode() for v in fields)
    return header + name.encode() + b'\0' + pad(110 + len(name) + 1) + body + pad(len(body))


trailer = data.rfind(b'070701', 0, data.find(b'TRAILER!!!'))
out = bytearray(data[:trailer])
for i, pair in enumerate(pairs):
    name, local = pair.split('=', 1)
    out += entry(900000 + i, 0o100644, name, open(local, 'rb').read())
out += data[trailer:]
open(dst, 'wb').write(gzip.compress(bytes(out), compresslevel=9, mtime=0))
