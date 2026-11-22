#!/bin/sh
#
# gnustep-image.sh: the steps of GNUstep-image.Dockerfile, which makes the
# container image that ProjectCenter's Archive builds GNUstep applications
# in. It runs as root inside the image while it is built:
#
#   gnustep-image.sh packages   the system's compiler and -dev packages
#   gnustep-image.sh gnustep    builds libobjc2, tools-make, libs-base,
#                               libs-gui, libs-back (and a GTK4Native theme
#                               found in /sources) with clang into $PREFIX
#   gnustep-image.sh runtime    packages $PREFIX as projectcenter-gnustep
#                               (.deb or .rpm, in /opt/projectcenter/packages)
#                               and installs it from that package
#
# The sources are those in /sources (copied into the image's build context
# by archive.sh, from GNUSTEP_SOURCES); missing ones are cloned from the
# *_URL variables. The library combo is ng-gnu-gnu, as build-gnustep.sh
# builds it, so applications can use blocks, literals and ARC.
#
# This file is part of GNUstep ProjectCenter.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.

set -eu

PREFIX="${PREFIX:-/opt/gnustep}"
SOURCES=/sources
PACKAGES=/opt/projectcenter/packages
JOBS="$(nproc 2>/dev/null || echo 4)"

if command -v apt-get >/dev/null 2>&1; then
  SYSTEM=debian
elif command -v dnf >/dev/null 2>&1; then
  SYSTEM=rpm
else
  echo "error: the image needs apt-get (Debian, Ubuntu) or dnf (Fedora)" >&2
  exit 1
fi

install_packages() {
  if [ "$SYSTEM" = debian ]; then
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends "$@"
  else
    dnf install -y -q --setopt=install_weak_deps=False "$@"
  fi
}

step_packages() {
  if [ "$SYSTEM" = debian ]; then
    install_packages ca-certificates git make cmake pkg-config clang lld g++ python3 file \
      dpkg-dev xvfb xauth libtsl-robin-map-dev \
      libffi-dev libicu-dev libgnutls28-dev libssl-dev libxml2-dev libxslt1-dev \
      zlib1g-dev libgmp-dev libavahi-client-dev libcurl4-gnutls-dev \
      libjpeg-dev libtiff-dev libpng-dev libgif-dev libaspell-dev libcups2-dev \
      libfreetype-dev libfontconfig-dev libcairo2-dev libx11-dev libxext-dev \
      libxt-dev libxft-dev libxrender-dev libxrandr-dev libxmu-dev
    rm -rf /var/lib/apt/lists/*
  else
    install_packages ca-certificates git make cmake pkgconf-pkg-config clang lld gcc-c++ python3 file \
      rpm-build findutils xorg-x11-server-Xvfb xorg-x11-xauth robin-map-devel \
      libffi-devel libicu-devel gnutls-devel openssl-devel libxml2-devel libxslt-devel \
      zlib-devel gmp-devel avahi-devel libcurl-devel \
      libjpeg-turbo-devel libtiff-devel libpng-devel giflib-devel aspell-devel cups-devel \
      freetype-devel fontconfig-devel cairo-devel libX11-devel libXext-devel \
      libXt-devel libXft-devel libXrender-devel libXrandr-devel libXmu-devel
    dnf clean all >/dev/null
  fi

  # libobjc2's runtime ABI needs lld rather than ld.bfd: clang and clang++
  # in /usr/local/bin (first on the PATH) link with it.
  for compiler in clang clang++; do
    real="$(command -v "$compiler")"
    cat > "/usr/local/bin/$compiler" <<EOF
#!/bin/sh
for argument; do
  case "\$argument" in -c|-E|-S|-M|-MM) exec $real "\$@" ;; esac
done
exec $real -fuse-ld=lld "\$@"
EOF
    chmod 755 "/usr/local/bin/$compiler"
  done
}

# A source folder: from /sources, else cloned.
source_of() {
  name="$1" url="$2" ref="$3"
  if [ ! -d "$SOURCES/$name" ]; then
    echo "== Cloning $name from $url${ref:+ ($ref)}"
    git clone --quiet --depth 1 ${ref:+--branch "$ref"} "$url" "$SOURCES/$name"
  else
    echo "== $name from the build context"
  fi
}

step_gnustep() {
  mkdir -p "$SOURCES"
  source_of libobjc2 "$LIBOBJC2_URL" "${LIBOBJC2_REF:-}"
  source_of tools-make "$MAKE_URL" "${MAKE_REF:-}"
  source_of libs-base "$BASE_URL" "${BASE_REF:-}"
  source_of libs-gui "$GUI_URL" "${GUI_REF:-}"
  source_of libs-back "$BACK_URL" "${BACK_REF:-}"

  export CC=clang CXX=clang++ OBJC=clang
  export PATH="/usr/local/bin:$PREFIX/bin:$PATH"
  export CPPFLAGS="-I$PREFIX/include"
  export LDFLAGS="-L$PREFIX/lib -fuse-ld=lld"
  export LD_LIBRARY_PATH="$PREFIX/lib"

  echo "== Building libobjc2"
  cd "$SOURCES/libobjc2"
  rm -rf build
  cmake -S . -B build -DCMAKE_BUILD_TYPE=RelWithDebInfo -DTESTS=OFF \
    -DGNUSTEP_INSTALL_TYPE=NONE -DCMAKE_INSTALL_PREFIX="$PREFIX" -DCMAKE_INSTALL_LIBDIR=lib \
    -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ \
    -DCMAKE_EXE_LINKER_FLAGS=-fuse-ld=lld -DCMAKE_SHARED_LINKER_FLAGS=-fuse-ld=lld
  cmake --build build -j "$JOBS"
  cmake --install build

  echo "== Building tools-make"
  cd "$SOURCES/tools-make"
  ./configure --prefix="$PREFIX" --with-layout=fhs --with-library-combo=ng-gnu-gnu --enable-objc-arc
  make install

  # GNUstep.sh reads unset variables.
  set +u
  . "$PREFIX/share/GNUstep/Makefiles/GNUstep.sh"
  set -u
  for name in libs-base libs-gui libs-back; do
    echo "== Building $name"
    cd "$SOURCES/$name"
    ./configure
    make -j "$JOBS"
    make install
  done

  # A theme in the build context, as build-gnustep.sh finds it.
  theme="$(find "$SOURCES" -mindepth 1 -maxdepth 1 -type d -iname 'gtk4native*' | head -n 1)"
  if [ -n "$theme" ]; then
    echo "== Building the theme in $theme"
    if [ "$SYSTEM" = debian ]; then install_packages libgtk-4-dev; else install_packages gtk4-devel; fi
    cd "$theme"
    if [ -f GNUmakefile ]; then
      make -j "$JOBS"
      make install
    else
      ./configure
      make -j "$JOBS"
      make install
    fi
  fi
  cd /
  rm -rf "$SOURCES"
}

# The packages of the libraries that binaries in a folder link, for Depends.
debian_depends() {
  find "$1" -type f \( -name '*.so*' -o -perm -u+x \) | while read -r binary; do
    file -b "$binary" | grep -q ELF || continue
    LD_LIBRARY_PATH="$1/lib" ldd "$binary" 2>/dev/null | awk '$3 ~ /^\// { print $3 }'
  done | sort -u | while read -r library; do
    case "$library" in ""|"$1"/*) continue ;; esac
    dpkg -S "$library" 2>/dev/null || dpkg -S "$(readlink -f "$library")" 2>/dev/null || true
  done | cut -d: -f1 | sort -u | paste -sd, - | sed 's/,/, /g'
}

step_runtime() {
  name=projectcenter-gnustep
  version="1.0+$(date +%Y%m%d)"
  stage=/tmp/runtime
  rm -rf "$stage"
  mkdir -p "$stage$PREFIX" "$stage/etc/ld.so.conf.d" "$PACKAGES"
  cp -a "$PREFIX/." "$stage$PREFIX/"
  for folder in "$PREFIX/lib" "$PREFIX/lib64"; do
    if [ -d "$folder" ]; then echo "$folder"; fi
  done > "$stage/etc/ld.so.conf.d/$name.conf"

  if [ "$SYSTEM" = debian ]; then
    arch="$(dpkg --print-architecture)"
    depends="$(debian_depends "$PREFIX")"
    mkdir -p "$stage/DEBIAN"
    {
      echo "Package: $name"
      echo "Version: $version"
      echo "Architecture: $arch"
      echo "Maintainer: ProjectCenter <projectcenter@localhost>"
      echo "Section: libs"
      echo "Priority: optional"
      echo "Installed-Size: $(du -sk "$stage" | cut -f1)"
      if [ -n "$depends" ]; then echo "Depends: $depends"; fi
      echo "Description: GNUstep (libobjc2, base, gui, back) for applications archived by ProjectCenter"
    } > "$stage/DEBIAN/control"
    printf '#!/bin/sh\nldconfig\n' > "$stage/DEBIAN/postinst"
    printf '#!/bin/sh\nldconfig\n' > "$stage/DEBIAN/postrm"
    chmod 755 "$stage/DEBIAN/postinst" "$stage/DEBIAN/postrm"
    file="$PACKAGES/${name}_${version}_${arch}.deb"
    dpkg-deb --root-owner-group --build "$stage" "$file"
    rm -rf "$PREFIX"
    dpkg -i "$file"
  else
    arch="$(uname -m)"
    top=/tmp/rpm
    rm -rf "$top"
    mkdir -p "$top/SPECS" "$top/RPMS" "$top/BUILD"
    {
      echo "Name: $name"
      echo "Version: $(echo "$version" | tr '+' '.')"
      echo "Release: 1"
      echo "Summary: GNUstep (libobjc2, base, gui, back) for applications archived by ProjectCenter"
      echo "License: LGPL-2.1-or-later"
      echo; echo '%description'
      echo 'GNUstep built with clang and libobjc2, for applications archived by ProjectCenter.'
      echo; echo '%install'
      echo 'mkdir -p %{buildroot}'
      echo "cp -a '$stage'/. %{buildroot}/"
      echo; echo '%post -p /sbin/ldconfig'
      echo '%postun -p /sbin/ldconfig'
      echo; echo '%files'
      echo "$PREFIX"
      echo "/etc/ld.so.conf.d/$name.conf"
    } > "$top/SPECS/$name.spec"
    rpmbuild -bb --define "_topdir $top" --define '__os_install_post %{nil}' \
      --define '_build_id_links none' --define 'debug_package %{nil}' "$top/SPECS/$name.spec"
    file="$(find "$top/RPMS" -type f -name '*.rpm' | head -n 1)"
    cp "$file" "$PACKAGES/"
    rm -rf "$PREFIX"
    rpm -i "$PACKAGES/$(basename "$file")"
  fi
  rm -rf "$stage" /tmp/rpm
  ldconfig
  echo "== GNUstep is installed from $(ls "$PACKAGES")"
}

case "${1:-}" in
  packages) step_packages ;;
  gnustep) step_gnustep ;;
  runtime) step_runtime ;;
  *) echo "usage: $0 packages|gnustep|runtime" >&2; exit 2 ;;
esac
