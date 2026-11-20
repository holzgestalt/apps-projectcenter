# ProjectCenter

This is the schriftgestalt fork of GNUstep's ProjectCenter IDE. It turns ProjectCenter into an
Xcode-like IDE for Cocoa projects on GNUstep, and makes ProjectCenter itself buildable with Xcode on macOS.

## Goals

1. **Xcode projects on GNUstep.** Open `.xcodeproj` bundles directly and work on them as in Xcode:
   navigator with Xcode's groups, jump bar, toolbar, bottom area, inspector, integrated gdb debugger,
   and a visual XIB editor. Xcode metadata stays read-only, except for the values of the project
   editor's General pane, which `PCXcodeProject` changes one line at a time. Builds go through an
   existing GNUmakefile or `GNUstep/ProjectCenter.plist`. See `XcodeProjects.md` for the user-facing
   behaviour. The main test project is EditGlyphData, with the GTK4Native theme.
2. **ProjectCenter on macOS.** Build and run ProjectCenter itself from `ProjectCenter.xcodeproj`
   against Cocoa, from the same sources as the GNUstep build.
   - Status: builds and runs. Preferences load from the module bundles, and `.xcodeproj` projects open
     in the Xcode-style window with the navigator. On macOS, Build uses `xcodebuild` and Run starts
     the product from DerivedData (`PCXcodeProject`); there is no debugger, as the debugger module
     needs gdb. The toolbar's scheme, destination and configuration popups (`PCProjectWindow`)
     choose the `xcodebuild` arguments; `PCXcodeProject` reads the schemes and keeps the choice
     in the user defaults. Where GNUstep is installed, the destination **My Mac (GNUstep)**
     builds with `make` in the environment of `GNUstep.sh` and runs the GNUstep build, with the
     theme. The installation is the one chosen in Preferences → Miscellaneous (the user default
     `GNUstepInstallation`, `+[PCXcodeProject GNUstepMakefiles]`), else the one found. No GNUstep
     is installed on the development Mac (the sources are in `~/Code/gnuStep`, unbuilt), so it was
     only tried with a stand-in.
   - Interfaces: each `.gorm` has a `.xib` next to it, converted once from it, which the Xcode
     targets compile. Embedded unnamed images and GNUstep theme images (`common_ret`) were not
     converted.
   - Not yet checked on macOS: the editor beyond opening files and most panels. The XIB editor
     was tried on a copy of `Info.xib` (adding, connecting, editing, undo, saving).
3. **Stay a GNUstep application.** The GNUmakefile build and the GNUstep CI must keep working.
   Changes for macOS must not break or degrade the GNUstep version.

## Building

- **macOS:** open `ProjectCenter.xcodeproj`. There are two schemes:
  - `ProjectCenter` builds the framework, the 14 module bundles and the app.
  - `XcodeProjectTests` builds a Foundation-only test tool.
  - The app icon is `Images/ProjectCenter.icns`, made once with `sips` and `iconutil` from
    `Images/ProjectCenterx4.tiff`, a 192 px upscale of the GNUstep icon `Images/ProjectCenter.tiff`.
    It holds sizes up to 128 px; macOS scales up for larger ones. `Resources/Info-macOS.plist` holds the Info.plist keys that Xcode
    doesn't generate, including the project document types that Open Recent needs. On Cocoa,
    `PCDocumentController` (`PCProjectDocument.m`) sends recent projects to `-application:openFile:`.
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
  `PCDeployment` (Foundation only) holds the Deployment, kept as build settings of the targets
  (a Mac target's `ARCHS`; a Linux target, `SDKROOT = linux`, has `GNUSTEP_DISTRIBUTIONS` and
  `GNUSTEP_<DISTRIBUTION>_<SETTING>`, see `PCDeployment.h`), and writes the shell scripts that
  Archive (`PCProjectBuilder`) runs:
  `build/Deployment/archive.sh`, which builds and packages each platform natively, with a cross
  toolchain's `GNUstep.sh` or in a Docker/Podman container. `XcodeProjectTests` runs them with a
  stand-in toolchain. The XIB editor's
  model is `PCInterfaceDocument` (Foundation only): every edit changes only its own XML, and an
  unchanged XIB is written back byte for byte (`XcodeProjectTests` checks every `.xib`).
  `PCInterfaceInspector` is the editor's Xcode-style inspector, and `PCInterfaceRendering` draws
  the canvas with the cells of the active theme.
- `Modules/`: bundles loaded at runtime, which are project types (`.project`), the editor
  (`.editor`), the parser (`.parser`), the debugger (`.debugger`) and preference panes
  (`.preferences`).
- `Tests/`: `XcodeProjectTests.m` (Foundation only). The other tests are GNUstep and Xvfb
  integration tests.

## Conventions

- **Interfaces:** the `.xib` is the source; edit it in Xcode or in ProjectCenter's XIB editor. The
  `.gorm` files are only converted once, when a project moves to XIBs: with **Edit → Convert →
  To XIB...** in ProjectCenter, or `Tools/gorm2xib/regenerate.sh`, which converts only the
  interfaces that have no `.xib` yet (`--replace` overwrites them). The GNUstep build still
  installs the `.gorm` files (see the GNUmakefiles), so it doesn't get changes made in a `.xib`.
  `PCGormArchive` must keep writing unchanged archives back byte for byte (`XcodeProjectTests`
  checks every `.gorm`). See `Tools/gorm2xib/README.md`.
  New interfaces are XIBs only, with no `.gorm`, and both builds install the `.xib`. They use
  Auto Layout constraints; views inside scroll views (tables, forms, the canvas) and the split
  view's panes keep autoresizing masks. They were only tried on macOS:
  - `Framework/English.lproj/ProjectEditor.xib`, the Xcode project editor
    (`PCXcodeProjectEditor`). Its General pane has fixed forms for the project and a target,
    which the code fills from `-generalRows`. The target list's starting width is set in code
    (`-_placeDivider:`): a width constraint on a split view pane pulls the divider back after a drag.
    Its Deployment tab (`PCDeploymentEditor`) shows the selected target's: macOS's
    Architectures, or a Linux target's distributions; the selected one's form is built in code
    from `+[PCDeployment fieldsForKind:]`.
  - `Framework/English.lproj/InterfaceEditor.xib`, the XIB editor (`PCInterfaceEditor`): the
    object outline, canvas, inspector panes, Connections controls and object library. The
    inspector's Identity, Attributes and Size forms are built for the selection from the
    property tables in `PCInterfaceInspector.m`, and the outline's row view in code.
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
