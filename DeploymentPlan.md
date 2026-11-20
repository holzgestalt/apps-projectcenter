# Plan: cross compiling, and building with the Deployment settings

Status: proposal, nothing of it is built yet. Since it was written, the
Deployment settings moved into the targets' build settings: a Mac target
(only `ARCHS`) and a Linux target (`SDKROOT = linux`) with its distributions;
see `XcodeProjects.md`, "Deployment and Archive". A platform below is a
target's macOS entry or one of a Linux target's distributions.

It extends the Deployment tab
(`PCDeployment`, `PCDeploymentEditor`) and Archive (`PCProjectBuilder`), see
`XcodeProjects.md`, "Deployment and Archive".

## Why

- GNUstep can't be built on macOS: clang compiles the GNUstep runtime only
  for ELF and Windows binaries (the v2 ABI refuses Mach-O, the v1 ABI crashes
  the backend). So a Mac never has a native GNUstep, and "My Mac (GNUstep)"
  only works where someone has one by other means.
- Build and Run use the toolbar (scheme, configuration, destination), Archive
  uses the Deployment platforms. The same project is set up twice, and what
  Build checks is not what Archive ships.

## Terms

- **Host:** the computer ProjectCenter runs on (macOS or Linux; Windows later).
- **Platform:** an entry of the Deployment tab: a kind (macOS, Debian / Ubuntu,
  Fedora / openSUSE, Linux, Windows), an architecture and its settings.
- **Way** (the platform's Build setting), how the host builds it:
  - **Native:** the host is the platform (same system, same architecture).
  - **Container:** in a Docker or Podman container of the platform's system,
    any architecture the container tool runs (emulated where it differs).
  - **Toolchain:** cross compiled on the host with a toolchain made for the
    platform (below). No container while building; fastest and needs nothing
    emulated.

Which ways each host has:

| Platform \ Host | macOS | Debian (amd64 / arm64) |
|---|---|---|
| macOS | Native (xcodebuild) | – |
| Debian, RPM, Linux, same arch | Container, Toolchain | Native, Container, Toolchain |
| Debian, RPM, Linux, other arch | Container (emulated), Toolchain | Container (emulated), Toolchain |
| Windows | Toolchain (later) | Toolchain (later) |

## Part 1: Build and Run use the platform settings

One place for the settings: a platform's settings are what Build, Run and
Archive use for it. Archive is Build plus packaging, for every platform that is
turned on.

1. **Destinations are platforms.** The toolbar's Destination menu lists the
   Deployment platforms the host can build (all of them, turned on or not;
   the check box only says whether Archive includes it). On macOS without a
   macOS platform, an implicit one with the defaults stands in for "My Mac",
   so a project with no Deployment works as today. On Debian, the default is
   the platform of the host's kind and architecture, else an implicit Debian
   one, built Native.
   - "Any Mac" becomes the macOS platform's Architecture "Universal"; Rosetta
     its "Intel (x86_64)". "My Mac (GNUstep)" goes away: a Debian platform
     built in a Container replaces it on a Mac.
2. **The toolbar edits the chosen platform.** Scheme (macOS) and Configuration
   are settings of the platform, so the toolbar popups show and change them
   (saved as build settings of the target, like the Deployment tab does).
   Everything else stays in the Deployment tab.
3. **Build** runs the build half of the platform's Archive script (everything
   up to "Built $APP", no packaging), into `build/Deployment/<platform>`:
   - macOS: `xcodebuild build` with the platform's Scheme, Configuration and
     Architecture; Signing applies only to Archive.
   - GNUstep platforms: `make` (or `BuildScript`) with `debug=`, Make
     Arguments, natively, in the container or with the toolchain.
   - The build log and errors appear as today; error lines with container
     paths (`/src/...`) are mapped back to the project folder.
4. **Run** starts the build of the chosen platform:
   - macOS and Native: as today (with `-GSTheme` for GNUstep).
   - Container: `docker run` with the project mounted, the platform's image,
     and `DISPLAY=host.docker.internal:0` to XQuartz on a Mac (it must allow
     network clients) or the host's X server on Linux. Toolchain builds of
     another system run the same way, in the platform's container.
   - Debugging (gdb) stays Native only at first.
5. **Code:** `PCDeployment` gets `+buildScriptForDeployment:...` (the shared
   build half, so Archive and Build can't drift apart) and
   `+destinationsForProject:host:`; `PCXcodeProject`'s build selection keeps
   only which platform is chosen; `PCProjectBuilder` and `PCProjectLauncher`
   run the platform's script. `XcodeProjectTests` checks the scripts and the
   destinations for both hosts with stand-in tools, as it does for Archive.

## Part 2: proper cross compiling (the Toolchain way)

A toolchain is one folder that builds for one platform (system and
architecture), made once with **Make Toolchain…** in the Deployment tab:

```
<toolchain>/
  sysroot/                   the platform's /usr and /lib, with GNUstep
                             (libobjc2, libs-base, libs-gui, libs-back) built
                             for it, and the libraries they link
  bin/<triple>-clang         clang --target=<triple> --sysroot=… -fuse-ld=lld
  bin/<triple>-clang++
  bin/                       host builds of the tools GNUstep's make runs
                             while building (see "Build-time tools")
  share/GNUstep/Makefiles/   the platform's gnustep-make, GNUstep.sh among
                             them, with paths pointing into sysroot/
  toolchain.plist            platform, triple, image, versions
```

The Toolchain setting of a platform names this folder (today it names the
folder of GNUstep.sh; that becomes `<toolchain>/share/GNUstep/Makefiles`).

### Making a toolchain

1. **Host tools:** clang and lld (`brew install llvm lld` on a Mac, which
   also gives `ld.lld`; `apt install clang lld` on Debian) and GNU make 4
   (`brew install make`; macOS's make is 3.81).
2. **The sysroot,** made in a container of the platform (same image and
   architecture as its Container way, emulated once if it differs):
   - install the platform's -dev packages (the list of `build-gnustep.sh`),
   - build libobjc2, tools-make, libs-base, libs-gui and libs-back from the
     sources chosen in the preferences (default: clone them; `~/Code/gnuStep`
     here, to include the holzgestalt changes), with clang and the gnustep-2.2
     ABI, into `/usr/GNUstep` (gnustep layout) or the fhs layout,
   - export `/usr/include`, `/usr/lib`, `/lib` and the GNUstep prefix from the
     container into `sysroot/` (`docker create` + `docker cp`, keeping
     symlinks; absolute symlinks are rewritten to relative ones).
   - The theme (GTK4Native) is built into the sysroot the same way, if chosen.
3. **Makefiles:** copy the platform's installed gnustep-make into
   `share/GNUstep/Makefiles`, rewrite `GNUstep.conf` so every
   `GNUSTEP_*_ROOT` points into `sysroot/`, and set `CC`, `OBJC`, `CXX`,
   `LD` and `GNUSTEP_HOST*` to the wrappers and the triple in its
   `config.make`. `GNUstep.sh` of the toolchain then sets up a cross build:
   `make` builds `<Target>.app` for the platform on the host.
4. **Check:** build a small test application with the toolchain and run it in
   the platform's container (`<App>.app/<App> --version`-like smoke test, and
   `ldd` finding every library in the sysroot).

### Build-time tools

GNUstep's make runs tools of libs-base while building an application:
`plmerge` merges the project's own Info plist into Info-gnustep.plist (its
failure is ignored, so the entries would quietly be missing) and `pl2link`
writes the `.desktop` file (its failure stops the build); see
`Instance/application.make` of tools-make. They are platform binaries in the
sysroot and can't run on the host:

- On a Debian host for another architecture: build the tools natively (the
  host has GNUstep) and put them in `bin/`.
- On a Mac there is no GNUstep to build them with. The toolchain installs
  small wrappers in `bin/` that run the sysroot's tool in the platform's
  container (`docker run … plmerge "$@"`, with the project mounted). Slow,
  but these run only once per build. If that's too slow: write the two tools
  with Foundation on macOS (a plist merge, and a plist to `.desktop` file) in
  ProjectCenter's `Tools/`.

### Packaging

Unchanged: dpkg-deb, rpmbuild, tar and zip run on the host
(`brew install dpkg rpm` on a Mac); `problemsWithDeployment` already says when
one is missing.

### Windows (later)

The same shape with a MSYS2 clang64 sysroot (GNUstep built there, or the
GNUstep Windows MSVC packages) and llvm-mingw as the compiler; Run needs a
Windows VM. Not part of the first steps.

## Order

1. Shared build script for Build and Archive (Part 1.3, 1.5), tests.
2. Destinations from platforms, toolbar edits the platform (1.1, 1.2); remove
   "My Mac (GNUstep)" and the GNUstep preference's role for macOS (on Linux
   hosts it still chooses the Native GNUstep).
3. Run for Container builds with XQuartz (1.4). From here a Mac can build and
   run the GNUstep version of a project, in a container.
4. Make Toolchain… for Debian arm64 and amd64 from a Mac and from Debian
   (Part 2), checked with EditGlyphData and GTK4Native.
5. RPM and plain Linux toolchains (same steps, other image), then Windows.

## Open questions

- Should the toolbar change the platform's settings (proposed), or only
  override them for Build and Run, leaving Archive's alone?
- Debug and Release: one platform with Configuration switched in the toolbar
  (proposed), or a platform each?
- Where the toolchains live: `~/Library/Application Support/ProjectCenter/
  Toolchains` (Mac) and `~/GNUstep/Library/ProjectCenter/Toolchains`
  (Linux), shared by all projects (proposed), or in the project folder.
- Needs on this Mac for steps 3 and 4: Docker (`brew install colima docker`,
  no admin password) and XQuartz (its installer asks for one).
