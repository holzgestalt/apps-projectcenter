# Cross toolchain: Debian packages and RPMs without Docker

ProjectCenter makes a GNUstep cross toolchain for Debian or Fedora on a Mac, or on another
Linux computer. It needs no Docker, no virtual machine and no root. Archive then builds
and packages a Linux target with it: Debian packages and Linux tarballs with Debian's,
RPMs with Fedora's.

```bash
brew install llvm lld make cmake pkgconf dpkg rpm
```

`dpkg` is for Debian toolchains, `rpm` (rpmbuild) for Fedora ones.

## In ProjectCenter

1. In the Deployment tab, select a Debian, Fedora / openSUSE (RPM) or Linux (tarball)
   platform of the Linux target, for arm64 or amd64.
2. Click **Make Toolchain…** next to **Toolchain**. After you confirm, the build log shows
   the steps of `make-toolchain.sh`, which takes about half an hour the first time. Stop
   ends it. Clicking it again makes the toolchain again from up-to-date sources.
3. The toolchain goes to `~/gnustep-toolchains/debian-trixie-<arch>` (`arm64`, `amd64`)
   or, for RPMs, `~/gnustep-toolchains/fedora-45-<arch>` (`aarch64`, `x86_64`), the
   platform's default **Toolchain**. Once it's there, a platform whose **Build** is left
   at its default builds with it (Cross Toolchain) instead of a container. Debian
   packages and Linux tarballs of one architecture share one toolchain.
4. **Archive** builds and packages on the Mac.

The GNUstep sources are the folders in the `GNUstepSources` user default, as for the
container (`defaults write org.gnustep.ProjectCenter GNUstepSources ~/Code/gnuStep` for
the Xcode build of ProjectCenter, domain `ProjectCenter` for the GNUstep build). Missing ones
are cloned: from the holzgestalt forks where there is one, libdispatch from swiftlang,
the rest from gnustep.

## From the command line

The scripts are ProjectCenter's resources, in `Framework/Resources`:

```bash
Framework/Resources/make-toolchain.sh --sources ~/Code/gnuStep              # Debian trixie arm64
Framework/Resources/make-toolchain.sh --arch amd64 --sources ~/Code/gnuStep
Framework/Resources/make-toolchain.sh --distribution fedora --sources ~/Code/gnuStep  # Fedora 45 aarch64
```

The default folder is `~/gnustep-toolchains/<distribution>-<release>-<arch>`, with the
architecture in the distribution's words, and `--sources` defaults to `$GNUSTEP_SOURCES`. Each step logs to `logs/<step>.log`.

`--from STEP` starts again at a step after one failed; `--only STEP` redoes one.

Each run starts from up-to-date sources. The folders in `--sources` that are git
checkouts are updated first, as `build-gnustep.sh` updates them: each one fetches all its
remotes and fast-forwards its branch to the branch it tracks (libs-gui's
`focused-history` to `holzgestalt/focused-history`, say). A checkout with local changes
(not counting untracked files), on a branch that tracks none, or with commits its tracked
branch hasn't is only fetched and is built as it is. The build log says so with a
`warning:` line. `--no-fetch` builds them as they are. Sources missing from `--sources`
are cloned new on every run from their default branch: libdispatch from swiftlang, and
GTK4Native from `github.com/holzgestalt/GTK4Native` unless a `gtk4native*` folder is in
`--sources`. So what is built of those is what is pushed. The `== sources` part of the
build log lists every source with where it comes from and its commit. The sysroot step
gets the distribution's current packages, downloading only the ones that changed.

## What it does

1. **sysroot**: downloads the development packages that GNUstep and GTK4Native build
   against, and everything they depend on.
   - Debian (`debian-sysroot.py`): the `-dev` packages, from deb.debian.org. Each
     package is checked against the SHA-256 sums in the release's `Packages` index.
     That index is checked against `InRelease`, fetched over HTTPS; its GPG signature
     is not checked.
   - Fedora (`fedora-sysroot.py`): the `-devel` packages, and `gcc` for its start files
     and libgcc, from dl.fedoraproject.org: the release's repository and its updates,
     the newer version of a package in both. Each package is checked against the
     SHA-256 sums in the repositories' primary index, which is checked against
     `repomd.xml`, fetched over HTTPS; its signature is not checked. The script reads
     RPM files itself (their zstd cpio payload, with Python 3.14's `compression.zstd`
     or the `zstd` tool), so it needs no `rpm2cpio`. It connects to IPv4 addresses
     first: an IPv6 address without a route would hold every download up.
   - The packages are unpacked into `sysroot/`, leaving out programs and
     documentation, and absolute links are made relative.
   - `packages.txt` lists the versions, and `files.tsv` which package each file came
     from.
2. **wrappers**: `bin/clang` and `bin/clang++` are LLVM's clang for the target with
   `--sysroot` and lld. They also map `/opt/gnustep` paths into the sysroot, because
   gnustep-make and `gnustep-config` name GNUstep where it will be on the target.
   - `bin/pkg-config` looks only in the sysroot.
   - `bin/gnustep-config` is the target's own.
   - `ar` and the other binutils are LLVM's, and `make` is GNU make 4.
   - `bin/plmerge` and `bin/pl2link` (`plmerge.py`) stand in for libs-base's tools,
     which gnustep-make runs for bundles and applications and which can't run here.
3. **libdispatch**: swift-corelibs-libdispatch, which Debian doesn't package and
   GTK4Native's Xcode SDK needs. Its `libBlocksRuntime` is the only blocks runtime:
   libobjc2 is built with `EMBEDDED_BLOCKS_RUNTIME=OFF`.
4. **libobjc2, tools-make, libs-base, libs-gui, libs-back, theme**: built as
   `gnustep-image.sh` builds them in the container: clang, library combo
   `ng-gnu-gnu`, fhs layout in `/opt/gnustep`, installed into the sysroot with
   `DESTDIR`.
   - libs-base can't run its configure tests on the target. `libs-base-cross.config`
     gives the answers a native configure gets on Debian with libobjc2.
5. **package**: `packages/projectcenter-gnustep_<version>_<arch>.deb` (or
   `projectcenter-gnustep-<version>-1.<arch>.rpm`), the runtime package, as the
   container makes it, for applications archived with **Include GNUstep** off. Its
   `Depends` come from the sysroot, via `debian-depends.py`. The RPM lists its
   `Requires` (as rpm's soname capabilities, `libgtk-4.so.1()(64bit)`) and the
   `Provides` of GNUstep's libraries itself: Homebrew's rpmbuild has no ELF reader, so
   it finds none.

`GNUstep.sh` in the folder sets up a cross build: compilers, `pkg-config`, the target's
gnustep-make. Archive sources it, then builds with `pc-xcode-build.py`. On a Mac,
`ldd` and `dpkg -S` can't answer, and rpmbuild finds no ELF dependencies, so Archive
takes the application package's `Depends` from `bin/debian-depends` and an RPM's
`Requires` from `bin/rpm-requires`. It makes RPMs with `rpmbuild --target <arch>-linux`,
so they are for Linux, not for the Mac, and in the v4 format (`_rpmformat 4`): Homebrew's
rpm 6 writes v6 packages by default, which Fedora's Software can't open. rpmbuild's tree
is a temporary folder, as its own `rm` of it fails when Finder writes into it. With **Include GNUstep** (the default), the
sysroot's GNUstep goes inside the application's bundle; otherwise Archive puts
`projectcenter-gnustep` next to the package, as it does for container builds.

Tried on a Mac (Apple silicon, Homebrew LLVM 23): EditGlyphData with GTK4Native
archived to a 10 MB `editglyphdata_1.0_arm64.deb` with GNUstep inside, 40 MB
installed. Every library the application and GNUstep need is either in the package
or in a Debian package of its `Depends`. Not yet installed on a Debian machine.

Fedora 45 aarch64, on the same Mac: the sysroot is 272 packages (154 MB downloaded,
370 MB unpacked). EditGlyphData archived to an 11 MB `editglyphdata-1.0-1.aarch64.rpm`
with GNUstep inside, whose `Requires` are Fedora's libraries (`libgtk-4.so.1()(64bit)`
and so on) and `/bin/sh`. With Include GNUstep off it is 1 MB and requires
`projectcenter-gnustep`, which goes next to it. Not yet installed on a Fedora machine.
libs-gui gets `ICU_LIBS` named, as Fedora's `icu-i18n.pc` names `icu-uc` only privately
and libs-gui uses both.

The wrapper keeps `-Wincompatible-pointer-types` a warning. Newer clang makes it an
error, while Debian's clang 19 warns. EditGlyphData needs that: it assigns
`-makeViewWithIdentifier:owner:`'s `NSView *` to an `NSTableCellView *`.

## Limits

- The packages are built, not run: smoke-testing the application still needs a Debian
  computer of that architecture.
- libdispatch is built from its main branch, and the other sources are taken as they
  are in `--sources`. Pin them there for a reproducible toolchain.
- The optional libs-base and libs-gui features that the container has and the sysroot
  leaves out are Avahi (NSNetServices), Aspell (spell checking) and CUPS (printing).
- Archive was tried with `pc-xcode-build.py` builds (EditGlyphData). GNUmakefile builds
  work with the toolchain's `GNUstep.sh` too: ProjectCenter itself (framework, application
  and modules) cross-builds with `make`.
