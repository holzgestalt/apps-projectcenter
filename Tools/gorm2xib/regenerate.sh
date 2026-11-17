#!/bin/sh
# Regenerate every .xib from its .gorm with gorm2xib (macOS, Xcode's clang).
# Run from anywhere.
set -e
cd "$(dirname "$0")/../.."
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

clang -fno-objc-arc -IFramework -framework Foundation \
  Framework/PCGormArchive.m Framework/PCGormXIBWriter.m Tools/gorm2xib/gorm2xib.m \
  -o "$work/gorm2xib"

find . -type d -name '*.gorm' -not -path './Modules/Projects/Application/Resources/Main.gorm' |
  while read -r gorm
  do
    "$work/gorm2xib" "$gorm"
  done
