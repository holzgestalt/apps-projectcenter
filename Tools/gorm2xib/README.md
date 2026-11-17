# gorm2xib

Writes the Interface Builder document (`.xib`) of a Gorm interface (`.gorm`).
The macOS build compiles these XIBs; the `.gorm` files stay the source for the
GNUstep build and are what Gorm edits.

```sh
Tools/gorm2xib/regenerate.sh      # all interfaces of ProjectCenter (macOS)
```

`regenerate.sh` builds `gorm2xib.m` with Xcode's clang and runs it on every
`.gorm` except `Modules/Projects/Application/Resources/Main.gorm` (the template
copied into new GNUstep application projects). Run it after changing a `.gorm`
in Gorm, and commit both files.

The work is done by two Foundation-only classes of ProjectCenter.framework,
which its interface editor uses too:

- `Framework/PCGormArchive` reads `objects.gorm`, a GNUstep `NSArchiver`
  archive, without instantiating anything. Every value keeps its archived type
  tag, width and bytes; objects are split into the fields their non-keyed
  `-initWithCoder:` reads in libs-gui and libs-base. Writing numbers objects,
  classes and selectors in the order it writes them, as NSArchiver does, so an
  unchanged archive is written back byte for byte, and an edited one (new
  strings, changed frames) stays consistent. `XcodeProjectTests` checks this
  for every `.gorm` in the repository.
- `Framework/PCGormXIBWriter` writes the object graph as a XIB 3.0 document
  with autoresizing masks and Gorm's frames. Each object gets the id
  `g<identifier>`, so an edit of the XIB can be made in the archive.

Not converted to XIB (gorm2xib prints a warning):

- Images embedded in a gorm without a name. Set them in code, or add them as
  named resources.
- GNUstep theme images such as `common_ret`. Switch and radio images become
  checkbox and radio button types.
