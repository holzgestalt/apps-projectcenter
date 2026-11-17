# ProjectCenter

This is the schriftgestalt fork of GNUstep's ProjectCenter IDE. It turns ProjectCenter into an
Xcode-like IDE for Cocoa projects on GNUstep, and makes ProjectCenter itself buildable with Xcode on macOS.

## Goals

1. **Xcode projects on GNUstep.** Open `.xcodeproj` bundles directly and work on them as in Xcode:
   navigator with Xcode's groups, jump bar, toolbar, bottom area, inspector, integrated gdb debugger,
   and a visual XIB editor. Xcode metadata stays read-only. Builds go through an existing GNUmakefile
   or `GNUstep/ProjectCenter.plist`. See `XcodeProjects.md` for the user-facing behaviour. The main
   test project is EditGlyphData, with the GTK4Native theme.
2. **ProjectCenter on macOS.** Build and run ProjectCenter itself from `ProjectCenter.xcodeproj`
   against Cocoa, from the same sources as the GNUstep build.
   - Status: everything compiles.
   - Interfaces: each `.gorm` has a generated `.xib` next to it, which the Xcode targets compile.
     Embedded unnamed images and GNUstep theme images (`common_ret`) are not converted yet.
   - Still missing at runtime: `PCBundleManager` looks for `<bundle>/Resources/Info.table`, which on
     macOS is `Contents/Resources/Info.table`.
3. **Stay a GNUstep application.** The GNUmakefile build and the GNUstep CI must keep working.
   Changes for macOS must not break or degrade the GNUstep version.

## Building

- **macOS:** open `ProjectCenter.xcodeproj`. There are two schemes:
  - `ProjectCenter` builds the framework, the 14 module bundles and the app.
  - `XcodeProjectTests` builds a Foundation-only test tool.
- **GNUstep:** run `make && make install` with the GNUstep environment loaded.
  - The workspace scripts in `XcodeProjects.md` (`scripts/build-projectcenter.sh`,
    `scripts/test-projectcenter-xcode.sh [--integration]`, `scripts/test-projectcenter-interface.sh`)
    run from the workspace root, outside this repository.
  - CI is `.github/workflows/main.yml` (GNUstep on Ubuntu).

## Layout

- `*.m`, `Headers/*.h`: the application (menus, preferences, app controller).
- `Framework/`, `Headers/ProjectCenter/`, `Headers/Protocols/`: ProjectCenter.framework, which holds
  the project model, project window, navigator, builder, launcher and Xcode project reader
  (`PCXcodeProject`, `PCXcodeProjectEditor`, `PCNavigators`, `PCInterfaceEditor`).
- `Modules/`: bundles loaded at runtime, which are project types (`.project`), the editor
  (`.editor`), the parser (`.parser`), the debugger (`.debugger`) and preference panes
  (`.preferences`).
- `Tests/`: `XcodeProjectTests.m` (Foundation only). The other tests are GNUstep and Xvfb
  integration tests.

## Conventions

- **Interfaces:** the `.gorm` is the source. After changing one in Gorm, regenerate the `.xib` files
  with `Tools/gorm2xib/regenerate.sh` and commit both. Don't edit the generated `.xib` by hand.
  `PCGormArchive` must keep writing unchanged archives back byte for byte (`XcodeProjectTests`
  checks every `.gorm`). See `Tools/gorm2xib/README.md`.
- **Keep both build systems in sync.** The GNUmakefiles define what each target contains. When adding
  or removing a source or resource, update the GNUmakefile and `ProjectCenter.xcodeproj` together.
- **Portability:**
  - Prefer APIs that exist on both platforms.
  - Put GNUstep-only code behind `#ifdef GNUSTEP`.
  - Cocoa stand-ins for GNUstep conveniences live in `Headers/ProjectCenter/PCCompat.h` and
    `Framework/PCCompat.m`, inside `#ifndef GNUSTEP`. Examples are the `RETAIN`/`RELEASE`/`ASSIGN`
    macros, `_()`, `NSDebugLog` and `-[NSFont widthOfString:]`.
  - `PCCompat.h` is the Xcode prefix header and is imported by `PCDefines.h`.
- **Memory:** manual retain/release, no ARC.
- **Formatting:** two spaces, no tabs, laid out as Xcode's Re-Indent does: braces on their own line
  at the level of their statement, and message keywords aligned on their colons. Match the
  surrounding code.
- **New files** carry the GPL header used by the existing sources.
- **Don't commit** `build.log`, `.DS_Store` or `xcuserdata`.
