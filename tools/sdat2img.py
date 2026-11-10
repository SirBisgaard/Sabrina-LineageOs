#!/usr/bin/env python3
# Simple sdat2img: reads transfer.list and new.dat, writes raw image.
# Handles 'new' and 'zero'; erase is a no-op; unsupported ops abort.
import sys, os
BLK = 4096
def parse_rs(s):
    parts = s.split(',')
    n = int(parts[0]); nums = [int(x) for x in parts[1:]]
    assert len(nums) == n and n % 2 == 0
    return [(nums[2*i], nums[2*i+1]) for i in range(n//2)]
def main(tlist, newdat, out):
    with open(tlist) as f:
        lines = [l.strip() for l in f.read().splitlines()]
    ver = int(lines[0]); nblocks = int(lines[1]); i = 4  # skip stash lines
    with open(newdat,'rb') as nd, open(out,'wb') as img:
        max_end = 0
        while i < len(lines):
            parts = lines[i].split(' ',1); i += 1
            cmd = parts[0]; rs = parse_rs(parts[1]) if len(parts)>1 else []
            if cmd == 'new':
                for b,e in rs:
                    img.seek(b*BLK)
                    img.write(nd.read((e-b)*BLK))
                    max_end = max(max_end, e)
            elif cmd == 'zero':
                for b,e in rs:
                    img.seek(b*BLK)
                    img.write(b'\x00'*((e-b)*BLK))
                    max_end = max(max_end, e)
            elif cmd in ('erase',):
                for b,e in rs: max_end = max(max_end, e)
            else:
                sys.exit(f"unsupported op: {cmd}")
        img.truncate(max(max_end,nblocks)*BLK)
if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2], sys.argv[3])
