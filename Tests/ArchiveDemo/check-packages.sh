#!/bin/sh
#
# check-packages.sh: installs the packages that Archive made of ArchiveDemo
# into clean containers of their systems, and starts the application there
# under Xvfb (--smoke-test: it opens its window and quits).
#
#   Tests/ArchiveDemo/check-packages.sh [archive folder]
#
# The folder defaults to the newest one in Tests/ArchiveDemo/build/Archives.
# Needs docker (or CONTAINER=podman) running. Each package is checked for
# its own architecture, amd64 under emulation on Apple silicon.
#
# This file is part of GNUstep ProjectCenter.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.

set -u
CONTAINER="${CONTAINER:-docker}"
HERE="$(cd "$(dirname "$0")" && pwd)"
FOLDER="${1:-$(ls -d "$HERE"/build/Archives/*/ 2>/dev/null | tail -n 1)}"
FOLDER="${FOLDER%/}"
FAILED=0

if [ ! -d "$FOLDER" ]; then
  echo "error: no archive folder; archive ArchiveDemo first" >&2
  exit 1
fi
echo "Checking the packages in $FOLDER"

check() { # name platform image command
  echo "=== $1 ($2, $3)"
  if "$CONTAINER" run --rm --platform "$2" -v "$FOLDER:/packages:ro" "$3" /bin/sh -c "$4" > "$FOLDER/check.log" 2>&1 \
     && grep -q 'ArchiveDemo started' "$FOLDER/check.log"; then
    echo "ok: ArchiveDemo started"
  else
    tail -n 30 "$FOLDER/check.log"
    echo "error: $1 on $2 failed" >&2
    FAILED=1
  fi
}

for arch in amd64 arm64; do
  deb="$(cd "$FOLDER" && ls archivedemo_*_"$arch".deb 2>/dev/null | head -n 1)"
  runtime="$(cd "$FOLDER" && ls projectcenter-gnustep_*_"$arch".deb 2>/dev/null | head -n 1)"
  [ -n "$deb" ] || continue
  check "$deb" "linux/$arch" debian:trixie \
    "apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends \
       /packages/$runtime /packages/$deb xvfb xauth >/dev/null && xvfb-run -a archivedemo --smoke-test"
done

for arch in x86_64 aarch64; do
  rpm="$(cd "$FOLDER" && ls archivedemo-*."$arch".rpm 2>/dev/null | head -n 1)"
  runtime="$(cd "$FOLDER" && ls projectcenter-gnustep-*."$arch".rpm 2>/dev/null | head -n 1)"
  [ -n "$rpm" ] || continue
  platform=linux/amd64; [ "$arch" = aarch64 ] && platform=linux/arm64
  check "$rpm" "$platform" fedora:latest \
    "dnf install -y -q /packages/$runtime /packages/$rpm xorg-x11-server-Xvfb xorg-x11-xauth which >/dev/null \
       && xvfb-run -a archivedemo --smoke-test"
done

# The tarball needs GNUstep, so it runs in ProjectCenter's image.
for arch in x86_64 aarch64; do
  tarball="$(cd "$FOLDER" && ls ArchiveDemo-*-linux-"$arch".tar.gz 2>/dev/null | head -n 1)"
  [ -n "$tarball" ] || continue
  platform=amd64; [ "$arch" = aarch64 ] && platform=arm64
  check "$tarball" "linux/$platform" "projectcenter-gnustep:debian-$platform" \
    "cd /tmp && tar -xzf /packages/$tarball && xvfb-run -a ./ArchiveDemo.app/ArchiveDemo --smoke-test"
done

exit "$FAILED"
