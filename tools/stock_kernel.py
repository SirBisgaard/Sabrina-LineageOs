#!/usr/bin/env python3
"""Extract the build config and module-signing certificate from a stock lzma kernel."""
import gzip
import lzma
import subprocess
import sys

kernel, config_out, cert_out = sys.argv[1:4]
image = lzma.LZMADecompressor().decompress(open(kernel, 'rb').read())

start = image.find(b'IKCFG_ST')
end = image.find(b'IKCFG_ED', start)
if start < 0 or end < 0:
    sys.exit('stock kernel has no embedded config')
open(config_out, 'wb').write(gzip.decompress(image[start + 8:end]))

certs = []
offset = 0
while (offset := image.find(b'\x30\x82', offset)) >= 0:
    length = int.from_bytes(image[offset + 2:offset + 4], 'big') + 4
    blob = image[offset:offset + length]
    if 300 < length < 4096 and blob not in certs:
        probe = subprocess.run(['openssl', 'x509', '-inform', 'DER', '-noout'], input=blob, capture_output=True)
        if probe.returncode == 0:
            certs.append(blob)
    offset += 2
if len(certs) != 1:
    sys.exit(f'expected exactly one embedded certificate, found {len(certs)}')
open(cert_out, 'wb').write(certs[0])
