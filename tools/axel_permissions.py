#!/usr/bin/env python3
"""Write privapp and default-permission files for stock TVAxel from a stock product tree.

Usage: axel_permissions.py <aapt2> <stock product dir> <output dir>
"""
import pathlib
import re
import subprocess
import sys

aapt2, product, out = sys.argv[1], pathlib.Path(sys.argv[2]), pathlib.Path(sys.argv[3])
badging = subprocess.run([aapt2, 'dump', 'badging', str(product / 'priv-app/TVAxel/TVAxel.apk')],
                         capture_output=True, text=True, check=True).stdout
names = set(re.findall(r"uses-permission(?:-sdk-23)?: name='([^']+)'", badging))

stock = (product / 'etc/permissions/privapp-permissions-atv-product.xml').read_text()
entry = re.search(r'<privapp-permissions package="com\.google\.android\.tv\.axel">.*?</privapp-permissions>', stock, re.S)[0]
names |= set(re.findall(r'<permission name="([^"]+)"', entry))
deny = set(re.findall(r'<deny-permission name="([^"]+)"', entry))

lines = ['<?xml version="1.0" encoding="utf-8"?>', '<permissions>',
         '    <privapp-permissions package="com.google.android.tv.axel">']
lines += [f'        <permission name="{n}"/>' for n in sorted(names - deny)]
lines += [f'        <deny-permission name="{n}"/>' for n in sorted(deny)]
lines += ['    </privapp-permissions>', '</permissions>', '']
(out / 'privapp-permissions-sabrina-axel.xml').write_text('\n'.join(lines))

defaults = (product / 'etc/default-permissions/default-atv-permissions.xml').read_text()
exception = re.search(r'<exception\s+package="com\.google\.android\.tv\.axel".*?</exception>', defaults, re.S)[0]
(out / 'default-sabrina-axel.xml').write_text(
    '<?xml version="1.0" encoding="utf-8"?>\n<exceptions>\n    ' + exception + '\n</exceptions>\n')
