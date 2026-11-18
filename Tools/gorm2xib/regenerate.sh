#!/bin/sh
# Convert ProjectCenter's .gorm interfaces to .xib (macOS, Xcode's clang).
# The XIBs are the source: this is for moving interfaces to XIBs once, and
# converts only the interfaces that have no .xib yet. --replace overwrites
# the existing XIBs too. ProjectCenter's Edit → Convert → To XIB... does the
# same for any project. Run from anywhere.
set -e
replace=no
[ "$1" = "--replace" ] && replace=yes
cd "$(dirname "$0")/../.."
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

clang -fno-objc-arc -IFramework -framework Foundation \
  Framework/PCGormArchive.m Framework/PCGormXIBWriter.m Tools/gorm2xib/gorm2xib.m \
  -o "$work/gorm2xib"

find . -type d -name '*.gorm' -not -path './Modules/Projects/Application/Resources/Main.gorm' |
  while read -r gorm
  do
    if [ "$replace" = yes ] || [ ! -e "${gorm%.gorm}.xib" ]
    then
      "$work/gorm2xib" "$gorm"
    fi
  done
