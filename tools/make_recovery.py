#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Builds a recovery image whose factory reset leaves the unlock alone.

Stock recovery's Google plugin (librecovery_ui_ext.so, ChromecastDevice::PostWipeData)
wipes every partition in ro.odm.fdr.extra_wipe_partitions after a factory reset,
including env, which relocks the bootloader. This keeps stock recovery's ramdisk
layout, DTB and recovery DTBO, puts LineageOS's recovery and default plugin built
from the tree in it, removes the wipe list, trusts only the given OTA certificate
and uses our kernel. Every change is read back from the finished image.

Based on prepare_recovery_menu.py from lineageos-23.2-sabrina.

Usage: make_recovery.py --tree T --stock recovery.img --kernel Image.lzma
                        --otacert releasekey.x509.pem --out recovery.img [--avb-key avb.pem]
"""
import argparse
import gzip
import hashlib
import io
import re
import shlex
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

PARTITION_SIZE = 25165824
WIPE = b'ro.odm.fdr.extra_wipe_partitions=cri_data,env,param,tee\n'
USB = (b'ro.recovery.batteryless=true\nro.recovery.usb.vid=18D1\n'
       b'ro.recovery.usb.adb.pid=D001\nro.recovery.usb.fastboot.pid=4EE0\n')


def need(ok, why):
    if not ok:
        sys.exit('error: ' + why)


def run(*args):
    return subprocess.run([str(a) for a in args], check=True, capture_output=True, text=True,
                          errors='replace').stdout


def parse_cpio(raw):
    entries, i = [], 0
    while True:
        need(raw[i:i + 6] == b'070701', f'bad cpio header at {i}')
        fields = [int(raw[i + 6 + 8 * n:i + 14 + 8 * n], 16) for n in range(13)]
        namesize, size = fields[11], fields[6]
        start = i + 110
        name = raw[start:start + namesize - 1].decode()
        data_start = (start + namesize + 3) & ~3
        entries.append({'name': name, 'fields': fields, 'data': raw[data_start:data_start + size]})
        i = (data_start + size + 3) & ~3
        if name == 'TRAILER!!!':
            return entries


def build_cpio(entries):
    out = io.BytesIO()
    for entry in entries:
        fields = list(entry['fields'])
        name = entry['name'].encode() + b'\0'
        fields[6], fields[11] = len(entry['data']), len(name)
        out.write(b'070701' + b''.join(b'%08x' % f for f in fields) + name)
        out.write(b'\0' * (-out.tell() & 3))
        out.write(entry['data'])
        out.write(b'\0' * (-out.tell() & 3))
    out.write(b'\0' * (-out.tell() & 255))
    return out.getvalue()


def unpack(tree, image, folder):
    return run(sys.executable, tree / 'system/tools/mkbootimg/unpack_bootimg.py', '--boot_img', image,
               '--out', folder, '--format', 'mkbootimg')


def main():
    parser = argparse.ArgumentParser()
    for name in ('--tree', '--stock', '--kernel', '--otacert', '--out'):
        parser.add_argument(name, required=True)
    parser.add_argument('--avb-key')
    args = parser.parse_args()
    tree, stock, kernel = Path(args.tree), Path(args.stock), Path(args.kernel)
    built = tree / 'out/target/product/generic/recovery/root'
    avbtool = tree / 'external/avb/avbtool.py'
    cert = Path(args.otacert).read_bytes()
    need(b'BEGIN CERTIFICATE' in cert, 'the OTA certificate is not a PEM certificate')
    need((built / 'system/bin/recovery').is_file() and (built / 'system/bin/init').is_file(),
         'LineageOS recovery is not built in ' + str(built))

    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        argv = unpack(tree, stock, tmp / 'stock')
        raw = gzip.decompress((tmp / 'stock/ramdisk').read_bytes())
        entries = parse_cpio(raw)
        need(build_cpio(entries) == raw, 'stock ramdisk does not round-trip')
        trailer = entries.pop()
        by_name = {e['name']: e for e in entries}
        next_inode = [max(e['fields'][0] for e in entries)]

        def blank(mode, uid=0, gid=0):
            next_inode[0] += 1
            return [next_inode[0], mode, uid, gid, 1, 0, 0, 0, 0, 0, 0, 0, 0]

        def put(name, mode, data, uid=0, gid=0):
            parts = name.split('/')
            for n in range(1, len(parts)):
                folder = '/'.join(parts[:n])
                if folder not in by_name:
                    entry = {'name': folder, 'fields': blank(0o040755), 'data': b''}
                    entries.append(entry)
                    by_name[folder] = entry
            if name in by_name:
                fields = by_name[name]['fields']
                need((fields[1] & 0o170000) != 0o040000, 'would replace a folder: ' + name)
                fields[1:4] = [mode, uid, gid]
                by_name[name]['data'] = data
            else:
                entry = {'name': name, 'fields': blank(mode, uid, gid), 'data': data}
                entries.append(entry)
                by_name[name] = entry

        for path in sorted(built.rglob('*')):
            rel = str(path.relative_to(built))
            if path.is_dir() and not path.is_symlink():
                continue
            uid, gid, perm = (0, 2000, 0o755) if rel.startswith('system/bin/') else (0, 0, 0o644)
            if path.is_symlink():
                put(rel, 0o120777, str(path.readlink()).encode(), uid, gid)
            else:
                put(rel, 0o100000 | perm, path.read_bytes(), uid, gid)
        for path in sorted((tree / 'bootable/recovery/res-xhdpi/images').iterdir()):
            put('res/images/' + path.name, 0o100644, path.read_bytes())

        plugin = by_name['system/lib/librecovery_ui_ext.so']['data']
        need(b'extra_wipe_partitions' not in plugin and b'ChromecastDevice' not in plugin,
             "stock recovery's wipe plugin is still in place")
        prop = by_name['prop.default']
        need(prop['data'].count(WIPE) == 1, 'the wipe list is not in prop.default exactly once')
        prop['data'] = prop['data'].replace(WIPE, b'')
        if b'ro.recovery.usb.vid' not in prop['data']:
            prop['data'] = prop['data'].rstrip(b'\n') + b'\n' + USB

        otacerts = by_name['system/etc/security/otacerts.zip']
        names = zipfile.ZipFile(io.BytesIO(otacerts['data'])).namelist()
        need(len(names) == 1, 'unexpected otacerts.zip layout')
        google_cert = zipfile.ZipFile(io.BytesIO(otacerts['data'])).read(names[0])
        replacement = io.BytesIO()
        with zipfile.ZipFile(replacement, 'w', zipfile.ZIP_STORED) as archive:
            info = zipfile.ZipInfo(names[0], (1980, 1, 1, 0, 0, 0))
            archive.writestr(info, cert)
        otacerts['data'] = replacement.getvalue()

        (tmp / 'ramdisk').write_bytes(gzip.compress(build_cpio(entries + [trailer]), 9, mtime=0))
        cmd = shlex.split(argv)
        for i, arg in enumerate(cmd[:-1]):
            if arg == '--kernel':
                cmd[i + 1] = str(kernel)
            elif arg == '--ramdisk':
                cmd[i + 1] = str(tmp / 'ramdisk')
        need('--recovery_dtbo' in cmd, 'the stock recovery has no recovery DTBO')
        image = tmp / 'recovery.img'
        run(sys.executable, tree / 'system/tools/mkbootimg/mkbootimg.py', *cmd, '--output', image)

        props = re.findall(r"Prop: (\S+) -> '(.*)'", run(sys.executable, '-I', avbtool, 'info_image', '--image', stock))
        need(props, 'stock AVB footer properties missing')
        footer = [sys.executable, '-I', avbtool, 'add_hash_footer', '--image', image, '--partition_name', 'recovery',
                  '--partition_size', PARTITION_SIZE, '--salt', hashlib.sha256(b'recovery.img').hexdigest()]
        if args.avb_key:
            footer += ['--algorithm', 'SHA256_RSA4096', '--key', args.avb_key]
        else:
            footer += ['--algorithm', 'NONE']
        for key, value in props:
            footer += ['--prop', f'{key}:{value}']
        run(*footer)

        result = image.read_bytes()
        need(len(result) == PARTITION_SIZE, 'the image is not partition sized')
        argv_new = unpack(tree, image, tmp / 'new')
        for part in ('dtb', 'second', 'recovery_dtbo'):
            need((tmp / 'new' / part).read_bytes() == (tmp / 'stock' / part).read_bytes(), part + ' changed')
        need((tmp / 'new/kernel').read_bytes() == kernel.read_bytes(), 'the kernel is not ours')
        strip = lambda s: re.sub(r'--(kernel|ramdisk|second|dtb|recovery_dtbo) \S+', '', s).split()
        need(strip(argv) == strip(argv_new), 'the boot header changed')
        final = {e['name']: e for e in parse_cpio(gzip.decompress((tmp / 'new/ramdisk').read_bytes()))}
        need(final['system/bin/recovery']['data'] == (built / 'system/bin/recovery').read_bytes(),
             'the recovery binary differs from the build')
        need(b'extra_wipe_partitions' not in final['prop.default']['data'], 'the wipe list is still present')
        trusted = zipfile.ZipFile(io.BytesIO(final['system/etc/security/otacerts.zip']['data'])).read(names[0])
        need(trusted == cert and trusted != google_cert, 'the OTA certificate was not replaced')
        for name, entry in final.items():
            need(b'by-name/env' not in entry['data'] or name == 'system/bin/systemcontrol_static'
                 or name.endswith('file_contexts'), 'a program writes env: ' + name)
        if args.avb_key:
            run(sys.executable, '-I', avbtool, 'verify_image', '--image', image, '--key', args.avb_key)
        Path(args.out).write_bytes(result)
    print('recovery: ' + args.out)


main()
