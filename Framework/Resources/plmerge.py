#!/usr/bin/env python3
#
# plmerge.py: libs-base's plmerge for the build computer of a cross
# toolchain, where the target's can't run. gnustep-make runs it to merge a
# project's Info.plist into a bundle's generated Info-gnustep.plist:
#
#   plmerge DESTINATION SOURCE...
#
# merges the dictionaries in the SOURCE property lists into the one in
# DESTINATION, keys of later ones winning, and writes DESTINATION in the
# OpenStep format, which GNUstep always reads. It reads the OpenStep and
# XML formats.
#
#   plmerge --pl2link INFO-PLIST [DESKTOP-FILE]
#
# is libs-base's pl2link, which gnustep-make runs for applications: the
# freedesktop.org entry of an application from its Info-gnustep.plist, with
# the target's paths from the environment of the toolchain's GNUstep.sh
# (GNUSTEP_<DOMAIN>_APPS for GNUSTEP_INSTALLATION_DOMAIN, and openapp in
# GNUSTEP_SYSTEM_TOOLS).
#
# This file is part of GNUstep ProjectCenter.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.

import os
import plistlib
import re
import sys
from pathlib import Path

UNQUOTED = re.compile(r'[A-Za-z0-9_$+/:.\-]+')


class OpenStepParser:
    def __init__(self, text):
        self.text = text
        self.at = 0

    def skip(self):
        while True:
            match = re.compile(r'\s+').match(self.text, self.at)
            if match:
                self.at = match.end()
            if self.text.startswith('//', self.at):
                end = self.text.find('\n', self.at)
                self.at = len(self.text) if end < 0 else end
            elif self.text.startswith('/*', self.at):
                self.at = self.text.index('*/', self.at) + 2
            else:
                return

    def expect(self, character):
        self.skip()
        if not self.text.startswith(character, self.at):
            raise ValueError(f'expected {character!r} at {self.at}')
        self.at += 1

    def value(self):
        self.skip()
        character = self.text[self.at:self.at + 1]
        if character == '{':
            self.at += 1
            result = {}
            while True:
                self.skip()
                if self.text.startswith('}', self.at):
                    self.at += 1
                    return result
                key = self.value()
                self.expect('=')
                result[key] = self.value()
                self.expect(';')
        if character == '(':
            self.at += 1
            result = []
            while True:
                self.skip()
                if self.text.startswith(')', self.at):
                    self.at += 1
                    return result
                result.append(self.value())
                self.skip()
                if self.text.startswith(',', self.at):
                    self.at += 1
        if character == '"':
            self.at += 1
            out = []
            while self.text[self.at] != '"':
                if self.text[self.at] == '\\':
                    self.at += 1
                    escape = self.text[self.at]
                    out.append({'n': '\n', 't': '\t', 'r': '\r'}.get(escape, escape))
                else:
                    out.append(self.text[self.at])
                self.at += 1
            self.at += 1
            return ''.join(out)
        if character == '<':
            end = self.text.index('>', self.at)
            data = bytes.fromhex(re.sub(r'\s', '', self.text[self.at + 1:end]))
            self.at = end + 1
            return data
        match = UNQUOTED.match(self.text, self.at)
        if not match:
            raise ValueError(f'unexpected {character!r} at {self.at}')
        self.at = match.end()
        return match.group()


def read(path):
    data = Path(path).read_bytes()
    if data.lstrip().startswith((b'<?xml', b'<!DOCTYPE', b'<plist', b'bplist')):
        return plistlib.loads(data)
    parser = OpenStepParser(data.decode('utf-8'))
    result = parser.value()
    parser.skip()
    return result


def quoted(value):
    if re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*', value):
        return value
    return '"' + value.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n') + '"'


def write(value, indent=''):
    inner = indent + '  '
    if isinstance(value, dict):
        lines = [f'{inner}{quoted(str(k))} = {write(v, inner)};' for k, v in value.items()]
        return '{\n' + '\n'.join(lines) + '\n' + indent + '}'
    if isinstance(value, list):
        return '(\n' + ',\n'.join(inner + write(v, inner) for v in value) + '\n' + indent + ')'
    if isinstance(value, bool):
        return 'YES' if value else 'NO'
    if isinstance(value, bytes):
        return '<' + value.hex() + '>'
    return quoted(str(value))


def pl2link(arguments):
    """libs-base's Tools/pl2link.m."""
    plist = read(arguments[0])
    if not isinstance(plist, dict):
        print('The source property list must contain an NSDictionary.', file=sys.stderr)
        sys.exit(1)
    destination = arguments[1] if len(arguments) > 1 else None
    lines = ['[Desktop Entry]', 'Type=Application']
    categories = plist.get('FreeDesktopCategories')
    if isinstance(categories, list) and categories:
        lines.append('Categories=' + ';'.join(categories) + ';')
    else:
        lines.append('Categories=X-GNUstep;')
    name = plist.get('ApplicationName')
    if name is not None:
        lines += [f'Name={name}', f'StartupWMClass={name}']
        destination = destination or name + '.desktop'
    if plist.get('ApplicationDescription') is not None:
        lines.append(f"Comment={plist['ApplicationDescription']}")
    domain = os.environ.get('GNUSTEP_INSTALLATION_DOMAIN', 'LOCAL')
    if domain not in ('SYSTEM', 'NETWORK', 'LOCAL', 'USER'):
        domain = 'LOCAL'
    applications = os.environ.get(f'GNUSTEP_{domain}_APPS', '/opt/gnustep/lib/GNUstep/Applications')
    icon = plist.get('NSIcon')
    if icon is not None:
        path = f'{applications}/{name or ""}.app/Resources/{icon}'
        lines.append(f'Icon={path}' + ('' if os.path.splitext(icon)[1] else '.tiff'))
    executable = plist.get('NSExecutable')
    if executable is not None:
        tools = os.environ.get('GNUSTEP_SYSTEM_TOOLS', '/opt/gnustep/bin')
        lines.append(f'Exec={tools}/openapp {executable}')
    types = plist.get('NSTypes')
    if isinstance(types, list) and types:
        mime = ''.join(f'{t};' for entry in types if isinstance(entry, dict)
                       for t in entry.get('NSMIMETypes', []))
        lines.append('MimeType=' + mime)
    if destination is None:
        print('pl2link: no destination and no ApplicationName', file=sys.stderr)
        sys.exit(1)
    Path(destination).write_text('\n'.join(lines) + '\n')


def main():
    if len(sys.argv) > 1 and sys.argv[1] == '--pl2link':
        if len(sys.argv) < 3:
            print('usage: pl2link INFO-PLIST [DESKTOP-FILE]', file=sys.stderr)
            sys.exit(2)
        pl2link(sys.argv[2:])
        return
    if len(sys.argv) < 3:
        print('usage: plmerge DESTINATION SOURCE...', file=sys.stderr)
        sys.exit(2)
    destination = read(sys.argv[1])
    for source in sys.argv[2:]:
        merged = read(source)
        if not isinstance(merged, dict):
            print(f'plmerge: {source} is not a dictionary', file=sys.stderr)
            sys.exit(1)
        destination.update(merged)
    Path(sys.argv[1]).write_text(write(destination) + '\n')


if __name__ == '__main__':
    main()
