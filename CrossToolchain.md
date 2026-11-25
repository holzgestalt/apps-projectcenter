# Cross toolchain: Debian packages without Docker

ProjectCenter makes a GNUstep cross toolchain for Debian on a Mac, or on another Linux
computer. It needs no Docker, no virtual machine and no root. Archive then builds and
packages a Linux target with it.

```bash
brew install llvm lld make cmake pkgconf dpkg
```

## In ProjectCenter

1. In the Deployment tab, select a Debian or Linux (tarball) platform of the Linux target,
   for arm64 or amd64.
2. Click **Make Toolchain…** next to **Toolchain**. After you confirm, the build log shows
   the steps of `make-toolchain.sh`, which takes about half an hour the first time. Stop
   ends it.
3. The toolchain goes to `~/gnustep-toolchains/debian-trixie-<arch>`, the platform's
   default **Toolchain**. Once it's there, a platform whose **Build** is left at its
   default builds with it (Cross Toolchain) instead of a container. Debian packages and
   Linux tarballs of one architecture share one toolchain.
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
```

The default folder is `~/gnustep-toolchains/debian-<release>-<arch>`, and `--sources`
defaults to `$GNUSTEP_SOURCES`. `--from STEP` starts again at a step after one failed;
`--only STEP` redoes one. Each step logs to `logs/<step>.log`.

## What it does

1. **sysroot** (`debian-sysroot.py`): downloads the `-dev` packages that GNUstep and
   GTK4Native build against, and everything they depend on, from deb.debian.org.
   - Each package is checked against the SHA-256 sums in the release's `Packages`
     index. That index is checked against `InRelease`, fetched over HTTPS; its GPG
     signature is not checked.
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
5. **package**: `packages/projectcenter-gnustep_<version>_<arch>.deb`, the runtime
   package, as the container makes it, for applications archived with **Include
   GNUstep** off. Its `Depends` come from the sysroot, via `debian-depends.py`.

`GNUstep.sh` in the folder sets up a cross build: compilers, `pkg-config`, the target's
gnustep-make. Archive sources it, then builds with `pc-xcode-build.py`. On a Mac,
`ldd` and `dpkg -S` can't answer, so Archive takes the application package's
`Depends` from `bin/debian-depends`. With **Include GNUstep** (the default), the
sysroot's GNUstep goes inside the application's bundle; otherwise Archive puts
`projectcenter-gnustep` next to the package, as it does for container builds.

Tried on a Mac (Apple silicon, Homebrew LLVM 23): EditGlyphData with GTK4Native
archived to a 10 MB `editglyphdata_1.0_arm64.deb` with GNUstep inside, 40 MB
installed. Every library the application and GNUstep need is either in the package
or in a Debian package of its `Depends`. Not yet installed on a Debian machine.

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
