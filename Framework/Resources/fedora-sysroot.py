#!/usr/bin/env python3
#
# fedora-sysroot.py: makes a Fedora sysroot without Fedora, Docker or root:
# it downloads the packages a GNUstep build links against (and what they
# require) from Fedora's repositories and unpacks them into one folder.
#
#   fedora-sysroot.py --arch aarch64 --release 45 SYSROOT [PACKAGE...]
#
# SYSROOT/packages.txt lists the packages and their versions, and
# SYSROOT/files.tsv which package each file comes from.
#
# The release's repository and its updates are read; a package in both is
# taken in its newer version. The packages are checked against the SHA-256
# sums of the repositories' primary index, whose own sum is checked against
# repomd.xml (fetched over HTTPS; its signature is not checked). Programs,
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
import gzip
import hashlib
import http.client
import io
import lzma
import os
import re
import shutil
import socket
import ssl
import subprocess
import sys
import urllib.error
import urllib.request
import xml.etree.ElementTree as ElementTree
from pathlib import Path, PurePosixPath

# What GNUstep (libobjc2, base, gui, back) and the GTK4Native theme link
# against: the -devel packages of gnustep-image.sh, without the optional
# ones, and gcc for its start files and libgcc (its programs are left out).
DEFAULT_PACKAGES = '''
glibc-devel kernel-headers gcc libstdc++-devel robin-map-devel
libffi-devel libicu-devel gnutls-devel openssl-devel libxml2-devel libxslt-devel
zlib-devel gmp-devel libcurl-devel
libjpeg-turbo-devel libtiff-devel libpng-devel giflib-devel
freetype-devel fontconfig-devel cairo-devel libX11-devel libXext-devel
libXt-devel libXft-devel libXrender-devel libXrandr-devel libXmu-devel
gtk4-devel
'''.split()

# Packages a sysroot doesn't need: programs, interpreters, services, data.
SKIPPED = re.compile(r'''^(
    perl(-.*)? | python3.* | python-.* | bash | sh-utils | coreutils.* | filesystem | setup |
    basesystem | glibc-common | glibc-.*langpack.* | glibc-gconv-extra | tzdata | crypto-policies.* |
    ca-certificates | systemd.* | dbus.* | udev | shadow-utils | util-linux.* | grep | sed | gawk |
    findutils | info | ncurses-base | alternatives | chkconfig | cpp | binutils.* | gcc-plugin-.* |
    libmpc | mpfr | isl | annobin.* | gcc-gdb-plugin | make | cmake.* | pkgconf(-.*)? |
    llvm.* | clang.* | mesa-dri-drivers | mesa-va-drivers | mesa-vulkan-drivers | mesa-filesystem |
    dconf | gsettings-desktop-schemas | gtk-update-icon-cache | hicolor-icon-theme |
    adwaita-.* | .*-fonts(-.*)? | fonts-filesystem | fontconfig | xkeyboard-config | xml-common |
    glib2-doc | gtk4-devel-docs | .*-doc | gobject-introspection-devel | vala | libtool | autoconf |
    automake | m4 | gettext.* | emacs-filesystem | vim-filesystem | rpm.* | dnf.* | file
)$''', re.X)

# Paths left out of every package.
SKIPPED_PATHS = ('usr/share/doc/', 'usr/share/man/', 'usr/share/info/', 'usr/share/locale/',
                 'usr/share/licenses/', 'usr/share/gtk-doc/', 'usr/share/help/', 'usr/share/icons/',
                 'usr/bin/', 'usr/sbin/', 'usr/libexec/', 'bin/', 'sbin/', 'etc/', 'var/', 'run/',
                 'usr/lib/.build-id/', 'usr/lib/systemd/', 'usr/lib/debug/')

NS = {'c': 'http://linux.duke.edu/metadata/common', 'rpm': 'http://linux.duke.edu/metadata/rpm',
      'repo': 'http://linux.duke.edu/metadata/repo'}


def tls_context():
    # python.org's Python on macOS comes without CA certificates until its
    # "Install Certificates" step is run: use the system's bundle then.
    context = ssl.create_default_context()
    if not context.cert_store_stats().get('x509_ca') and os.path.exists('/etc/ssl/cert.pem'):
        context.load_verify_locations('/etc/ssl/cert.pem')
    return context


TLS = tls_context()


def create_connection(address, timeout, source_address=None):
    """socket.create_connection, IPv4 addresses first, 10 seconds each: an
    IPv6 address without a route would otherwise hold up the IPv4 ones for
    the whole timeout. Reading gets all of it."""
    host, port = address
    addresses = socket.getaddrinfo(host, port, type=socket.SOCK_STREAM)
    addresses.sort(key=lambda entry: entry[0] != socket.AF_INET)
    error = OSError(f'no address for {host}')
    for family, kind, protocol, _, location in addresses:
        connection = socket.socket(family, kind, protocol)
        connection.settimeout(10)
        try:
            if source_address:
                connection.bind(source_address)
            connection.connect(location)
        except OSError as failure:
            error = failure
            connection.close()
            continue
        connection.settimeout(timeout)
        return connection
    raise error


class Connection(http.client.HTTPSConnection):
    def __init__(self, *arguments, **options):
        super().__init__(*arguments, **options)
        self._create_connection = create_connection


class Handler(urllib.request.HTTPSHandler):
    def https_open(self, request):
        return self.do_open(Connection, request, context=TLS)


OPENER = urllib.request.build_opener(Handler(context=TLS))


def fetch(url):
    request = urllib.request.Request(url, headers={'User-Agent': 'fedora-sysroot.py'})
    for attempt in range(3):
        try:
            with OPENER.open(request, timeout=300) as response:
                return response.read()
        except (urllib.error.URLError, TimeoutError, ConnectionError):
            if attempt == 2:
                raise


def decompress(data):
    if data[:4] == b'\x28\xb5\x2f\xfd':
        try:
            from compression import zstd
            return zstd.decompress(data)
        except ImportError:
            tool = shutil.which('zstd')
            if not tool:
                raise SystemExit('error: zstd data needs Python 3.14 or the zstd tool (brew install zstd)')
            return subprocess.run([tool, '-dc'], input=data, stdout=subprocess.PIPE, check=True).stdout
    if data[:6] == b'\xfd7zXZ\x00':
        return lzma.decompress(data)
    if data[:2] == b'\x1f\x8b':
        return gzip.decompress(data)
    if data[:3] == b'BZh':
        import bz2
        return bz2.decompress(data)
    return data


def vercmp(a, b):
    """rpmvercmp: -1, 0 or 1."""
    while a or b:
        a = re.sub(r'^[^a-zA-Z0-9~^]+', '', a)
        b = re.sub(r'^[^a-zA-Z0-9~^]+', '', b)
        if a.startswith('~') or b.startswith('~'):
            if not a.startswith('~'):
                return 1
            if not b.startswith('~'):
                return -1
            a, b = a[1:], b[1:]
            continue
        if a.startswith('^') or b.startswith('^'):
            if not a:
                return -1
            if not b:
                return 1
            if not a.startswith('^'):
                return 1
            if not b.startswith('^'):
                return -1
            a, b = a[1:], b[1:]
            continue
        if not a or not b:
            break
        pattern = r'\d+' if a[0].isdigit() else r'[a-zA-Z]+'
        ma, mb = re.match(pattern, a), re.match(pattern, b)
        if not mb:
            return 1 if a[0].isdigit() else -1
        x, y = ma.group(), mb.group()
        if a[0].isdigit():
            x, y = x.lstrip('0'), y.lstrip('0')
            if len(x) != len(y):
                return 1 if len(x) > len(y) else -1
        if x != y:
            return 1 if x > y else -1
        a, b = a[ma.end():], b[mb.end():]
    if not a and not b:
        return 0
    return 1 if a else -1


def newer(one, other):
    for key in ('epoch', 'version', 'release'):
        result = vercmp(one[key], other[key])
        if result:
            return result > 0
    return False


class Index:
    def __init__(self, repositories, arch):
        self.packages = {}
        for base in repositories:
            try:
                repomd = ElementTree.fromstring(fetch(base + '/repodata/repomd.xml'))
            except urllib.error.HTTPError as error:
                if error.code == 404:
                    print(f'   no repository at {base}', flush=True)
                    continue
                raise
            primary = repomd.find("repo:data[@type='primary']", NS)
            href = primary.find('repo:location', NS).get('href')
            digest = primary.find('repo:checksum', NS)
            data = fetch(f'{base}/{href}')
            if digest.get('type') != 'sha256' or hashlib.sha256(data).hexdigest() != digest.text:
                raise SystemExit(f'error: {href} does not match the SHA-256 sum in repomd.xml')
            count = 0
            for _, element in ElementTree.iterparse(io.BytesIO(decompress(data))):
                if element.tag != '{%s}package' % NS['c']:
                    continue
                package = self.read(element, base)
                element.clear()
                if package['arch'] not in (arch, 'noarch'):
                    continue
                count += 1
                known = self.packages.get(package['name'])
                if known is None or newer(package, known):
                    self.packages[package['name']] = package
            print(f'   {count} packages in {base}', flush=True)
        if not self.packages:
            raise SystemExit('error: no packages: is the release right?')
        self.provides = {}
        for package in self.packages.values():
            for name in package['provides'] + package['files']:
                self.provides.setdefault(name, []).append(package['name'])

    @staticmethod
    def read(element, base):
        version = element.find('c:version', NS)
        checksum = element.find('c:checksum', NS)
        form = element.find('c:format', NS)

        def entries(tag):
            group = form.find(f'rpm:{tag}', NS)
            return [] if group is None else [e.get('name') for e in group.findall('rpm:entry', NS)]
        return {'name': element.find('c:name', NS).text, 'arch': element.find('c:arch', NS).text,
                'epoch': version.get('epoch') or '0', 'version': version.get('ver'), 'release': version.get('rel'),
                'sha256': checksum.text if checksum.get('type') == 'sha256' else None,
                'location': element.find('c:location', NS).get('href'), 'base': base,
                'provides': entries('provides'), 'requires': entries('requires'),
                'files': [f.text for f in form.findall('c:file', NS)]}

    def providers(self, name):
        if name in self.packages:
            return [name]
        return sorted(set(self.provides.get(name, [])), key=lambda n: (len(n), n))

    def closure(self, seeds):
        chosen = []
        seen = set()
        pending = list(seeds)
        while pending:
            name = pending.pop(0)
            found = self.providers(name)
            if not found:
                raise SystemExit(f'error: no package {name} in the repositories')
            real = found[0]
            if real in seen or (SKIPPED.match(real) and name not in seeds):
                continue
            seen.add(real)
            chosen.append(real)
            for requirement in self.packages[real]['requires']:
                # rpm's own features, rich dependencies (optional ones, as a
                # rule) and files (programs, for scriptlets) are not needed.
                if requirement.startswith(('rpmlib(', '(', '/', 'config(')):
                    continue
                found = self.providers(requirement)
                if not found or any(f in seen for f in found):
                    continue
                pick = next((f for f in found if not SKIPPED.match(f)), None)
                if pick:
                    pending.append(pick)
        return chosen

    def download(self, name, cache):
        package = self.packages[name]
        path = cache / PurePosixPath(package['location']).name
        if path.exists() and hashlib.sha256(path.read_bytes()).hexdigest() == package['sha256']:
            return path
        data = fetch(f"{package['base']}/{package['location']}")
        if package['sha256'] is None or hashlib.sha256(data).hexdigest() != package['sha256']:
            raise SystemExit(f'error: {path.name} does not match its SHA-256 sum')
        path.write_bytes(data)
        return path


def header_end(data, offset, pad):
    """The end of an RPM header structure that starts at offset."""
    if data[offset:offset + 3] != b'\x8e\xad\xe8':
        raise ValueError('not an RPM header')
    entries = int.from_bytes(data[offset + 8:offset + 12], 'big')
    size = int.from_bytes(data[offset + 12:offset + 16], 'big')
    end = offset + 16 + entries * 16 + size
    return (end + 7) & ~7 if pad else end


def payload(path):
    """The cpio archive in an RPM file."""
    data = path.read_bytes()
    if data[:4] != b'\xed\xab\xee\xdb':
        raise ValueError(f'{path.name} is not an RPM file')
    signature = header_end(data, 96, pad=True)
    return decompress(data[header_end(data, signature, pad=False):])


def inside(name):
    parts = [p for p in PurePosixPath(name).parts if p not in ('', '.', '/')]
    if any(p == '..' for p in parts):
        raise ValueError(f'unsafe path {name}')
    return '/'.join(parts)


def unpack(rpm, root):
    """Unpacks a package's files (its cpio payload, newc format); returns their paths."""
    data = payload(rpm)
    paths = []
    links = {}
    offset = 0
    while True:
        magic = data[offset:offset + 6]
        if magic not in (b'070701', b'070702'):
            raise ValueError(f'{rpm.name}: unknown cpio format {magic!r}')
        fields = [int(data[offset + 6 + 8 * i:offset + 14 + 8 * i], 16) for i in range(13)]
        inode, mode, nlink, size, namesize = fields[0], fields[1], fields[4], fields[6], fields[11]
        name_start = offset + 110
        name = data[name_start:name_start + namesize - 1].decode()
        start = (name_start + namesize + 3) & ~3
        content = data[start:start + size]
        offset = (start + size + 3) & ~3
        if name == 'TRAILER!!!':
            break
        relative = inside(name)
        if not relative or relative.startswith(SKIPPED_PATHS):
            continue
        target = root / relative
        kind = mode & 0o170000
        if kind == 0o040000:
            target.mkdir(parents=True, exist_ok=True)
            continue
        target.parent.mkdir(parents=True, exist_ok=True)
        if target.is_symlink() or target.exists():
            if target.is_dir() and not target.is_symlink():
                continue
            target.unlink()
        if kind == 0o120000:
            link = content.decode()
            if link.startswith('/'):
                link = os.path.relpath(root / inside(link), target.parent)
            os.symlink(link, target)
        elif kind == 0o100000:
            # Hard links: the data comes with the last of them.
            if nlink > 1:
                links.setdefault(inode, []).append(target)
                if not size:
                    continue
                for other in links[inode]:
                    other.write_bytes(content)
                    other.chmod(0o644 | (mode & 0o111))
            else:
                target.write_bytes(content)
                target.chmod(0o644 | (mode & 0o111))
        else:
            continue
        paths.append(relative)
    return paths


def main():
    parser = argparse.ArgumentParser(description='Make a Fedora sysroot from Fedora packages.')
    parser.add_argument('sysroot', type=Path)
    parser.add_argument('packages', nargs='*')
    parser.add_argument('--arch', default='aarch64')
    parser.add_argument('--release', default='45')
    parser.add_argument('--mirror', default='https://dl.fedoraproject.org/pub/fedora/linux')
    parser.add_argument('--cache', type=Path, help='where to keep the downloaded .rpm files')
    args = parser.parse_args()

    root = args.sysroot.resolve()
    root.mkdir(parents=True, exist_ok=True)
    cache = args.cache or root.parent / f'rpms-{args.release}-{args.arch}'
    cache.mkdir(parents=True, exist_ok=True)
    mirror = args.mirror.rstrip('/')
    print(f'== Fedora {args.release} {args.arch} from {mirror}', flush=True)
    index = Index([f'{mirror}/updates/{args.release}/Everything/{args.arch}',
                   f'{mirror}/releases/{args.release}/Everything/{args.arch}/os'], args.arch)
    names = index.closure(args.packages or DEFAULT_PACKAGES)
    print(f'== {len(names)} packages', flush=True)
    # Merged /usr: /lib, /lib64 and the program folders are links into usr/.
    for name in ('lib', 'lib64', 'bin', 'sbin'):
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
        package = index.packages[name]
        print(f'   [{number}/{len(names)}] {name}', flush=True)
        owners.update((path, name) for path in unpack(index.download(name, cache), root))
        versions[name] = f"{package['version']}-{package['release']}"
    # Which package each file is from, for the Requires of packages built
    # against the sysroot (as rpm -qf answers on Fedora).
    (root / 'files.tsv').write_text(''.join(f'{p}\t{n}\n' for p, n in sorted(owners.items())))
    (root / 'packages.txt').write_text(''.join(f'{n} {v}\n' for n, v in sorted(versions.items())))
    print(f'== Sysroot in {root}', flush=True)


if __name__ == '__main__':
    main()
