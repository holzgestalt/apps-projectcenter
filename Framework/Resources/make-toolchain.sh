#!/bin/sh
#
# make-toolchain.sh: makes a GNUstep cross toolchain for Debian or Fedora on
# this computer (a Mac or a Linux machine), without Docker, a virtual machine
# or root. Make Toolchain... in ProjectCenter's Deployment tab runs it
# (+[PCDeployment makeToolchainArgumentsForDeployment:project:]); Archive
# then builds a Linux target with it when its Build is Cross Toolchain and
# its Toolchain is the folder this makes (see CrossToolchain.md).
#
#   make-toolchain.sh [options] [FOLDER]
#     FOLDER            default: ~/gnustep-toolchains/<distribution>-<release>-<arch>
#     --distribution D  debian (default) or fedora
#     --arch ARCH       arm64 (default) or amd64; Fedora's names, aarch64 and
#                       x86_64, are the same
#     --release NAME    the release, default trixie for Debian, 45 for Fedora
#     --sources DIR     GNUstep sources to build (libdispatch, libobjc2,
#                       tools-make, libs-base, libs-gui, libs-back and a
#                       gtk4native* theme), default $GNUSTEP_SOURCES; the
#                       missing ones (all, without a folder) are cloned,
#                       from holzgestalt where it has a fork
#     --no-fetch        build the sources in --sources as they are: without
#                       it, each one that is a git checkout first fetches
#                       its remotes and fast-forwards its branch (not one
#                       with local changes, which is built as it is); the
#                       others are cloned new each time
#     --no-theme        leave GTK4Native out
#     --from STEP       start at a step: sysroot, wrappers, libdispatch,
#                       libobjc2, tools-make, libs-base, libs-gui,
#                       libs-back, theme,
#                       package (the earlier ones must have been done)
#     --only STEP       do only that step
#     --jobs N          parallel jobs
#
# FOLDER then holds:
#   sysroot/          the distribution's libraries and headers
#                     (debian-sysroot.py, fedora-sysroot.py) and GNUstep
#                     built for it in sysroot/opt/gnustep
#   bin/              clang, clang++, pkg-config, gnustep-config, ar, ...
#                     for the target, and GNU make as make
#   GNUstep.sh        the toolchain's environment: what ProjectCenter's
#                     Toolchain setting names (its folder)
#   packages/         projectcenter-gnustep_<version>_<arch>.deb (or
#                     projectcenter-gnustep-<version>-1.<arch>.rpm), GNUstep
#                     for the target's computers, which an application's
#                     package without Include GNUstep depends on
#   logs/             a log for each step
#
# The host needs clang and lld (LLVM's, not Apple's: brew install llvm lld),
# GNU make 4 (brew install make), CMake, pkgconf, Python 3, and dpkg-deb
# for Debian (brew install dpkg) or rpmbuild for Fedora (brew install rpm).
# GNUstep is built as gnustep-image.sh builds it for the container: clang,
# libobjc2, library combo ng-gnu-gnu, fhs layout in /opt/gnustep, so the
# package is the same.
#
# This file is part of GNUstep ProjectCenter.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.

set -eu

# ProjectCenter runs this with an application's PATH, which has no Homebrew.
PATH="$PATH:/opt/homebrew/bin:/usr/local/bin:/opt/local/bin"
export PATH

HERE="$(cd "$(dirname "$0")" && pwd)"
DISTRIBUTION=debian
ARCH=arm64
RELEASE=""
SOURCES="${GNUSTEP_SOURCES:-}"
THEME=1
FETCH=1
FROM=sysroot
ONLY=""
JOBS="$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 4)"
DEST=""
PREFIX=/opt/gnustep

while [ $# -gt 0 ]; do
  case "$1" in
    --distribution) DISTRIBUTION="$2"; shift 2 ;;
    --arch) ARCH="$2"; shift 2 ;;
    --release) RELEASE="$2"; shift 2 ;;
    --sources) SOURCES="$2"; shift 2 ;;
    --no-theme) THEME=0; shift ;;
    --no-fetch) FETCH=0; shift ;;
    --from) FROM="$2"; shift 2 ;;
    --only) FROM="$2"; ONLY="$2"; shift 2 ;;
    --jobs) JOBS="$2"; shift 2 ;;
    -h|--help) sed -n '2,53p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) echo "Unknown option $1 (see --help)" >&2; exit 2 ;;
    *) DEST="$1"; shift ;;
  esac
done

case "$ARCH" in
  arm64|aarch64) PROCESSOR=aarch64 ;;
  amd64|x86_64) PROCESSOR=x86_64 ;;
  *) echo "error: --arch is arm64 or amd64, not $ARCH" >&2; exit 2 ;;
esac
# The distribution's names: its release, architecture, target triple (the
# folder of GCC's files) and library folder.
case "$DISTRIBUTION" in
  debian)
    TITLE=Debian
    RELEASE="${RELEASE:-trixie}"
    case "$PROCESSOR" in aarch64) ARCH=arm64 ;; *) ARCH=amd64 ;; esac
    TRIPLE="$PROCESSOR-linux-gnu"
    LIBDIR="/usr/lib/$TRIPLE"
    ;;
  fedora)
    TITLE=Fedora
    RELEASE="${RELEASE:-45}"
    ARCH="$PROCESSOR"
    TRIPLE="$PROCESSOR-redhat-linux"
    LIBDIR=/usr/lib64
    ;;
  *) echo "error: --distribution is debian or fedora, not $DISTRIBUTION" >&2; exit 2 ;;
esac
DEST="${DEST:-$HOME/gnustep-toolchains/$DISTRIBUTION-$RELEASE-$ARCH}"
mkdir -p "$DEST"
DEST="$(cd "$DEST" && pwd)"
SYSROOT="$DEST/sysroot"
WORK="$DEST/build"
LOGS="$DEST/logs"
mkdir -p "$WORK" "$LOGS" "$DEST/bin"

# --- Host tools -------------------------------------------------------------

tool() {
  for candidate in "$@"; do
    if [ -x "$candidate" ]; then echo "$candidate"; return 0; fi
    if command -v "$candidate" >/dev/null 2>&1; then command -v "$candidate"; return 0; fi
  done
  return 1
}
BREW="$(brew --prefix 2>/dev/null || echo /opt/homebrew)"
CLANG="$(tool "$BREW/opt/llvm/bin/clang" clang-21 clang-20 clang-19 clang)" || { echo "error: no clang (brew install llvm)" >&2; exit 1; }
LLVM_BIN="$(dirname "$CLANG")"
LLD="$(tool "$BREW/opt/lld/bin/ld.lld" "$LLVM_BIN/ld.lld" ld.lld)" || { echo "error: no ld.lld (brew install lld)" >&2; exit 1; }
GMAKE="$(tool "$BREW/opt/make/bin/gmake" gmake)" || GMAKE="$(command -v make)"
"$GMAKE" --version | head -n 1 | grep -q 'GNU Make [4-9]' || { echo "error: GNU make 4 is needed (brew install make)" >&2; exit 1; }
PKGCONF="$(tool "$BREW/bin/pkgconf" pkgconf pkg-config)" || { echo "error: no pkgconf (brew install pkgconf)" >&2; exit 1; }
[ -x "$LLVM_BIN/llvm-ar" ] || { echo "error: no llvm-ar next to $CLANG (brew install llvm)" >&2; exit 1; }
case "$("$CLANG" --version | head -n 1)" in
  Apple*) echo "error: $CLANG is Apple's clang; use LLVM's (brew install llvm)" >&2; exit 1 ;;
esac
if [ "$DISTRIBUTION" = debian ]; then
  command -v dpkg-deb >/dev/null 2>&1 || { echo "error: no dpkg-deb (brew install dpkg)" >&2; exit 1; }
else
  command -v rpmbuild >/dev/null 2>&1 || { echo "error: no rpmbuild (brew install rpm)" >&2; exit 1; }
fi

# --- Steps ------------------------------------------------------------------

STEPS="sysroot wrappers libdispatch libobjc2 tools-make libs-base libs-gui libs-back theme package"
case " $STEPS " in *" $FROM "*) ;; *) echo "error: no step $FROM ($STEPS)" >&2; exit 2 ;; esac

# A process and everything it started.
kill_tree() {
  for grandchild in $(pgrep -P "$1" 2>/dev/null); do kill_tree "$grandchild"; done
  kill "$1" 2>/dev/null || true
}

# Runs a step with its output in its log, unless it comes before --from.
started=0
step() {
  name="$1"; shift
  if [ "$started" = 0 ] && [ "$name" != "$FROM" ]; then echo "== $name: done before"; return 0; fi
  if [ -n "$ONLY" ] && [ "$name" != "$ONLY" ]; then return 0; fi
  started=1
  echo "== $name"
  # Not in an if: set -e is off in a condition, also in its subshells. The
  # step runs in the background so that a TERM (Stop in ProjectCenter)
  # can end it and everything it started.
  set +e
  ( set -e; "$@" ) > "$LOGS/$name.log" 2>&1 &
  child=$!
  trap 'kill_tree "$child"; echo "== stopped" >&2; exit 143' TERM INT
  wait "$child"
  status=$?
  trap - TERM INT
  set -e
  if [ "$status" != 0 ]; then
    echo "error: $name failed; the end of $LOGS/$name.log:" >&2
    tail -n 40 "$LOGS/$name.log" >&2
    exit 1
  fi
}

# The theme's folder in --sources, if there is one.
theme_folder() {
  if [ -n "$SOURCES" ]; then
    find "$SOURCES" -mindepth 1 -maxdepth 1 -type d -iname 'gtk4native*' 2>/dev/null | head -n 1
  fi
}

# Where the sources that aren't in --sources are cloned from.
LIBDISPATCH_URL=https://github.com/swiftlang/swift-corelibs-libdispatch.git
LIBOBJC2_URL=https://github.com/gnustep/libobjc2.git
TOOLS_MAKE_URL=https://github.com/gnustep/tools-make.git
LIBS_BASE_URL=https://github.com/holzgestalt/libs-base.git
LIBS_GUI_URL=https://github.com/holzgestalt/libs-gui.git
LIBS_BACK_URL=https://github.com/gnustep/libs-back.git
THEME_URL=https://github.com/holzgestalt/GTK4Native.git

# Brings the sources up to date and lists them, with the commit each is
# built from. A git checkout in --sources fetches all its remotes and
# fast-forwards its branch to the branch it tracks, as build-gnustep.sh
# does; one with local changes, without a tracked branch, or that has
# commits of its own is built as it is, with a warning. The others are
# cloned new by their step, from the default branch.
update_sources() {
  command -v git >/dev/null 2>&1 || { echo "warning: no git; the sources in --sources are built as they are" >&2; return 0; }
  theme="$(theme_folder)"
  while read -r name url; do
    if [ "$name" = theme ]; then
      [ "$THEME" = 1 ] || continue
      if [ -n "$theme" ]; then name="$(basename "$theme")"; else name=GTK4Native; fi
    fi
    folder="$SOURCES/$name"
    if [ -z "$SOURCES" ] || [ ! -d "$folder" ]; then
      head="$(git ls-remote "$url" HEAD 2>/dev/null | cut -c1-9)"
      echo "   $name: cloned from $url${head:+ at $head}"
      continue
    fi
    if [ ! -d "$folder/.git" ]; then
      echo "   $name: $folder (not a git checkout), as it is"
      continue
    fi
    branch="$(git -C "$folder" branch --show-current)"
    if [ "$FETCH" = 0 ]; then
      :
    elif ! git -C "$folder" fetch --all --prune --quiet; then
      echo "warning: $name: couldn't fetch; built as it is" >&2
    elif [ -n "$(git -C "$folder" status --porcelain --untracked-files=no)" ]; then
      echo "warning: $name: local changes; fetched, built as it is" >&2
    elif ! tracked="$(git -C "$folder" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null)"; then
      echo "warning: $name: ${branch:-a detached HEAD} tracks no branch; fetched, built as it is" >&2
    elif ! git -C "$folder" merge --ff-only --quiet '@{u}' 2>/dev/null; then
      echo "warning: $name: $branch has commits $tracked hasn't; fetched, built as it is" >&2
    fi
    echo "   $name: $folder, ${branch:-detached} at $(git -C "$folder" log -1 --format='%h %s')"
  done <<SOURCES
libdispatch $LIBDISPATCH_URL
libobjc2 $LIBOBJC2_URL
tools-make $TOOLS_MAKE_URL
libs-base $LIBS_BASE_URL
libs-gui $LIBS_GUI_URL
libs-back $LIBS_BACK_URL
theme $THEME_URL
SOURCES
}

# A source folder in $WORK: a copy of the one in --sources, else a clone.
source_folder() {
  name="$1" url="$2"
  rm -rf "${WORK:?}/${name:?}"
  if [ -n "$SOURCES" ] && [ -d "$SOURCES/$name" ]; then
    mkdir -p "$WORK/$name"
    (cd "$SOURCES/$name" && tar -cf - --exclude .git --exclude ./obj --exclude ./build \
      --exclude .DS_Store .) | (cd "$WORK/$name" && tar -xf -)
    echo "$name: from $SOURCES/$name"
  else
    git clone --quiet --depth 1 "$url" "$WORK/$name"
    echo "$name: cloned from $url at $(git -C "$WORK/$name" log -1 --format='%h %s')"
  fi
}

step_sysroot() {
  python3 -I "$HERE/$DISTRIBUTION-sysroot.py" --arch "$ARCH" --release "$RELEASE" "$SYSROOT"
}

# The wrappers: the target's compilers, with the sysroot and lld, which
# also find GNUstep's /opt/gnustep in the sysroot (gnustep-make and
# gnustep-config name it as it is on the target).
wrapper_compiler() {
  cat > "$DEST/bin/$1" <<EOF
#!/bin/sh
# Written by make-toolchain.sh: $1 for $TRIPLE, in $SYSROOT.
link=yes
for argument; do
  case "\$argument" in -c|-E|-S|-M|-MM|-fsyntax-only) link=no ;; esac
done
count=\$#
for argument; do
  case "\$argument" in
    -I$PREFIX|-I$PREFIX/*) argument="-I$SYSROOT\${argument#-I}" ;;
    -L$PREFIX|-L$PREFIX/*) argument="-L$SYSROOT\${argument#-L}" ;;
    $PREFIX/*) argument="$SYSROOT\$argument" ;;
  esac
  set -- "\$@" "\$argument"
done
shift "\$count"
if [ "\$link" = yes ]; then
  set -- --ld-path='$LLD' "\$@" -Wl,-rpath-link,$SYSROOT$PREFIX/lib -Wl,-rpath-link,$SYSROOT$LIBDIR
fi
# Newer clang than Debian's makes this an error; Debian's (and the
# container's) warns, so builds behave the same here.
exec '$LLVM_BIN/$2' --target=$TRIPLE --sysroot='$SYSROOT' -Wno-error=incompatible-pointer-types "\$@"
EOF
  chmod 755 "$DEST/bin/$1"
}

step_wrappers() {
  wrapper_compiler clang clang
  wrapper_compiler clang++ clang++
  for name in ar ranlib nm strip objdump objcopy readelf; do
    ln -sf "$LLVM_BIN/llvm-$name" "$DEST/bin/$name"
    ln -sf "$LLVM_BIN/llvm-$name" "$DEST/bin/$TRIPLE-$name"
  done
  ln -sf "$GMAKE" "$DEST/bin/make"
  # gnustep-make runs plmerge for bundles; the target's can't run here,
  cp "$HERE/plmerge.py" "$DEST/bin/plmerge.py"
  printf '#!/bin/sh\nexec python3 -I %s "$@"\n' "'$DEST/bin/plmerge.py'" > "$DEST/bin/plmerge"
  chmod 755 "$DEST/bin/plmerge"
  # and pl2link for applications' desktop entries (plmerge.py --pl2link).
  printf '#!/bin/sh\nexec python3 -I %s --pl2link "$@"\n' "'$DEST/bin/plmerge.py'" > "$DEST/bin/pl2link"
  chmod 755 "$DEST/bin/pl2link"
  cat > "$DEST/bin/pkg-config" <<EOF
#!/bin/sh
# Written by make-toolchain.sh: pkg-config for $TRIPLE, in $SYSROOT.
PKG_CONFIG_SYSROOT_DIR='$SYSROOT'
PKG_CONFIG_LIBDIR='$SYSROOT$PREFIX/lib/pkgconfig:$SYSROOT$LIBDIR/pkgconfig:$SYSROOT/usr/lib/pkgconfig:$SYSROOT/usr/share/pkgconfig'
# The sysroot's own folders are system folders: no -I or -L for them, which
# would put C's headers before C++'s.
PKG_CONFIG_SYSTEM_INCLUDE_PATH='$SYSROOT/usr/include'
PKG_CONFIG_SYSTEM_LIBRARY_PATH='$SYSROOT/usr/lib:$SYSROOT$LIBDIR'
export PKG_CONFIG_SYSROOT_DIR PKG_CONFIG_LIBDIR PKG_CONFIG_SYSTEM_INCLUDE_PATH PKG_CONFIG_SYSTEM_LIBRARY_PATH
unset PKG_CONFIG_PATH
exec '$PKGCONF' "\$@"
EOF
  chmod 755 "$DEST/bin/pkg-config"
  ln -sf pkg-config "$DEST/bin/$TRIPLE-pkg-config"
  ln -sf clang "$DEST/bin/$TRIPLE-clang"
  ln -sf clang++ "$DEST/bin/$TRIPLE-clang++"
  # gnustep-config runs the target's, with the toolchain's configuration.
  cat > "$DEST/bin/gnustep-config" <<EOF
#!/bin/sh
# Written by make-toolchain.sh: the target's gnustep-config.
GNUSTEP_CONFIG_FILE='$DEST/GNUstep.conf'
GNUSTEP_MAKEFILES='$SYSROOT$PREFIX/share/GNUstep/Makefiles'
PATH='$DEST/bin':"\$PATH"
export GNUSTEP_CONFIG_FILE GNUSTEP_MAKEFILES PATH
exec /bin/sh '$SYSROOT$PREFIX/bin/gnustep-config' "\$@"
EOF
  chmod 755 "$DEST/bin/gnustep-config"
  cat > "$DEST/toolchain.cmake" <<EOF
# Written by make-toolchain.sh: CMake for $TRIPLE, in $SYSROOT.
set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR $PROCESSOR)
set(CMAKE_SYSROOT "$SYSROOT")
set(CMAKE_C_COMPILER "$DEST/bin/clang")
set(CMAKE_CXX_COMPILER "$DEST/bin/clang++")
set(CMAKE_ASM_COMPILER "$DEST/bin/clang")
set(CMAKE_OBJC_COMPILER "$DEST/bin/clang")
set(CMAKE_AR "$DEST/bin/ar")
set(CMAKE_RANLIB "$DEST/bin/ranlib")
set(CMAKE_FIND_ROOT_PATH "$SYSROOT;$SYSROOT$PREFIX")
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
EOF
  "$DEST/bin/clang" -x c - -o "$WORK/hello" <<EOF
#include <stdio.h>
int main(void) { puts("hello"); return 0; }
EOF
  file "$WORK/hello"
}

step_libobjc2() {
  source_folder libobjc2 "$LIBOBJC2_URL"
  cd "$WORK/libobjc2"
  cmake -S . -B build -DCMAKE_TOOLCHAIN_FILE="$DEST/toolchain.cmake" -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DTESTS=OFF -DGNUSTEP_INSTALL_TYPE=NONE -DCMAKE_INSTALL_PREFIX="$PREFIX" -DCMAKE_INSTALL_LIBDIR=lib \
    -DEMBEDDED_BLOCKS_RUNTIME=OFF -DBlocksRuntime_INCLUDE_DIR="$SYSROOT$PREFIX/include" \
    -DBlocksRuntime_LIBRARIES="$SYSROOT$PREFIX/lib/libBlocksRuntime.so"
  cmake --build build -j "$JOBS"
  DESTDIR="$SYSROOT" cmake --install build
}

# Grand Central Dispatch, which Debian doesn't package: GTK4Native's SDK
# and libs-base use it. It brings the blocks runtime (libBlocksRuntime),
# which libobjc2 then uses instead of its own, so there is only one.
step_libdispatch() {
  rm -rf "$SYSROOT$PREFIX"
  source_folder libdispatch "$LIBDISPATCH_URL"
  cd "$WORK/libdispatch"
  cmake -S . -B build -DCMAKE_TOOLCHAIN_FILE="$DEST/toolchain.cmake" -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DBUILD_TESTING=OFF -DINSTALL_PRIVATE_HEADERS=YES \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" -DCMAKE_INSTALL_LIBDIR=lib
  cmake --build build -j "$JOBS"
  DESTDIR="$SYSROOT" cmake --install build
}

# configure for the target.
cross_configure() {
  ./configure --build="$("$CLANG" -dumpmachine)" --host="$TRIPLE" \
    CC="$DEST/bin/clang" CXX="$DEST/bin/clang++" OBJC="$DEST/bin/clang" OBJCXX="$DEST/bin/clang++" \
    AR="$DEST/bin/ar" RANLIB="$DEST/bin/ranlib" PKG_CONFIG="$DEST/bin/pkg-config" "$@"
}

step_tools_make() {
  source_folder tools-make "$TOOLS_MAKE_URL"
  cd "$WORK/tools-make"
  # tools-make's configure (autoconf 2.73, since tools-make cffce46) adds
  # -std=gnu23 to CC, then runs "${CC}" -v as one word to see if it is clang,
  # so clang counts as an old GCC and is refused: it is clang.
  PATH="$DEST/bin:$PATH" cross_configure --prefix="$PREFIX" --with-layout=fhs \
    --with-library-combo=ng-gnu-gnu --enable-objc-arc \
    CPPFLAGS="-I$PREFIX/include" LDFLAGS="-L$PREFIX/lib" _gs_cv_cc_is_clang=yes
  PATH="$DEST/bin:$PATH" make
  PATH="$DEST/bin:$PATH" make install DESTDIR="$SYSROOT"
  # The toolchain's GNUstep.conf: the target's, with its makefiles here.
  { cat "$SYSROOT$PREFIX/etc/GNUstep/GNUstep.conf"
    echo
    echo "# make-toolchain.sh: the makefiles are in the sysroot on this computer."
    echo "GNUSTEP_MAKEFILES=$SYSROOT$PREFIX/share/GNUstep/Makefiles"
  } > "$DEST/GNUstep.conf"
  cat > "$DEST/GNUstep.sh" <<EOF
# GNUstep.sh of a cross toolchain, written by make-toolchain.sh: source it
# to build for $TITLE $RELEASE $ARCH ($TRIPLE). GNUstep is in
# $SYSROOT$PREFIX; installing with
# DESTDIR='$SYSROOT' adds to it.
GNUSTEP_TOOLCHAIN='$DEST'
GNUSTEP_TOOLCHAIN_DISTRIBUTION='$DISTRIBUTION'
GNUSTEP_SYSROOT='$SYSROOT'
GNUSTEP_CONFIG_FILE='$DEST/GNUstep.conf'
GNUSTEP_MAKEFILES='$SYSROOT$PREFIX/share/GNUstep/Makefiles'
export GNUSTEP_TOOLCHAIN GNUSTEP_TOOLCHAIN_DISTRIBUTION GNUSTEP_SYSROOT GNUSTEP_CONFIG_FILE GNUSTEP_MAKEFILES
. "\$GNUSTEP_MAKEFILES/GNUstep.sh"
PATH='$DEST/bin':"\$PATH"
CC='$DEST/bin/clang'
CXX='$DEST/bin/clang++'
OBJC='$DEST/bin/clang'
AR='$DEST/bin/ar'
RANLIB='$DEST/bin/ranlib'
PKG_CONFIG='$DEST/bin/pkg-config'
PKG_CONFIG_SYSROOT_DIR='$SYSROOT'
PKG_CONFIG_LIBDIR='$SYSROOT$PREFIX/lib/pkgconfig:$SYSROOT$LIBDIR/pkgconfig:$SYSROOT/usr/lib/pkgconfig:$SYSROOT/usr/share/pkgconfig'
export PATH CC CXX OBJC AR RANLIB PKG_CONFIG PKG_CONFIG_SYSROOT_DIR PKG_CONFIG_LIBDIR
unset PKG_CONFIG_PATH
EOF
}

# make install with DESTDIR: what goes to GNUSTEP_MAKEFILES, which is in the
# sysroot here, lands in the sysroot twice; it is moved where it belongs.
install_into_sysroot() {
  make install DESTDIR="$SYSROOT"
  doubled="$SYSROOT$SYSROOT"
  if [ -d "$doubled" ]; then
    (cd "$doubled" && tar -cf - .) | (cd "$SYSROOT" && tar -xf -)
    rm -rf "$doubled"
    parent="$(dirname "$doubled")"
    while [ "$parent" != "$SYSROOT" ] && rmdir "$parent" 2>/dev/null; do
      parent="$(dirname "$parent")"
    done
  fi
}

# Builds a GNUstep library in the toolchain's environment.
gnustep_library() {
  name="$1" url="$2"; shift 2
  source_folder "$name" "$url"
  cd "$WORK/$name"
  set +u
  . "$DEST/GNUstep.sh"
  set -u
  cross_configure "$@"
  make -j "$JOBS" messages=yes
  install_into_sysroot
}

step_libs_base() {
  gnustep_library libs-base "$LIBS_BASE_URL" \
    --with-config-file="$PREFIX/etc/GNUstep/GNUstep.conf" \
    --with-default-config="$SYSROOT$PREFIX/etc/GNUstep/GNUstep.conf" \
    --with-cross-compilation-info="$HERE/libs-base-cross.config"
}

step_libs_gui() {
  # libs-gui uses ICU's common library as well as i18n, but asks pkg-config
  # only for icu-i18n, which names icu-uc only privately on Fedora.
  gnustep_library libs-gui "$LIBS_GUI_URL" \
    ICU_LIBS="-licui18n -licuuc -licudata"
}

step_libs_back() {
  gnustep_library libs-back "$LIBS_BACK_URL"
}

step_theme() {
  if [ "$THEME" = 0 ]; then echo "left out (--no-theme)"; return 0; fi
  theme="$(theme_folder)"
  if [ -n "$theme" ]; then
    source_folder "$(basename "$theme")" -
    name="$(basename "$theme")"
  else
    source_folder GTK4Native "$THEME_URL"
    name=GTK4Native
  fi
  cd "$WORK/$name"
  set +u
  . "$DEST/GNUstep.sh"
  set -u
  make -j "$JOBS" messages=yes
  install_into_sysroot
  find "$SYSROOT$PREFIX" -name 'gnustep-theme-*.pc' | grep -q . || {
    echo "error: the theme installed no gnustep-theme-*.pc" >&2; exit 1; }
}

# projectcenter-gnustep: $PREFIX as a package of the distribution, as
# gnustep-image.sh makes it in the container, with Depends (Requires) from
# the libraries it links.
step_package() {
  "package_$DISTRIBUTION"
}

package_debian() {
  name=projectcenter-gnustep
  version="1.0+$(date +%Y%m%d)"
  stage="$WORK/package"
  rm -rf "$stage" 2>/dev/null || true
  mkdir -p "$stage$PREFIX" "$stage/etc/ld.so.conf.d" "$stage/DEBIAN" "$DEST/packages"
  (cd "$SYSROOT$PREFIX" && tar -cf - --exclude .DS_Store .) | (cd "$stage$PREFIX" && tar -xf -)
  echo "$PREFIX/lib" > "$stage/etc/ld.so.conf.d/$name.conf"
  depends="$(python3 -I "$HERE/debian-depends.py" "$SYSROOT" "$stage$PREFIX")"
  # For Archive (PCDeployment): the Depends of an application built here.
  cp "$HERE/debian-depends.py" "$DEST/bin/debian-depends.py"
  cat > "$DEST/bin/debian-depends" <<EOF
#!/bin/sh
# Written by make-toolchain.sh: the Debian packages that the ELF files in a
# folder (an application bundle) need, from the sysroot's.
exec python3 -I '$DEST/bin/debian-depends.py' --gnustep '$PREFIX' '$name' '$SYSROOT' "\$1"
EOF
  chmod 755 "$DEST/bin/debian-depends"
  {
    echo "Package: $name"
    echo "Version: $version"
    echo "Architecture: $ARCH"
    echo "Maintainer: ProjectCenter <projectcenter@localhost>"
    echo "Section: libs"
    echo "Priority: optional"
    echo "Installed-Size: $(du -sk "$stage" | cut -f1)"
    if [ -n "$depends" ]; then echo "Depends: $depends"; fi
    echo "Description: GNUstep (libobjc2, base, gui, back, GTK4Native) for applications archived by ProjectCenter"
  } > "$stage/DEBIAN/control"
  printf '#!/bin/sh\nldconfig\n' > "$stage/DEBIAN/postinst"
  printf '#!/bin/sh\nldconfig\n' > "$stage/DEBIAN/postrm"
  chmod 755 "$stage/DEBIAN/postinst" "$stage/DEBIAN/postrm"
  # Finder writes .DS_Store into folders open in a window, even while this runs.
  find "$stage" -name .DS_Store -delete
  rm -f "$DEST/packages/${name}_"*.deb
  dpkg-deb --root-owner-group -Zxz --build "$stage" "$DEST/packages/${name}_${version}_${ARCH}.deb"
  cat "$stage/DEBIAN/control"
  # The package is made; a folder Finder is writing into can't fail the step.
  rm -rf "$stage" 2>/dev/null || echo "note: couldn't remove $stage"
}

# An RPM, made with rpmbuild for the target. rpmbuild finds no dependencies
# here (it has no ELF reader on a Mac), so the package lists them itself:
# Requires from the sysroot, and Provides of GNUstep's libraries.
package_fedora() {
  name=projectcenter-gnustep
  version="1.0.$(date +%Y%m%d)"
  stage="$WORK/package"
  # rpmbuild's tree is a temporary folder: rpmbuild removes its build folder
  # with an rm that fails when Finder, showing the folder, writes a .DS_Store
  # into it meanwhile.
  top="$(mktemp -d "${TMPDIR:-/tmp}/projectcenter-rpm.XXXXXX")"
  rm -rf "$stage" "$WORK/rpm" 2>/dev/null || true
  mkdir -p "$stage$PREFIX" "$stage/etc/ld.so.conf.d" "$top/SPECS" "$top/BUILD" "$DEST/packages"
  (cd "$SYSROOT$PREFIX" && tar -cf - --exclude .DS_Store .) | (cd "$stage$PREFIX" && tar -xf -)
  echo "$PREFIX/lib" > "$stage/etc/ld.so.conf.d/$name.conf"
  find "$stage" -name .DS_Store -delete
  requires="$(python3 -I "$HERE/debian-depends.py" --capabilities "$SYSROOT" "$stage$PREFIX")"
  # The sonames of GNUstep's libraries, as rpm would provide them.
  provides="$(python3 -I - "$stage$PREFIX/lib" <<'PYTHON'
import struct, sys
from pathlib import Path
names = set()
for path in Path(sys.argv[1]).glob('*.so*'):
    if path.is_symlink() or not path.is_file():
        continue
    data = path.read_bytes()
    if data[:4] != b'\x7fELF' or data[4] != 2 or data[5] != 1:
        continue
    shoff, = struct.unpack_from('<Q', data, 0x28)
    shentsize, shnum = struct.unpack_from('<HH', data, 0x3a)
    sections = [struct.unpack_from('<IIQQQQIIQQ', data, shoff + i * shentsize) for i in range(shnum)]
    for _, kind, _, _, offset, size, link, _, _, entsize in sections:
        if kind != 6:
            continue
        for i in range(0, size, entsize or 16):
            tag, value = struct.unpack_from('<qQ', data, offset + i)
            if tag == 0:
                break
            if tag == 14:  # DT_SONAME
                start = sections[link][4] + value
                names.add(data[start:data.index(b'\0', start)].decode() + '()(64bit)')
print(', '.join(sorted(names)))
PYTHON
)"
  # For Archive (PCDeployment): the Requires of an application built here.
  cp "$HERE/debian-depends.py" "$DEST/bin/debian-depends.py"
  cat > "$DEST/bin/rpm-requires" <<EOF
#!/bin/sh
# Written by make-toolchain.sh: the capabilities (libraries) that the ELF
# files in a folder (an application bundle) need, from the sysroot's.
exec python3 -I '$DEST/bin/debian-depends.py' --capabilities --gnustep '$PREFIX' '$name' '$SYSROOT' "\$1"
EOF
  chmod 755 "$DEST/bin/rpm-requires"
  {
    echo "Name: $name"
    echo "Version: $version"
    echo "Release: 1"
    echo "Summary: GNUstep (libobjc2, base, gui, back, GTK4Native) for applications archived by ProjectCenter"
    echo "License: LGPL-2.1-or-later AND GPL-3.0-or-later"
    echo "AutoReqProv: no"
    if [ -n "$requires" ]; then echo "Requires: $requires"; fi
    if [ -n "$provides" ]; then echo "Provides: $provides"; fi
    echo
    echo "%description"
    echo "GNUstep built by ProjectCenter's make-toolchain.sh, in $PREFIX."
    echo
    echo "%install"
    echo "mkdir -p %{buildroot}"
    echo "cp -R '$stage'/. %{buildroot}/"
    echo
    echo "%post -p /sbin/ldconfig"
    echo "%postun -p /sbin/ldconfig"
    echo
    echo "%files"
    echo "$PREFIX"
    echo "/etc/ld.so.conf.d/$name.conf"
  } > "$top/SPECS/$name.spec"
  rm -f "$DEST/packages/$name-"*.rpm
  # No post-install processing: these binaries are not for this computer's
  # strip. The target's system is Linux, whatever this computer's is. In the
  # C locale, as libmagic's patterns are invalid ranges in a macOS UTF-8 one.
  # In the v4 format Fedora ships, which rpm 6 doesn't write by default.
  LC_ALL=C rpmbuild -bb --target "$ARCH-linux" --define "_topdir $top" --define '__os_install_post %{nil}' \
    --define '__arch_install_post %{nil}' --define 'debug_package %{nil}' \
    --define '_build_id_links none' --define '_rpmformat 4' --define "_target_platform $ARCH-linux-gnu" \
    "$top/SPECS/$name.spec"
  made="$(find "$top/RPMS" -type f -name '*.rpm' | head -n 1)"
  [ -n "$made" ] || { echo "error: rpmbuild made no package" >&2; exit 1; }
  cp "$made" "$DEST/packages/"
  sed -n '1,8p' "$top/SPECS/$name.spec"
  rm -rf "$stage" "$top" 2>/dev/null || echo "note: couldn't remove $stage"
}

# The sources, unless no step builds them.
case "$FROM:$ONLY" in
  package:*|*:sysroot|*:wrappers) ;;
  *) echo "== sources"; update_sources ;;
esac
step sysroot step_sysroot
step wrappers step_wrappers
step libdispatch step_libdispatch
step libobjc2 step_libobjc2
step tools-make step_tools_make
step libs-base step_libs_base
step libs-gui step_libs_gui
step libs-back step_libs_back
step theme step_theme
step package step_package

cat <<EOF

The toolchain for $TITLE $RELEASE $ARCH is in $DEST.
In ProjectCenter: Deployment, the Linux target's platform, Build: Cross
Toolchain, Toolchain: $DEST
On the target's computers, install first:
  $(ls "$DEST/packages/"*.deb "$DEST/packages/"*.rpm 2>/dev/null | head -n 1)
EOF
