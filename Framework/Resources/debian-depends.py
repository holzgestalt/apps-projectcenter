#!/usr/bin/env python3
#
# debian-depends.py: the Depends of a Debian package built against a sysroot
# that debian-sysroot.py made: the packages of the shared libraries that the
# ELF files in FOLDER need, other than those FOLDER holds itself.
#
#   debian-depends.py [--gnustep PREFIX PACKAGE] [--capabilities] SYSROOT FOLDER
#
# With --gnustep, the libraries in SYSROOT/PREFIX (GNUstep, which is not from
# the distribution) are PACKAGE's. With --capabilities, for an RPM built
# against a sysroot that fedora-sysroot.py made, the libraries are named as
# rpm's capabilities (libgtk-4.so.1()(64bit)) rather than by their packages,
# as rpmbuild finds them on Fedora; GNUstep's are still PACKAGE.
#
# This file is part of GNUstep ProjectCenter.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.

import argparse
import struct
import sys
from pathlib import Path


def needed(path):
    """The DT_NEEDED names of a 64-bit little-endian ELF file, or None."""
    data = path.read_bytes()
    if data[:4] != b'\x7fELF' or data[4] != 2 or data[5] != 1:
        return None
    shoff, = struct.unpack_from('<Q', data, 0x28)
    shentsize, shnum = struct.unpack_from('<HH', data, 0x3a)
    sections = [struct.unpack_from('<IIQQQQIIQQ', data, shoff + i * shentsize) for i in range(shnum)]
    names = []
    for _, kind, _, _, offset, size, link, _, _, entsize in sections:
        if kind != 6:  # SHT_DYNAMIC
            continue
        strtab = sections[link]
        for i in range(0, size, entsize or 16):
            tag, value = struct.unpack_from('<qQ', data, offset + i)
            if tag == 0:
                break
            if tag == 1:  # DT_NEEDED
                start = strtab[4] + value
                names.append(data[start:data.index(b'\0', start)].decode())
    return names


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--gnustep', nargs=2, metavar=('PREFIX', 'PACKAGE'))
    parser.add_argument('--capabilities', action='store_true')
    parser.add_argument('sysroot', type=Path)
    parser.add_argument('folder', type=Path)
    args = parser.parse_args()
    sysroot, folder = args.sysroot, args.folder
    owners = {}
    for line in (sysroot / 'files.tsv').read_text().splitlines():
        path, package = line.split('\t')
        owners[Path(path).name] = owners.get(Path(path).name) or package
    gnustep = set()
    if args.gnustep:
        prefix, package = args.gnustep
        for path in (sysroot / prefix.lstrip('/')).rglob('*.so*'):
            owners[path.name] = package
            gnustep.add(path.name)
    own = {p.name for p in folder.rglob('*') if p.is_file() or p.is_symlink()}
    packages = set()
    missing = set()
    for path in folder.rglob('*'):
        if path.is_symlink() or not path.is_file():
            continue
        for name in needed(path) or []:
            if name in own:
                continue
            if name in owners:
                packages.add(f'{name}()(64bit)' if args.capabilities and name not in gnustep else owners[name])
            else:
                missing.add(name)
    for name in sorted(missing):
        print(f'warning: no package in the sysroot has {name}', file=sys.stderr)
    print(', '.join(sorted(packages)))


if __name__ == '__main__':
    main()
