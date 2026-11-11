#!/usr/bin/env python3
"""Compare two flash sets (super.sparse.img, boot.img, vbmeta.img) by content.

Usage: compare_images.py <dist A> <dist B> [--keep DIR]

Identical images are reported as such. For differing ones it compares what is
inside: the boot image's header, kernel, ramdisk, second stage and DTB, the
super metadata, and every ext4 partition file by file with owners, modes and
extended attributes such as SELinux labels. Needs debugfs. Exits 0 when
everything matches.
"""
import argparse
import hashlib
import os
import shutil
import struct
import subprocess
import sys
import tempfile

DEBUGFS = '/usr/sbin/debugfs'
problems = 0


def report(ok, text):
    global problems
    if not ok:
        problems += 1
    print(('  same    ' if ok else '  DIFFERS ') + text)


def sha(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for block in iter(lambda: f.read(1 << 20), b''):
            h.update(block)
    return h.hexdigest()


def boot_parts(path):
    data = open(path, 'rb').read()
    if data[:8] != b'ANDROID!':
        raise ValueError(f'{path} is not an Android boot image')
    (kernel_size, kernel_addr, ramdisk_size, ramdisk_addr, second_size, second_addr, tags_addr,
     page_size, header_version, os_version) = struct.unpack_from('<10I', data, 8)
    name = data[48:64]
    cmdline = data[64:576].rstrip(b'\0') + data[608:1632].rstrip(b'\0')
    dtb_size = struct.unpack_from('<I', data, 1648)[0] if header_version >= 2 else 0
    recovery_size = struct.unpack_from('<I', data, 1632)[0] if header_version >= 1 else 0

    def pages(size):
        return (size + page_size - 1) // page_size * page_size

    offset = page_size
    layout = (kernel_addr, ramdisk_addr, second_addr, tags_addr, page_size, header_version, os_version, name)
    parts = {'header': repr(layout).encode(), 'cmdline': cmdline}
    for part, size in (('kernel', kernel_size), ('ramdisk', ramdisk_size), ('second', second_size),
                       ('recovery_dtbo', recovery_size), ('dtb', dtb_size)):
        parts[part] = data[offset:offset + size]
        offset += pages(size)
    return parts


def unsparse(sparse, raw):
    with open(sparse, 'rb') as f, open(raw, 'wb') as o:
        magic, _, _, header_size, chunk_header_size, block_size, _, chunks, _ = struct.unpack('<IHHHHIIII', f.read(28))
        if magic != 0xED26FF3A:
            raise ValueError(f'{sparse} is not an Android sparse image')
        f.seek(header_size)
        for _ in range(chunks):
            kind, _, blocks, total = struct.unpack('<HHII', f.read(12))
            f.seek(chunk_header_size - 12, 1)
            size = blocks * block_size
            if kind == 0xCAC1:
                left = size
                while left:
                    block = f.read(min(left, 1 << 22))
                    o.write(block)
                    left -= len(block)
            elif kind == 0xCAC2:
                fill = f.read(4)
                o.write(fill * (size // 4))
            elif kind == 0xCAC3:
                o.seek(size, 1)
            else:
                f.seek(total - chunk_header_size, 1)
        o.truncate()


def lp_partitions(raw):
    with open(raw, 'rb') as f:
        f.seek(4096 * 3)
        header = f.read(4096)
        if struct.unpack_from('<I', header, 0)[0] != 0x414C5030:
            raise ValueError(f'{raw} has no LP metadata')
        header_size = struct.unpack_from('<I', header, 8)[0]
        tables_size = struct.unpack_from('<I', header, 44)[0]
        p_off, p_num, p_size = struct.unpack_from('<III', header, 80)
        e_off, e_num, e_size = struct.unpack_from('<III', header, 92)
        f.seek(4096 * 3 + header_size)
        tables = f.read(tables_size)
    extents = [struct.unpack_from('<QIQI', tables, e_off + i * e_size) for i in range(e_num)]
    result = {}
    for i in range(p_num):
        entry = tables[p_off + i * p_size:p_off + (i + 1) * p_size]
        name = entry[:36].rstrip(b'\0').decode()
        first, count = struct.unpack_from('<II', entry, 40)
        result[name] = [(sectors, data) for sectors, _, data, _ in extents[first:first + count]]
    return result


def extract(raw, extents, out):
    with open(raw, 'rb') as f, open(out, 'wb') as o:
        for sectors, start in extents:
            f.seek(start * 512)
            left = sectors * 512
            while left:
                block = f.read(min(left, 1 << 22))
                o.write(block)
                left -= len(block)


def debugfs(image, commands):
    with tempfile.NamedTemporaryFile('w', suffix='.cmd', delete=False) as f:
        f.write('\n'.join(commands) + '\n')
    try:
        return subprocess.run([DEBUGFS, '-f', f.name, image], capture_output=True, text=True,
                              errors='replace').stdout
    finally:
        os.unlink(f.name)


def ext4_metadata(image):
    entries, level = {}, ['/']
    while level:
        found, current = [], None
        for line in debugfs(image, [f'ls -p "{d}"' for d in level]).splitlines():
            if line.startswith('debugfs:'):
                current = line.split('"')[1] if '"' in line else None
                continue
            parts = line.strip().split('/')
            if current is None or len(parts) < 7 or parts[5] in ('.', '..', ''):
                continue
            path = current.rstrip('/') + '/' + parts[5]
            entries[path] = {'mode': parts[2], 'uid': parts[3], 'gid': parts[4], 'xattr': []}
            if parts[2].startswith('04'):
                found.append(path)
        level = found
    paths = sorted(entries)
    for i in range(0, len(paths), 2000):
        current = None
        for line in debugfs(image, [f'ea_list "{p}"' for p in paths[i:i + 2000]]).splitlines():
            if line.startswith('debugfs:'):
                current = line.split('"')[1] if '"' in line else None
            elif current in entries and '=' in line:
                entries[current]['xattr'].append(line.strip())
    return entries


def ext4_contents(image, dest):
    os.makedirs(dest, exist_ok=True)
    subprocess.run([DEBUGFS, '-R', f'rdump / {dest}', image], capture_output=True)
    subprocess.run(['chmod', '-R', 'u+rwX', dest])
    result = {}
    for root, _, files in os.walk(dest):
        for name in files:
            path = os.path.join(root, name)
            rel = '/' + os.path.relpath(path, dest)
            result[rel] = 'link:' + os.readlink(path) if os.path.islink(path) else sha(path)
    return result


def compare_ext4(name, a, b, work):
    ma, mb = ext4_metadata(a), ext4_metadata(b)
    ca = ext4_contents(a, os.path.join(work, name + '-a'))
    cb = ext4_contents(b, os.path.join(work, name + '-b'))
    lines = []
    for path in sorted(set(ma) | set(mb)):
        if path not in ma or path not in mb:
            lines.append(f'only in {"B" if path not in ma else "A"}: {path}')
            continue
        for key in ('mode', 'uid', 'gid'):
            if ma[path][key] != mb[path][key]:
                lines.append(f'{key} {path}: {ma[path][key]} vs {mb[path][key]}')
        if sorted(ma[path]['xattr']) != sorted(mb[path]['xattr']):
            lines.append(f'xattr {path}')
    lines += [f'content {p}' for p in sorted(set(ca) & set(cb)) if ca[p] != cb[p]]
    report(not lines, f'{name}: {len(ma)} entries, {len(ca)} files compared by content')
    for line in lines:
        print('            ' + line)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('a')
    parser.add_argument('b')
    parser.add_argument('--keep', help='keep unpacked files in this folder')
    args = parser.parse_args()
    work = args.keep or tempfile.mkdtemp(prefix='compare-images-')
    os.makedirs(work, exist_ok=True)
    try:
        print('vbmeta')
        report(sha(os.path.join(args.a, 'vbmeta.img')) == sha(os.path.join(args.b, 'vbmeta.img')), 'vbmeta.img')

        print('boot')
        ba, bb = (boot_parts(os.path.join(d, 'boot.img')) for d in (args.a, args.b))
        for part in ba:
            report(ba[part] == bb[part], part)
        footer_a = open(os.path.join(args.a, 'boot.img'), 'rb').read()
        footer_b = open(os.path.join(args.b, 'boot.img'), 'rb').read()
        report(footer_a == footer_b, 'whole boot.img including the AVB footer')

        print('super')
        raws = []
        for side, d in (('a', args.a), ('b', args.b)):
            raw = os.path.join(work, f'super-{side}.raw')
            unsparse(os.path.join(d, 'super.sparse.img'), raw)
            raws.append(raw)
        pa, pb = lp_partitions(raws[0]), lp_partitions(raws[1])
        report({k: sum(s for s, _ in v) for k, v in pa.items()} == {k: sum(s for s, _ in v) for k, v in pb.items()},
               'partition names and sizes')
        for name in sorted(set(pa) & set(pb)):
            images = []
            for side, raw, table in (('a', raws[0], pa), ('b', raws[1], pb)):
                image = os.path.join(work, f'{name}-{side}.img')
                extract(raw, table[name], image)
                images.append(image)
            if sha(images[0]) == sha(images[1]):
                report(True, f'{name}: byte-identical')
            else:
                compare_ext4(name, images[0], images[1], work)
    finally:
        if not args.keep:
            shutil.rmtree(work, ignore_errors=True)
    print('result:', 'everything matches' if problems == 0 else f'{problems} difference(s)')
    sys.exit(1 if problems else 0)


main()
