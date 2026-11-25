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

Selecting a modern Cocoa `.xib` opens an embedded interface editor: the object
outline on the left, the canvas in the middle and an inspector on the right.
Its object outline uses the theme's native control, with file/item icons and
expandable subtrees. Choose an object in the outline or click its canvas
representation to inspect it; canvas selection reveals any collapsed ancestors.
The canvas draws windows with their title bar, and controls with the cells of
the active theme (GSTheme on GNUstep, Aqua on macOS), set up from the XIB:
buttons, pop-up buttons, text fields, sliders, steppers, segmented controls,
image views, matrices, boxes, scroll and table views, tab views and custom
views.

The inspector has Xcode's panes, chosen at its top:

- **Identity** shows the custom class and module, the identifier, the
  Interface Builder label, the object ID, the tool tip and any user defined
  runtime attributes.
- **Attributes** shows a section for each class of the object, as Xcode does:
  "Pop Up Button", "Button", "Control" and "View" for a pop-up button,
  "Window" for a window, and so on, with pop-ups, check boxes, fields, color
  wells and font choices for what the XIB holds. A change applies at once (a
  field when you press Return or leave it); a value set to its default is left
  out of the XIB, as Xcode does. **Other Attributes** lists the attributes no
  section shows, so every XML attribute stays editable; an empty value removes
  one, and `name=value` adds one.
- **Size** shows the frame, whether constraints or the autoresizing mask lay
  the view out (with the mask's flags), content hugging and compression
  resistance priorities, and the view's constraints: click one to select it.
- **Connections** lists the outlets, actions and bindings from the object (→)
  and to it (←). Remove the selected one, or choose Outlet or Action, enter the
  property or action name and the object at the other end, and press
  **Connect**.
- **Constraints** appear in the object list, as in Xcode: a Constraints group
  below each view that holds some, with each constraint written out as Xcode
  writes it, leaving out the view that holds it: `Name.leading = leading + 20`,
  `OK.width ≥ Name.width - 10 @250`; a standard spacing has no number. Objects
  are named as in Xcode too: by their Interface Builder label, title, or kind
  ("Text Field"). Selecting a constraint outlines its views on the canvas, and
  the Attributes and Size panes show it as Xcode's inspector does: its kind ("Horizontal
  Space Constraint"), first and second item with their attributes (the
  item menus also reverse the items), relation,
  constant (empty for the standard spacing), priority, multiplier, identifier
  and "Remove at build time". Changed attributes are written in Xcode's order.
  **Delete** removes the constraint.
- Below the editor, choose an object from the library (buttons, labels, text
  fields, pop-up buttons, sliders, image views, boxes, custom views, menu items)
  and press **Add** to add it to the selected window or view, or after the
  selected menu item. **Delete** (or **Edit → Delete**) removes the selected
  object with its subviews and with the connections and constraints that refer
  to them.
- Drag a view on the canvas to move it, or drag one of the handles at its
  corners and edges to resize it.
- **Edit → Undo** and **Redo** step through the edits.

Use **File → Save** to write the XIB. Double-clicking the file reuses the
embedded editor. The XIB is the document: an edit changes only the XML of what
it is about, new elements are laid out as Xcode writes them, and everything
else, including what the editor doesn't show, is saved as it was. A diff of the
saved file shows only the edit. The canvas shows stored frames; it does not
solve Auto Layout constraints or instantiate custom classes. Legacy XIB formats
are not supported.

Gorm interfaces (`.gorm`) open in the same editor. ProjectCenter reads the
GNUstep archive itself and saves title and frame edits (including moving and
resizing on the canvas) into it, leaving the rest of the archive as it was, so
Gorm and GNUstep applications load the saved interface as before. The other
inspector edits, the library and Delete work on XIBs only. When Gorm is installed, opening a `.gorm` in its own
window starts Gorm.

To move a project's interfaces to XIBs, choose **Edit → Convert → To XIB...**,
as Xcode's Edit → Convert → To String Catalogs... moves strings files to the
current format. It lists the project's `.gorm` interfaces (not the copies in
build folders and built bundles) and writes a XIB next to each one you select.
Interfaces that already have a XIB are listed as "Replaces the XIB" and are not
selected, as the XIB is the source from then on. The Log Panel lists what a XIB
leaves out, such as GNUstep theme images and unnamed embedded images. The
project isn't changed: add the new XIB files to the targets that use them.

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
Source files can be edited and saved normally. Xcode metadata is read-only,
apart from the values the project editor's General pane edits (see below):
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
project editing beyond the General pane are not implemented.

## Project and targets

Select the project row at the top of the navigator to see the project as
Xcode shows it: the project and its targets on the left; General, Build
Settings and Build Phases on the right. Build Settings lists each setting per
configuration, target values over project values. Settings that come only
from `.xcconfig` files are not shown.

General is laid out in sections, as in Xcode. For a target:

- **Target**: its type and product name.
- **Identity**: display name, bundle identifier, version and build, from the
  target's Info.plist or the build settings Xcode generates it from.
- **Deployment**: the minimum macOS version, the main interface and the
  Info.plist.
- **App Icon**, and **Frameworks and Libraries** (the libraries it links).
- **Build**: configurations (with their base `.xcconfig` files),
  dependencies and an external target's build tool.
- **GNUstep**, for the Linux target (one whose `SDKROOT` is `linux`), or
  without one for the target ProjectCenter builds: the build script, the
  executable and the theme (see below). They can be edited here: a path is
  saved when you press Return or leave the field. With a Linux target they are
  its build settings `GNUSTEP_BUILD_SCRIPT`, `GNUSTEP_EXECUTABLE` and
  `GNUSTEP_THEME`, in every configuration; without one, they are kept in
  `GNUstep/ProjectCenter.plist`. A value still in that file from before is
  read until it is changed, and then moves into the Linux target.

What Xcode's General pane has only for the App Store or for Xcode itself (App
Category, Supported Destinations, Development Assets) is left out. Every
field is always shown, empty when the project has no value for it; a field
that can't be edited here, such as an Info.plist key of a target without an
Info.plist, is shown as plain text or as a disabled popup.

Values that Xcode's General pane edits can be edited here too, and are saved
where Xcode saves them:

- **Product name, bundle identifier, version, build and Info.plist** are text
  fields, saved when you press Return or leave the field.
- **Minimum macOS, main interface and app icon** are popups. The main
  interface lists the XIBs of the target's resources, and the app icon the
  icon sets of its asset catalogs, or else its `.icns` files.
- **Development region**, on the project row, is a popup of the project's
  localizations.
- **Where they go:** a build setting goes into every configuration of the
  target. A value the Info.plist has itself goes into the Info.plist; one it
  takes from a setting (`$(MARKETING_VERSION)`) goes into that setting. Each
  field's tooltip says where.
- **How:** only the edited line of `project.pbxproj` or the Info.plist changes,
  and the rest stays as Xcode wrote it. `project.pbxproj` is only written when
  the result still reads as a property list.
- **Read-only:** the target's type, which is fixed when the target is made, as
  in Xcode, and everything else.

**Theme** chooses the GNUstep appearance for Build and Run. Build passes the
selected provider as `GNUSTEP_APPLICATION_THEME` to the build script or make,
so the executable links that provider. Rebuild after changing it. The menu lists
installed application providers (for example Default, Classic and GTK4Native).
**Application Default** removes the override and uses the application's own
build default; it also clears any theme override inherited from ProjectCenter's
process. The selection is stored in `GNUstep/ProjectCenter.plist`, and does not
change the Xcode project or affect Cocoa builds on macOS.

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
  destination's architecture and Release builds both. **My Mac (GNUstep)**,
  shown where GNUstep is installed, builds and runs with GNUstep instead (see
  below).
- **Configuration**: the build configuration for Build and Run (Debug,
  Release, or the project's own). A scheme starts with its Run action's
  configuration, as Xcode's Edit Scheme sets it; a different choice is kept
  for each scheme. Choosing the scheme's own configuration again removes it.

Opening a project selects the scheme of its application target. The choices
are kept per user in ProjectCenter's defaults (`PCXcodeBuildSelections`); the
Xcode project and its schemes are not changed. Configurations for Test,
Profile and Analyze are read but not used, because ProjectCenter has only
Build, Run and Archive; a macOS platform of the Deployment (below) archives
with the scheme's Archive configuration.

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

### My Mac (GNUstep)

Where GNUstep is installed on the Mac, the Destination menu also has **My Mac
(GNUstep)**. It builds and runs the project as ProjectCenter does on GNUstep:

- **Choosing GNUstep:** **Preferences → Miscellaneous → GNUstep** sets the
  installation to use: its prefix (such as `~/gnustep-root` or `/usr/GNUstep`)
  or the folder of `GNUstep.sh`. The field shows in grey the GNUstep found
  when it is empty. A folder without `GNUstep.sh` is refused; if one chosen
  earlier has none any more, there is no GNUstep (no My Mac (GNUstep), and
  Build says so) rather than another one. A change applies at once, also to
  the Deployment's native builds. The GNUstep build of ProjectCenter doesn't
  have the field yet (its preferences still come from the `.gorm`); there,
  `defaults write ProjectCenter GNUstepInstallation <folder>` sets it.
- **Finding GNUstep:** with no GNUstep chosen, ProjectCenter looks for
  `GNUstep.sh` in `GNUSTEP_MAKEFILES` if it is set. Otherwise it asks
  `gnustep-config`, found on the `PATH` or in `/usr/GNUstep/System/Tools`,
  `/usr/GNUstep/Local/Tools`, `/usr/local/bin`, `/opt/homebrew/bin` or
  `/opt/local/bin`. Otherwise it tries the usual makefile folders of a
  GNUstep, Homebrew or MacPorts install. ProjectCenter looks once, when it
  starts.
- **Build** runs the build tool from the Build preferences (`/usr/bin/make`) on
  the project's GNUmakefile, or its `BuildScript`, with the environment that
  `GNUstep.sh` sets up. The configuration chooses `debug=yes` or `debug=no`.
- **Run** starts the GNUstep build (`Executable`, or `<Target>.app` in the
  project folder) in the same environment, with the project's **Theme**
  (`-GSTheme`).
- The choice is kept per project, like the other destinations.

## Deployment and Archive

The **Deployment** tab of the project editor (select the project row in the
navigator, then a target) shows what **Archive** makes of the selected target.
An application has a Mac target, which Xcode builds, and for GNUstep a Linux
target: a target whose `SDKROOT` build setting is `linux`. Xcode shows that
target as broken (it has no such SDK); the Mac targets are not affected.

- A **Mac target** has one entry, macOS, and one setting: **Architectures**,
  the target's `ARCHS` (Universal leaves it unset, so Xcode's standard
  architectures apply; Apple silicon `arm64`; Intel `x86_64`). Everything else
  comes from the Xcode project and its scheme.
- A **Linux target** lists the distributions it is packaged for. Add one with
  **+**, remove the selected one with **−**. Its settings are shown on the
  right, starting with **Distribution**, which changes it into another (say,
  Debian / Ubuntu into Fedora / openSUSE; the settings both have are kept),
  and **Architectures**, the target's `ARCHS` for all its distributions
  (`x86_64`, `aarch64` or both; This Computer leaves it unset). Archive
  packages each distribution once for every architecture.

Everything is saved at once as build settings of the target, in every
configuration, where Xcode leaves them alone: `GNUSTEP_DISTRIBUTIONS` (such as
`Debian RPM`) and one `GNUSTEP_<DISTRIBUTION>_<SETTING>` for each setting that
was changed, such as `GNUSTEP_DEBIAN_MAINTAINER` (`DEBIAN`, `RPM`, or
`TARBALL` for the Linux `.tar.gz`). An empty field takes the default shown in
grey, mostly from the project (product name, version), and is not written.

Archive makes the macOS archive for a Mac application in the selected scheme
and packages the configured distributions of its Linux targets. A Windows
target (`SDKROOT = windows`) is not supported yet.

| Platform | Makes | Built with |
| --- | --- | --- |
| macOS | a `.zip` of the application | `xcodebuild archive` |
| Debian / Ubuntu | a `.deb` package (`dpkg-deb`) | GNUstep |
| Fedora / openSUSE | an `.rpm` package (`rpmbuild`) | GNUstep |
| Linux | a `.tar.gz` of the application bundle | GNUstep |
| Windows (not yet for targets) | a `.zip` of a folder with the application bundle and its DLLs | GNUstep |

- **macOS** archives the selected scheme in the scheme's
  Archive configuration, signed as the project's settings say, into a `.zip`.
  macOS platforms are archived on a Mac with Xcode.
- **GNUstep platforms** build the Linux target with ProjectCenter's compiler,
  as Build does on GNUstep (no GNUmakefile needed), or with the target's
  `GNUSTEP_BUILD_SCRIPT` (`debug=no`, or `debug=yes` for a Debug
  configuration, plus the **Make Arguments**), into
  `build/Deployment/<platform>`. **Build** chooses how:
  - **Native**: with this computer's GNUstep, for its own system and
    architecture.
  - **Cross Toolchain**: with a GNUstep installation made for the target, such
    as a cross compiled sysroot or an MSYS2 MinGW tree; **Toolchain** is the
    folder of its `GNUstep.sh`. The package is made on this computer, so it
    needs `dpkg-deb` or `rpmbuild` (on a Mac: `brew install dpkg`,
    `brew install rpm`). For Debian and Linux
    tarballs on arm64 and amd64, **Make Toolchain…** next to **Toolchain**
    makes one on the Mac, without Docker. It downloads Debian's packages into
    a sysroot and cross-builds GNUstep, libdispatch and GTK4Native into it,
    with its steps in the build log. It makes the toolchain in
    `~/gnustep-toolchains/debian-trixie-<arch>`, the default **Toolchain**.
    Once that is there, a platform whose **Build** is left at its default
    builds with it rather than in a container. The toolchain's
    `bin/debian-depends` gives the package's **Find Dependencies**. See
    `CrossToolchain.md`.
  - **Container**: in a Docker or Podman container, for any architecture the
    container tool runs (`--platform linux/amd64` or `linux/arm64`, emulated
    where it isn't this computer's). The container builds and packages, so
    this computer needs only Docker or Podman. On a Mac:
    `brew install colima docker`, then
    `colima start --vm-type vz --vz-rosetta --cpu 4 --memory 8` (Rosetta
    makes amd64 fast; it needs `softwareupdate --install-rosetta`). Colima
    can't run inside a virtual Mac on M1, which has no nested
    virtualization.
    - The project folder is mounted at its own path, so the compiler's
      messages name the project's files and appear in the build log and the
      issue navigator as a native build's do. Colima shares only the home
      folder by default, so the project must be in it.
    - The **Container Image** is by default ProjectCenter's own,
      `projectcenter-gnustep:debian` (`:fedora` for RPM; `:ubuntu` also
      works). It is made from `GNUstep-image.Dockerfile` in ProjectCenter's
      resources the first time it is missing, once for each architecture
      (`projectcenter-gnustep:debian-arm64`, `...-amd64`), which takes a
      while (tens of minutes natively, far longer emulated without Rosetta). It holds
      GNUstep built with clang and libobjc2 (`ng-gnu-gnu`, as
      `build-gnustep.sh` builds it) in `/opt/gnustep`, installed from its own
      package, `projectcenter-gnustep`. The sources come from the user
      default `GNUstepSources` (`defaults write ProjectCenter GNUstepSources
      ~/Code/gnuStep`, domain `org.gnustep.ProjectCenter` for the Xcode
      build, or the environment variable `GNUSTEP_SOURCES` when
      `archive.sh` is run by hand), including a `gtk4native*` theme there;
      those it lacks are cloned (libs-base and libs-gui from holzgestalt).
      Delete the image (`docker image rm projectcenter-gnustep:debian-arm64`)
      to build it again from newer sources.
    - Another image works too: it needs GNUstep, or a **Container Setup**
      command that installs it on each run (`debian:stable` gets
      `apt-get install gnustep-devel`, whose GNUstep is built with gcc and
      lacks blocks and ARC).
    - With **Include GNUstep** off, Debian and RPM packages built in
      ProjectCenter's image depend on `projectcenter-gnustep` (found by
      **Find Dependencies**), so Archive puts that package next to them;
      install both on the target system. The `.tar.gz` needs the same GNUstep
      there.
    - `Tests/ArchiveDemo` is a small project with a Mac and a Linux target
      (Debian, RPM and Linux, `x86_64 aarch64`, all Container). Archive it,
      then `Tests/ArchiveDemo/check-packages.sh` installs the packages into
      clean `debian:trixie` and `fedora:latest` containers and starts the
      application under Xvfb. Not yet run: the development Mac is a virtual
      machine without nested virtualization, so only the scripts were
      checked, with a stand-in `docker` in `XcodeProjectTests`.
- **Debian** and **RPM** packages install the bundle in the **Install Folder**
  (`/usr/lib/GNUstep/Applications`), a command named after the package in
  `/usr/bin` and a desktop entry with the **Menu Categories** and **Icon**.
  The icon goes in `/usr/share/pixmaps`. Without an **Icon**, it is the
  application's own: the PNG, SVG or XPM file that the bundle's
  `CFBundleIconFile` or `NSIcon` names (the target's app icon set).
  **Find Dependencies** adds the packages of the libraries the application
  links and of GNUstep's back end where `dpkg` knows them (native and container
  builds), or lets `rpmbuild` find them; **Depends** adds more.
- **Include GNUstep** (on by default, for Debian, RPM and Linux tarballs) puts
  the GNUstep the application is built with inside its bundle, in
  `<App>.app/GNUstep`, so the package needs no GNUstep package and each
  application ships its own. It holds:
  - the shared libraries of GNUstep's Libraries folders: base, gui, libobjc2,
    libdispatch and its blocks runtime;
  - the Library folder: the back end bundle, fonts, images, color pickers and
    the libraries' resources. ThemeSDK, headers, makefiles and static
    libraries are left out;
  - the tools the libraries start: `gpbs`, `gdnc`, `gdomap`, `make_services`;
  - a `GNUstep.conf` whose folders are relative to it.

  `GNUstep/run` starts the application with `GNUSTEP_CONFIG_FILE` and
  `LD_LIBRARY_PATH` set to them. The command in `/usr/bin` and the desktop
  entry run it, so start the application with it, not with the executable
  itself. The package then depends only on the system's libraries; an RPM
  neither provides nor requires the bundled ones.
  Turned off, the package depends on `projectcenter-gnustep`.
- **Windows** copies the DLLs the executable needs, found with `objdump` in
  GNUstep's folders and the **Library Folders**. GNUstep's back end bundle and
  its other resources are not included.

The line below the settings says whether this computer can archive the
selected platform, or what is missing (a tool, Docker, a toolchain folder).

**Product → Archive** uses the toolbar scheme's targets marked for Archive.
For a Linux-only archive, select the Linux scheme before choosing Archive.
Use the Deployment tab to configure its distributions and architectures.
Archive leaves out, after asking, the platforms this computer can't archive.
The output appears in the build log, and a platform that fails doesn't stop
the others.
The packages go to a new folder, `build/Archives/<Product> <date time>`,
which is shown when Archive finishes. The scripts Archive runs are written to
`build/Deployment` (`archive.sh` and one for each platform), and can be run
again from a shell.

## GNUstep build and debug integration

On GNUstep, Build and Clean compile the selected Xcode targets directly using
ProjectCenter's bundled PBX compiler. Run resolves the product from the same
scheme and configuration. A project does not need a GNUmakefile, application
build script, or `GNUstep/ProjectCenter.plist`.

The compiler reads source/resource/header membership, target and referenced
subproject dependencies, project/target settings and xcconfig includes, prefix
headers and per-file ARC overrides. It builds C, C++ and Objective-C sources
against the installed GNUstep SDK. Products and compiler caches live under
`build/ProjectCenter/<configuration>` beside the `.xcodeproj`. Clean removes only
the chosen configuration's products. Source project metadata is never rewritten.

The images of asset catalogs are copied into the bundle's `Resources`. The
target's app icon set (`ASSETCATALOG_COMPILER_APPICON_NAME`, **App Icon** in the
General pane) is the application's icon: its largest PNG or SVG of up to 512
pixels goes in as `<name>.png` (`AppIcon.png`), and `NSIcon` in
`Info-gnustep.plist` names it. A non-empty `CFBundleIconFile` still wins, as it
does in GNUstep.

An installed appearance provider can expose an `xcode_sdk` pkg-config variable
for its compiler flags, SDK sources, library replacements and resource adaptation.
GTK-specific adapters remain in GTK4Native. Apple signing phases are skipped with
a diagnostic; arbitrary shell phases, Swift, and unknown external SDK libraries
are rejected rather than silently treated as a successful build.

Existing projects with an explicitly configured `BuildScript` or `Executable` in
`GNUstep/ProjectCenter.plist` retain those overrides. They are optional legacy
integration, not a prerequisite for Xcode project builds. FontTableViewer has no
such sidecar and builds from its original Xcode project and GSFontTools subproject.

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

A project can keep separate macOS and Linux application targets. Declare
`SUPPORTED_PLATFORMS = gnustep` in the Linux target's build configurations and
provide a shared scheme for it. On GNUstep, ProjectCenter defaults to that scheme
when there is exactly one native target; an explicitly saved scheme selection
still takes precedence. Each target's own source and resource phases remain the
build inputs. EditGlyphData uses this arrangement with **EditGlyphData Linux**,
leaving the macOS target's Python wrapper build phase unchanged.
