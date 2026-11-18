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
- **GNUstep**, for the target ProjectCenter builds: the build script, the
  executable and the theme (see below). These are ProjectCenter's own
  settings, kept in `GNUstep/ProjectCenter.plist`, and can be edited here: a
  path is saved when you press Return or leave the field.

What Xcode's General pane has only for the App Store or for Xcode itself (App
Category, Supported Destinations, Development Assets) is left out.

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

**Theme** chooses the GNUstep theme Run starts the application with: Run
passes `-GSTheme <Name>`, also when it runs the program under gdb. The menu
lists the themes installed as GNUstep finds them, a `<Name>.theme` bundle in
the `Themes` folder of a GNUstep Library directory (for instance
`~/GNUstep/Library/Themes` or `/usr/GNUstep/Local/Library/Themes`), and
GNUstep's built-in theme. **Default** passes no theme, so the user's own
`GSTheme` default applies (`defaults write <App> GSTheme <Name>`). A theme that
is set but not installed is shown as "not installed". The theme only affects
runs on GNUstep; the Cocoa build on macOS doesn't use GNUstep themes.

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

### My Mac (GNUstep)

Where GNUstep is installed on the Mac, the Destination menu also has **My Mac
(GNUstep)**. It builds and runs the project as ProjectCenter does on GNUstep:

- **Finding GNUstep:** ProjectCenter looks for `GNUstep.sh` in
  `GNUSTEP_MAKEFILES` if it is set. Otherwise it asks `gnustep-config`, found on
  the `PATH` or in `/usr/GNUstep/System/Tools`, `/usr/GNUstep/Local/Tools`,
  `/usr/local/bin`, `/opt/homebrew/bin` or `/opt/local/bin`. Otherwise it tries
  the usual makefile folders of a GNUstep, Homebrew or MacPorts install.
  ProjectCenter looks once, when it starts.
- **Build** runs the build tool from the Build preferences (`/usr/bin/make`) on
  the project's GNUmakefile, or its `BuildScript`, with the environment that
  `GNUstep.sh` sets up. The configuration chooses `debug=yes` or `debug=no`.
- **Run** starts the GNUstep build (`Executable`, or `<Target>.app` in the
  project folder) in the same environment, with the project's **Theme**
  (`-GSTheme`).
- The choice is kept per project, like the other destinations.

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
    Theme = GTK4Native;
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
`Theme` is the GNUstep theme Run uses (`-GSTheme`). The project editor's
General pane edits `BuildScript`, `Executable` and `Theme`, and writes the
file sorted, as above; on macOS, a `BuildScript` also replaces `xcodebuild`
for Build.
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
