# Opening Xcode projects on GNUstep

Use **Project → Open…** to select an `.xcodeproj` directory. Opening
`project.pbxproj` through the application's file-open handler also works.
Every opened project is added to **File → Open Recent**, listed under its
`.xcodeproj` (or ProjectCenter project folder).
The navigator is a resizable outline on the left of the editor. For an Xcode
project it shows the project row and below it Xcode's own groups, in project
order (synchronized folders are sorted by name). Files that are not in any
Xcode group, such as `project.pbxproj`, the GNUmakefile and the sidecar plist,
follow under their ProjectCenter category (Supporting Files, Libraries).
A single file click opens the integrated editor. Multiple file selection and reveal-from-editor preserve full relative
paths. Above the code, a jump bar shows the file's place in the navigator
(project, groups, file); click a part to reveal it in the navigator. Code
editors show line numbers but no tab-stop ruler.
The file navigator distinguishes Objective-C implementations (violet `m`), headers
(teal `h`), C sources (blue `c`), XIB interfaces (yellow tools) and plists (purple
hierarchy) with original icons inspired by Xcode. Source icons use plain letters;
folder icons continue to follow the theme.

Selecting a modern Cocoa `.xib` opens an embedded interface editor. Its object
outline uses the theme's native control, with file/item icons and expandable
subtrees. Choose an object in the outline or click its canvas representation to
inspect it; canvas selection reveals any collapsed ancestors. Edit the
title or frame fields and press **Apply**, then use **File → Save** to write the
XIB. Double-clicking the file reuses the embedded editor. The canvas shows stored
frames; it does not solve Auto Layout constraints or instantiate custom classes.
Actions, outlets, constraints and other XML metadata are preserved. This initial
editor supports title and frame changes; adding controls, editing connections
and constraints, and legacy XIB formats are not supported.

Gorm interfaces (`.gorm`) open in the same editor. ProjectCenter reads the
GNUstep archive itself and saves title and frame edits into it, leaving the
rest of the archive as it was, so Gorm and GNUstep applications load the saved
interface as before. When Gorm is installed, opening a `.gorm` in its own
window starts Gorm.

The project window has a toolbar with Run, Stop and Build, and toggles for the
navigator, the bottom area and the inspector panel (Clean, Debug and Find can
be added by customizing it). Build and Clean switch the navigator to its Issues
tab, as in Xcode: a summary of the last build, then its errors, warnings and
notes grouped by file. Click an issue to open the file at its line. The Issues
tab opens by itself when a build fails, and its Build Log button shows the full
compiler output. Build and run output open in a bottom area below
the editor, which stays visible. The loaded-files list appears below the
navigator. Choosing separate panels in Preferences → Miscellaneous
(`UseTearOffWindows`) moves build, run and loaded files into their own windows
instead; an earlier ProjectCenter may have stored that choice as `YES`.
With GTK4Native, Project Open uses GTK's folder chooser: navigate to and select
the `.xcodeproj` folder itself, then press Open. File Open uses GTK's file chooser.
In File Open, navigate inside the `.xcodeproj` directory and select
`project.pbxproj` to load the project rather than a text editor. GTK's file
chooser navigates into folders; to select the wrapper folder itself use
Project Open instead.
Source files can be edited and saved normally. Xcode metadata is read-only:
ProjectCenter does not convert the project, write a `.pcproj`, regenerate the
GNUmakefile or rewrite the application's Info plist. Reopen to refresh the
file list after changing Xcode metadata or a synchronized folder's contents.

The reader supports OpenStep-format `project.pbxproj` files, nested PBXGroup
and PBXVariantGroup references, SOURCE_ROOT and absolute references, and
Xcode 16+ PBXFileSystemSynchronizedRootGroup folders. The browser includes the
project's local files, including files belonging to other targets; it does not
interpret target membership exclusions as a filter. Hidden files and symlinks
inside synchronized folders are skipped. Asset catalogs remain single entries.
SDK/build-product references and unresolved build-setting paths are omitted.

One application target must be selected. A project containing one application
target works immediately (test and aggregate targets do not count). For several
application targets, select one with `TargetName` below. Framework/tool-only
projects, `.xcworkspace`, build-setting expansion, Swift packages and Xcode
project editing are not implemented.

## Project and targets

Select the project row at the top of the navigator to see the project as
Xcode shows it: the project and its targets on the left; General, Build
Settings and Build Phases on the right. General shows the target type,
product name, bundle identifier, deployment target, version, configurations
(with their base `.xcconfig` files) and dependencies, and for the target
ProjectCenter builds also the GNUstep build script and executable. Build
Settings lists each setting per configuration, target values over project
values. Settings that come only from `.xcconfig` files are not shown.
Everything here is read-only.

## Debugging

Run (toolbar) starts the program under gdb, like Xcode; Stop ends the session.
The bottom area shows the debug bar (continue/pause, step over, step into,
step out) above the gdb console, where gdb commands can also be typed.

The sidebar has three tabs, selected with the icons above it:

- **Project**: the project's files.
- **Breakpoints**: all breakpoints. File breakpoints are grouped by file and
  show their source line; selecting one opens it in the editor. Use **+** to
  add an Objective-C exception breakpoint (`objc_exception_throw`) or a
  symbolic breakpoint (a function or method such as `-[NSView setFrame:]`),
  and **−** to delete the selected breakpoint.
- **Debug**: while the program is paused, the call stack of the stopped thread.
  The tab opens automatically when the program pauses. The first frame with
  the project's own code is selected and shown in the editor; select another
  frame to inspect it.

Click the editor's gutter to set or remove a breakpoint on a line. A blue tag
marks a breakpoint and a green marker the line where the program is paused.
For Xcode projects, breakpoints are stored per user in
`<Name>.xcodeproj/xcuserdata/<user>.xcuserdatad/ProjectCenter/Breakpoints.plist`,
next to Xcode's own per-user data, which version control normally ignores.
Xcode's own breakpoint files are not read.

The debugger needs gdb (Preferences → Build → Debugger, default `/usr/bin/gdb`)
and a build with debug information.

## Schemes, configurations and run destinations

As in Xcode, the toolbar of an Xcode project chooses what Build and Run do:

- **Scheme**: the targets to build, and the target that Run starts. The menu
  lists the schemes as Xcode does: the shared ones (`xcshareddata/xcschemes`),
  your own (`xcuserdata/<user>.xcuserdatad/xcschemes`), and one for each
  target that no scheme builds, which Xcode (and `xcodebuild`) create by
  themselves. They are in the order of Xcode's Manage Schemes, which also
  hides schemes. A scheme without a run target (a framework, say) only
  builds. Schemes added or changed in Xcode appear the next time the menu
  opens.
- **Destination** (macOS only): **My Mac** builds for this Mac's architecture,
  **My Mac (Rosetta)** for x86_64 on Apple silicon with Rosetta installed, and
  **Any Mac (arm64, x86_64)** builds both. Any Mac is for building only, so Run
  is disabled, as in Xcode. With Xcode's usual settings, Debug builds only the
  destination's architecture and Release builds both.
- **Configuration**: the build configuration for Build and Run (Debug,
  Release, or the project's own). A scheme starts with its Run action's
  configuration, as Xcode's Edit Scheme sets it; a different choice is kept
  for each scheme. Choosing the scheme's own configuration again removes it.

Opening a project selects the scheme of its application target. The choices
are kept per user in ProjectCenter's defaults (`PCXcodeBuildSelections`); the
Xcode project and its schemes are not changed. Configurations for Test,
Profile, Analyze and Archive are read but not used, because ProjectCenter has
only Build and Run.

## Building and running on macOS

ProjectCenter built with Xcode builds an Xcode project with `xcodebuild`:
`-scheme`, `-configuration` and `-destination` are the toolbar's choices, so
the products go to Xcode's DerivedData as when building in Xcode. A scheme that
`xcodebuild` doesn't list is built with `-target` instead. A `BuildScript` in
`GNUstep/ProjectCenter.plist` still takes precedence, and then only the
configuration is shown. Run starts the run target that was built for the chosen
configuration and destination (through `arch -x86_64` for My Mac (Rosetta)). It
does not build first. It runs under the debugger only where gdb is available,
which macOS doesn't ship.

## GNUstep build and debug integration

Reading an Xcode project does not supply Apple's SDKs or translate its build
phases. The Build/Clean controls use an existing `GNUmakefile` in the project
root. Alternatively, create `GNUstep/ProjectCenter.plist` beside the
`.xcodeproj`:

```text
{
    TargetName = MyApp;
    BuildScript = "scripts/build-gnustep.sh";
    Executable = "build/MyApp.app/MyApp";
}
```

`TargetName` is optional for a single application target. `BuildScript` and
`Executable` paths are absolute or relative to the directory containing the
`.xcodeproj`. The script is invoked with `/bin/bash` when Build/Clean is selected,
with the project root as its working directory and GNUstep Make arguments
(including `all`/`clean`) forwarded to it. Opening a project does not execute it.
The toolbar's Configuration chooses `debug=yes` for a configuration named
Debug and `debug=no` for others, in place of the Build Options' debug switch.
Without a script or makefile, browsing/editing still works and Build explains
that a GNUstep build is required. `Executable` selects the binary for Run/Debug;
otherwise ProjectCenter searches its standard GNUstep output locations.
Launch ProjectCenter from a shell with the correct GNUstep environment loaded.
Project settings changed in the Inspector/Build panels are session-local;
edit the sidecar file for persistent configuration.

This workspace configures EditGlyphData to use its existing build script,
resource preparation and GTK4Native output in `build/EditGlyphData/`.

## Workspace validation

```bash
bash scripts/build-projectcenter.sh install
bash scripts/test-projectcenter-xcode.sh
bash scripts/test-projectcenter-xcode.sh --integration
bash scripts/test-projectcenter-interface.sh
```

Run from the workspace root. The integration test uses Xvfb and GNUstep's user
defaults. It opens EditGlyphData, checks duplicate-open handling and resource
paths, verifies save leaves the original project/build files unchanged, checks
the configured executable, debugs a small test program (line and exception
breakpoints, call stack, frame selection, Stop) and closes the project.
The focused interface test exercises the theme's native outline rows, icons,
disclosure controls, nested object selection and document reload without using
the project file chooser.
