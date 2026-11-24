#!/usr/bin/env python3
#
# debian-sysroot.py: makes a Debian sysroot without Debian, Docker or root:
# it downloads the packages a GNUstep build links against (and their
# dependencies) from a Debian mirror and unpacks them into one folder.
#
#   debian-sysroot.py --arch arm64 --release trixie SYSROOT [PACKAGE...]
#
# SYSROOT/packages.txt lists the packages and their versions, and
# SYSROOT/files.tsv which package each file comes from.
#
# The packages are checked against the SHA-256 sums of the release's
# Packages index, whose own sum is checked against the release's InRelease
# file (fetched over HTTPS; its signature is not checked). Tools,
# interpreters and documentation that a sysroot doesn't need are left out.
# Absolute symbolic links are made relative, so they point into the sysroot.
#
# This file is part of GNUstep ProjectCenter.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.

import argparse
import hashlib
import io
import lzma
import os
import re
import ssl
import sys
import tarfile
import urllib.request
from pathlib import Path, PurePosixPath

# What GNUstep (libobjc2, base, gui, back) and the GTK4Native theme link
# against: the -dev packages of gnustep-image.sh, without the optional ones.
DEFAULT_PACKAGES = '''
libc6-dev linux-libc-dev libgcc-14-dev libstdc++-14-dev robin-map-dev
libffi-dev libicu-dev libgnutls28-dev libssl-dev libxml2-dev libxslt1-dev
zlib1g-dev libgmp-dev libcurl4-gnutls-dev
libjpeg-dev libtiff-dev libpng-dev libgif-dev
libfreetype-dev libfontconfig-dev libcairo2-dev libx11-dev libxext-dev
libxt-dev libxft-dev libxrender-dev libxrandr-dev libxmu-dev
libgtk-4-dev
'''.split()

# Packages a sysroot doesn't need: programs, interpreters, services, data.
SKIPPED = re.compile(r'''^(
    perl(-.*)? | libperl.* | python3.* | libpython3.* |
    debconf.* | dpkg.* | coreutils | bash | dash | sensible-utils | install-info |
    init-system-helpers | adduser | passwd | login.* | systemd.* | libsystemd-shared | udev |
    sysvinit-utils | lsb-base | ucf | tzdata | media-types | mime-support |
    gcc(-\d+)? | cpp(-\d+)?(-.*)? | g\+\+(-\d+)? | binutils.* | libc-bin | libc-dev-bin | rpcsvc-proto |
    dconf-service | dbus.* | default-dbus.* | gsettings-desktop-schemas |
    adwaita-icon-theme | hicolor-icon-theme | fonts-.* | fontconfig | x11-common |
    libglib2\.0-bin | libglib2\.0-dev-bin | libgtk-4-bin | libgtk-4-media-.* |
    gir1\.2-.* | libgirepository.*-dev | gobject-introspection.* |
    libllvm.* | clang.* | llvm.* | mesa-libgallium | libgl1-mesa-dri | cdebconf | libdebian-installer.* | .*-doc | .*-dbg | xkb-data | libglib2\.0-data |
    libgtk-4-common | libgdk-pixbuf2\.0-common | libgdk-pixbuf2\.0-bin | libgdk-pixbuf-2\.0-0-bin |
    libwayland-bin | wayland-protocols | pkgconf(-bin)? | pkg-config | libpkgconf\d* | icu-devtools |
    cmake.* | uuid-runtime | mount | util-linux.* | libudev-dev
)$''', re.X)

# Paths left out of every package.
SKIPPED_PATHS = ('usr/share/doc/', 'usr/share/man/', 'usr/share/info/', 'usr/share/locale/',
                 'usr/share/lintian/', 'usr/share/bug/', 'usr/share/gtk-doc/', 'usr/share/help/',
                 'usr/bin/', 'usr/sbin/', 'bin/', 'sbin/', 'etc/init.d/', 'usr/lib/systemd/')


def tls_context():
    # python.org's Python on macOS comes without CA certificates until its
    # "Install Certificates" step is run: use the system's bundle then.
    context = ssl.create_default_context()
    if not context.cert_store_stats().get('x509_ca') and os.path.exists('/etc/ssl/cert.pem'):
        context.load_verify_locations('/etc/ssl/cert.pem')
    return context


TLS = tls_context()


def fetch(url):
    request = urllib.request.Request(url, headers={'User-Agent': 'debian-sysroot.py'})
    with urllib.request.urlopen(request, timeout=120, context=TLS) as response:
        return response.read()


def parse_stanzas(text):
    for block in text.split('\n\n'):
        fields = {}
        key = None
        for line in block.splitlines():
            if line.startswith((' ', '\t')) and key:
                fields[key] += '\n' + line.strip()
            elif ':' in line:
                key, value = line.split(':', 1)
                fields[key] = value.strip()
        if 'Package' in fields:
            yield fields


def alternatives(relation):
    """Depends as a list of lists of package names (alternatives)."""
    result = []
    for clause in relation.split(','):
        names = []
        for alternative in clause.split('|'):
            name = re.sub(r'\(.*?\)|\[.*?\]|<.*?>', '', alternative).strip()
            name = name.split(':')[0]
            if name:
                names.append(name)
        if names:
            result.append(names)
    return result


class Index:
    def __init__(self, mirror, release, arch, cache):
        self.mirror = mirror.rstrip('/')
        self.cache = cache
        cache.mkdir(parents=True, exist_ok=True)
        release_file = fetch(f'{self.mirror}/dists/{release}/InRelease').decode()
        sums = {}
        in_sha256 = False
        for line in release_file.splitlines():
            if line.startswith('SHA256:'):
                in_sha256 = True
            elif in_sha256 and line.startswith(' '):
                digest, size, name = line.split()
                sums[name] = digest
            elif in_sha256:
                in_sha256 = False
        self.packages = {}
        self.provides = {}
        # Architecture-independent packages have an index of their own.
        for member in (f'main/binary-{arch}/Packages.xz', 'main/binary-all/Packages.xz'):
            packages_xz = fetch(f'{self.mirror}/dists/{release}/{member}')
            if hashlib.sha256(packages_xz).hexdigest() != sums.get(member):
                raise SystemExit(f'error: {member} does not match the SHA-256 sum in InRelease')
            for fields in parse_stanzas(lzma.decompress(packages_xz).decode()):
                if fields['Package'] in self.packages:
                    continue
                self.packages[fields['Package']] = fields
                for names in alternatives(fields.get('Provides', '')):
                    for name in names:
                        self.provides.setdefault(name, []).append(fields['Package'])

    def real(self, name):
        if name in self.packages:
            return name
        for candidate in self.provides.get(name, []):
            if candidate in self.packages:
                return candidate
        return None

    def closure(self, seeds):
        chosen = []
        seen = set()
        pending = list(seeds)
        while pending:
            name = pending.pop(0)
            real = self.real(name)
            if real is None:
                raise SystemExit(f'error: no package {name} in the index')
            if real in seen or (SKIPPED.match(real) and name not in seeds):
                continue
            seen.add(real)
            chosen.append(real)
            fields = self.packages[real]
            for clause in alternatives(fields.get('Pre-Depends', '')) + alternatives(fields.get('Depends', '')):
                if any(self.real(n) in seen for n in clause):
                    continue
                pick = next((n for n in clause if self.real(n) and not SKIPPED.match(self.real(n))), None)
                if pick:
                    pending.append(pick)
        return chosen

    def download(self, name):
        fields = self.packages[name]
        path = self.cache / Path(fields['Filename']).name
        if path.exists() and hashlib.sha256(path.read_bytes()).hexdigest() == fields['SHA256']:
            return path
        data = fetch(f"{self.mirror}/{fields['Filename']}")
        if hashlib.sha256(data).hexdigest() != fields['SHA256']:
            raise SystemExit(f'error: {path.name} does not match its SHA-256 sum')
        path.write_bytes(data)
        return path


def ar_members(data):
    if not data.startswith(b'!<arch>\n'):
        raise ValueError('not an ar archive')
    offset = 8
    while offset < len(data):
        header = data[offset:offset + 60]
        name = header[:16].decode().strip().rstrip('/')
        size = int(header[48:58].decode().strip())
        yield name, data[offset + 60:offset + 60 + size]
        offset += 60 + size + (size & 1)


def inside(root, name):
    parts = [p for p in PurePosixPath(name).parts if p not in ('', '.', '/')]
    if any(p == '..' for p in parts):
        raise ValueError(f'unsafe path {name}')
    return '/'.join(parts)


def unpack(deb, root):
    """Unpacks a package's files; returns their paths."""
    paths = []
    for name, data in ar_members(deb.read_bytes()):
        if not name.startswith('data.tar'):
            continue
        with tarfile.open(fileobj=io.BytesIO(data), mode='r:*') as archive:
            for member in archive:
                relative = inside(root, member.name)
                if not relative or relative.startswith(SKIPPED_PATHS):
                    continue
                target = root / relative
                if not member.isdir():
                    paths.append(relative)
                if member.isdir():
                    target.mkdir(parents=True, exist_ok=True)
                    continue
                target.parent.mkdir(parents=True, exist_ok=True)
                if target.is_symlink() or target.exists():
                    if target.is_dir() and not target.is_symlink():
                        continue
                    target.unlink()
                if member.issym():
                    link = member.linkname
                    if link.startswith('/'):
                        link = os.path.relpath(root / inside(root, link), target.parent)
                    os.symlink(link, target)
                elif member.islnk():
                    source = root / inside(root, member.linkname)
                    if source.exists():
                        os.link(source, target)
                elif member.isfile():
                    with archive.extractfile(member) as stream:
                        target.write_bytes(stream.read())
                    target.chmod(0o644 | (member.mode & 0o111))
        return paths
    raise ValueError(f'{deb.name} has no data.tar')


def main():
    parser = argparse.ArgumentParser(description='Make a Debian sysroot from Debian packages.')
    parser.add_argument('sysroot', type=Path)
    parser.add_argument('packages', nargs='*')
    parser.add_argument('--arch', default='arm64')
    parser.add_argument('--release', default='trixie')
    parser.add_argument('--mirror', default='https://deb.debian.org/debian')
    parser.add_argument('--cache', type=Path, help='where to keep the downloaded .deb files')
    args = parser.parse_args()

    root = args.sysroot.resolve()
    root.mkdir(parents=True, exist_ok=True)
    cache = args.cache or root.parent / f'debs-{args.release}-{args.arch}'
    print(f'== Debian {args.release} {args.arch} from {args.mirror}', flush=True)
    index = Index(args.mirror, args.release, args.arch, cache)
    names = index.closure(args.packages or DEFAULT_PACKAGES)
    print(f'== {len(names)} packages', flush=True)
    # Merged /usr: /lib and friends are links into usr/, as on Debian.
    for name in ('lib', 'bin', 'sbin'):
        link = root / name
        (root / 'usr' / name).mkdir(parents=True, exist_ok=True)
        if not link.exists() and not link.is_symlink():
            os.symlink(f'usr/{name}', link)
    # Packages added to a sysroot join the ones there.
    owners = {}
    if (root / 'files.tsv').exists():
        owners = dict(line.split('\t', 1) for line in (root / 'files.tsv').read_text().splitlines())
    versions = {}
    if (root / 'packages.txt').exists():
        versions = dict(line.split(' ', 1) for line in (root / 'packages.txt').read_text().splitlines())
    for number, name in enumerate(names, 1):
        print(f'   [{number}/{len(names)}] {name}', flush=True)
        owners.update((path, name) for path in unpack(index.download(name), root))
        versions[name] = index.packages[name]['Version']
    # Which package each file is from, for the Depends of packages built
    # against the sysroot (as dpkg -S answers on Debian).
    (root / 'files.tsv').write_text(''.join(f'{p}\t{n}\n' for p, n in sorted(owners.items())))
    (root / 'packages.txt').write_text(''.join(f'{n} {v}\n' for n, v in sorted(versions.items())))
    print(f'== Sysroot in {root}', flush=True)


if __name__ == '__main__':
    main()
