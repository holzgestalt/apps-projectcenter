"""ProjectCenter's built-in GNUstep compiler for PBX native targets.

All project inputs come from project.pbxproj and its referenced xcconfig/source/
resource files. No source GNUmakefile, sidecar or application build script is read.
The installed appearance provider may supply SDK compatibility hooks.
"""
import argparse
import concurrent.futures
import fcntl
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import re
import shlex
import shutil
import subprocess
import sys
import tempfile


def words(value):
    return list(value) if isinstance(value, list) else shlex.split(str(value or ''))


def output(command):
    return subprocess.check_output(list(map(str, command)), text=True).strip()


def read_plist(path):
    data = path.read_bytes()
    try:
        return plistlib.loads(data)
    except plistlib.InvalidFileException:
        with tempfile.NamedTemporaryFile(suffix='.plist') as converted:
            subprocess.run(['plutil', '-convert', 'xml1', '-o', converted.name, str(path)], check=True)
            return plistlib.loads(Path(converted.name).read_bytes())


def xcconfig(path, active=None):
    active = set() if active is None else active
    if path in active:
        raise ValueError(f'Cyclic xcconfig include: {path}')
    if not path.exists():
        if path.name == 'signing.xcconfig':
            return {}  # Code signing is not part of the GNUstep SDK.
        raise FileNotFoundError(path)
    active.add(path)
    result = {}
    for line in path.read_text().replace('\\\n', '').splitlines():
        line = line.split('//', 1)[0].strip()
        include = re.match(r'#include(\?)?\s+["<](.*?)[">]', line)
        if include:
            child = path.parent / include[2]
            if child.exists() or not include[1]:
                result.update(xcconfig(child, active))
        else:
            setting = re.match(r'([\w]+)\s*(\+?=)\s*(.*?)\s*;?$', line)
            if setting:
                name, op, value = setting.groups()
                previous = ' '.join(words(result.get(name, '')))
                result[name] = (previous + ' ' + value if op == '+=' else value.replace('$(inherited)', previous)).strip()
    active.remove(path)
    return result


class Project:
    def __init__(self, path, configuration):
        self.path = path.resolve()
        self.root = self.path.parent
        data = read_plist(self.path / 'project.pbxproj')
        self.objects = data['objects']
        self.project = self.objects[data['rootObject']]
        self.configuration = configuration
        self.paths = {}
        self.targets = {self.objects[ref]['name']: ref for ref in self.project['targets']}
        def visit(ref, parent):
            obj = self.objects[ref]
            tree = obj.get('sourceTree', '<group>')
            if tree not in ('<group>', 'SOURCE_ROOT', '<absolute>'):
                return
            base = self.root if tree == 'SOURCE_ROOT' else parent
            path = base / obj.get('path', '')
            self.paths[ref] = path
            for child in obj.get('children', []):
                visit(child, path)
        visit(self.project['mainGroup'], self.root)

    def settings(self, ref):
        result = {}
        for owner in (self.project, self.objects[ref]):
            configs = self.objects[owner['buildConfigurationList']]['buildConfigurations']
            config = next((self.objects[c] for c in configs if self.objects[c]['name'] == self.configuration), None)
            if config is None:
                raise ValueError(f'Missing {self.configuration} configuration in {self.path}')
            layer = {}
            if config.get('baseConfigurationReference'):
                layer.update(xcconfig(self.paths[config['baseConfigurationReference']]))
            layer.update(config.get('buildSettings', {}))
            for key, value in layer.items():
                inherited = words(result.get(key, ''))
                result[key] = [v for item in value for v in (inherited if item == '$(inherited)' else [item])] if isinstance(value, list) else str(value).replace('$(inherited)', ' '.join(inherited))
        return result

    def expand(self, value, ref, settings):
        variables = dict(settings, SRCROOT=str(self.root), SOURCE_ROOT=str(self.root), PROJECT_DIR=str(self.root),
                         TARGET_NAME=self.objects[ref]['name'], CONFIGURATION=self.configuration)
        def replace(match):
            key = match[1] or match[2]
            key, _, modifier = key.partition(':')
            result = str(variables.get(key, match[0]))
            return re.sub(r'[^A-Za-z0-9.-]', '-', result) if modifier == 'rfc1034identifier' else result
        for _ in range(16):
            expanded = re.sub(r'\$\(([^)]+)\)|\$\{([^}]+)\}', replace, str(value))
            if expanded == value:
                break
            value = expanded
        return value

    def files(self, ref, kind):
        for phaseid in self.objects[ref].get('buildPhases', []):
            phase = self.objects[phaseid]
            if phase['isa'] != kind:
                continue
            for entryid in phase.get('files', []):
                entry = self.objects[entryid]
                fileid = entry.get('fileRef')
                if fileid is None:
                    raise ValueError('Build rules without a file reference are unsupported')
                obj = self.objects[fileid]
                for child in obj.get('children', []) if obj['isa'] == 'PBXVariantGroup' else [fileid]:
                    yield child, entry.get('settings', {})


class Build:
    def __init__(self, args):
        self.args = args
        self.theme = args.theme or os.environ.get('GNUSTEP_APPLICATION_THEME', 'GTK4Native')
        self.sdk = None
        # A theme that is not installed (as in a plain GNUstep, or Archive's
        # container) leaves the application with GNUstep's own look.
        self.theme_package = 'gnustep-theme-' + self.theme
        try:
            installed = subprocess.run(['pkg-config', '--exists', self.theme_package]).returncode == 0
        except FileNotFoundError:
            installed = False
        if not installed:
            if args.theme or os.environ.get('GNUSTEP_APPLICATION_THEME'):
                print(f'warning: the theme {self.theme} is not installed; building without it', file=sys.stderr)
            self.theme_package = None
        module = output(['pkg-config', '--variable=xcode_sdk', self.theme_package]) if self.theme_package else ''
        if module:
            spec = importlib.util.spec_from_file_location('theme_sdk', module)
            self.sdk = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(self.sdk)
        self.replacements = getattr(self.sdk, 'REPLACED_FRAMEWORKS', {})
        self.projects = {}
        self.ordered = []
        self.visiting = set()
        self.load(args.project)
        self.root = self.projects[args.project.resolve()]
        names = args.target or [self.choose_target()]
        self.build_dir = (args.build_dir or self.root.root / 'build/ProjectCenter' / args.configuration).resolve()
        for name in names:
            self.visit(self.root, self.root.targets[name])
        self.selected = (self.root, self.root.targets[names[0]])
        self.commands = []

    def load(self, path):
        path = path.resolve()
        if path not in self.projects:
            self.projects[path] = Project(path, self.args.configuration)
        return self.projects[path]

    def choose_target(self):
        targets = [name for name, ref in self.root.targets.items() if self.root.objects[ref].get('productType') == 'com.apple.product-type.application']
        native = [name for name in targets if 'gnustep' in words(self.root.settings(self.root.targets[name]).get('SUPPORTED_PLATFORMS', []))
                  or self.root.settings(self.root.targets[name]).get('SDKROOT') in ('linux', 'gnustep')]
        if len(native) == 1:
            return native[0]
        if len(targets) != 1:
            raise ValueError('Select a scheme/target: the project does not have exactly one application target')
        return targets[0]

    def dependency(self, project, fileid):
        file = project.objects[fileid]
        if Path(file.get('path', '')).stem in self.replacements:
            return None
        if file.get('isa') == 'PBXReferenceProxy':
            proxy = project.objects[file['remoteRef']]
            dependency = self.load(project.paths[proxy['containerPortal']])
            target = next((ref for ref in dependency.targets.values() if dependency.objects[ref].get('productReference') == proxy['remoteGlobalIDString']), None)
            if target is None:
                raise ValueError(f'Unresolved subproject product: {file}')
            return dependency, target
        for ref in project.targets.values():
            if project.objects[ref].get('productReference') == fileid:
                return project, ref
        return None

    def visit(self, project, ref):
        key = (project, ref)
        if key in self.ordered:
            return
        if key in self.visiting:
            raise ValueError('Cyclic PBX target dependencies')
        self.visiting.add(key)
        for depid in project.objects[ref].get('dependencies', []):
            dep = project.objects[depid]
            if dep.get('target'):
                self.visit(project, dep['target'])
            elif dep.get('targetProxy'):
                proxy = project.objects[dep['targetProxy']]
                child = self.load(project.paths[proxy['containerPortal']])
                self.visit(child, proxy['remoteGlobalIDString'])
        for fileid, _ in project.files(ref, 'PBXFrameworksBuildPhase'):
            dependency = self.dependency(project, fileid)
            if dependency:
                self.visit(*dependency)
        self.visiting.remove(key)
        self.ordered.append(key)

    def name(self, project, ref):
        settings = project.settings(ref)
        name = project.expand(settings.get('PRODUCT_NAME', project.objects[ref]['name']), ref, settings)
        if not name or name in ('.', '..') or '/' in name or '\\' in name:
            raise ValueError(f'Invalid product name: {name}')
        return name

    def directory(self, project, ref):
        suffix = hashlib.sha256(str(project.path).encode()).hexdigest()[:8]
        return self.build_dir / (self.name(project, ref) + '-' + suffix)

    def executable(self):
        project, ref = self.selected
        name = self.name(project, ref)
        kind = project.objects[ref]['productType']
        if kind == 'com.apple.product-type.application':
            return self.build_dir / (name + '.app') / name
        if kind == 'com.apple.product-type.tool':
            return self.build_dir / name
        return self.directory(project, ref) / ('lib' + name + '.a')

    def describe(self):
        return dict(executable=str(self.executable()), build_directory=str(self.build_dir),
                    targets=[dict(project=str(p.path), target=p.objects[r]['name'],
                                  sources=[str(p.paths[f]) for f, _ in p.files(r, 'PBXSourcesBuildPhase')]) for p, r in self.ordered])

    def prepare_headers(self):
        include = self.build_dir / 'Headers'
        if include.exists():
            shutil.rmtree(include)
        for project, ref in self.ordered:
            namespace = include / self.name(project, ref)
            namespace.mkdir(parents=True, exist_ok=True)
            for fileid, path in project.paths.items():
                if path.suffix != '.h' or not path.is_file():
                    continue
                for dest in (namespace / path.name, include / path.name):
                    if dest.is_symlink() and dest.resolve() == path.resolve():
                        continue
                    if dest.exists() or dest.is_symlink():
                        # Each framework retains its own namespaced headers.
                        if dest.parent == include:
                            continue
                        dest.unlink()
                    dest.symlink_to(path.resolve())
        return include

    def compile_target(self, project, ref, include):
        settings = project.settings(ref)
        directory = self.directory(project, ref)
        directory.mkdir(parents=True, exist_ok=True)
        common = shlex.split(output(['gnustep-config', '--objc-flags']))
        common = [flag for flag in common if flag != '-DDEBUG']
        common += ['-I' + str(include), '-I' + str(include / self.name(project, ref))]
        for value in words(settings.get('HEADER_SEARCH_PATHS', [])):
            path = project.root / project.expand(value, ref, settings)
            if path.exists():
                common += ['-I' + str(path)]
        for value in words(settings.get('GCC_PREPROCESSOR_DEFINITIONS', [])):
            common += ['-D' + project.expand(value, ref, settings)]
        if settings.get('ENABLE_NS_ASSERTIONS') == 'NO':
            common += ['-DNS_BLOCK_ASSERTIONS']
        sdk_flags = self.sdk.compiler_flags() if self.sdk else []
        common += sdk_flags
        common += ['-O' + str(settings.get('GCC_OPTIMIZATION_LEVEL', '0'))]
        entries = [(project.paths[fileid], flags) for fileid, flags in project.files(ref, 'PBXSourcesBuildPhase')]
        if (project, ref) == self.selected and self.sdk:
            entries += [(Path(source), {'COMPILER_FLAGS': '-fobjc-arc'}) for source in self.sdk.SOURCES]
        headers = [p for q in self.projects.values() for p in q.paths.values() if p.suffix in ('.h', '.pch', '.xcconfig') and p.is_file()]
        headers += [Path(__file__)]
        if self.sdk:
            headers += [Path(p) for p in self.sdk.build_inputs()]
        newest_header = max(p.stat().st_mtime_ns for p in headers)
        objects = []
        for source, file_settings in entries:
            if source.suffix not in ('.m', '.mm', '.c', '.cc', '.cpp'):
                raise ValueError(f'Unsupported source language: {source}')
            if not source.is_file():
                raise FileNotFoundError(source)
            obj = directory / (hashlib.sha256(str(source).encode()).hexdigest()[:12] + '-' + source.name + '.o')
            cpp = source.suffix in ('.mm', '.cc', '.cpp')
            command = [os.environ.get('CXX', 'clang++') if cpp else os.environ.get('CC', 'clang'), *common, '-I' + str(source.parent)]
            if cpp:
                command += ['-std=' + settings.get('CLANG_CXX_LANGUAGE_STANDARD', 'gnu++17')]
            if source.suffix in ('.m', '.mm'):
                command += ['-fobjc-arc' if settings.get('CLANG_ENABLE_OBJC_ARC') == 'YES' else '-fno-objc-arc']
                prefix = settings.get('GCC_PREFIX_HEADER')
                if prefix:
                    command += ['-include', str(project.root / project.expand(prefix, ref, settings))]
            command += words(settings.get('OTHER_CFLAGS', ''))
            command += words(file_settings.get('COMPILER_FLAGS', ''))
            command += ['-c', str(source), '-o', str(obj)]
            objects.append(obj)
            self.commands.append((command, obj, max(newest_header, source.stat().st_mtime_ns)))
        return objects

    def compile_one(self, entry):
        command, obj, newest = entry
        signature = obj.with_suffix('.command')
        key = shlex.join(command)
        if obj.exists() and signature.exists() and signature.read_text() == key and obj.stat().st_mtime_ns > newest:
            return
        print('Compile ' + command[command.index('-c') + 1], flush=True)
        subprocess.run(command, check=True)
        signature.write_text(key)

    def resources(self, project, ref, destination):
        for fileid, _ in project.files(ref, 'PBXResourcesBuildPhase'):
            source = project.paths[fileid]
            if source.suffix == '.xcassets':
                # Preserve raster image sets, including the configured app icon.
                for image in source.rglob('*'):
                    if image.suffix.lower() in ('.png', '.jpg', '.jpeg'):
                        shutil.copy2(image, destination / image.name)
                print(f'note: copied raster images from asset catalog: {source}', file=sys.stderr)
                continue
            target = destination / source.name
            if source.parent.suffix == '.lproj':
                target = destination / source.parent.name / source.name
            target.parent.mkdir(parents=True, exist_ok=True)
            if source.is_dir():
                shutil.copytree(source, target, dirs_exist_ok=True)
            else:
                shutil.copy2(source, target)

    def app_icon(self, project, ref, settings, destination):
        """Copies the largest image of the target's app icon set
        (ASSETCATALOG_COMPILER_APPICON_NAME) as <name>.<extension> and
        returns its file name, or None."""
        name = project.expand(settings.get('ASSETCATALOG_COMPILER_APPICON_NAME', ''), ref, settings)
        if not name:
            return None
        for fileid, _ in project.files(ref, 'PBXResourcesBuildPhase'):
            catalog = project.paths[fileid]
            folder = catalog / (name + '.appiconset')
            if catalog.suffix != '.xcassets' or not folder.is_dir():
                continue
            def pixels(entry):
                try:
                    size = float(str(entry.get('size', '0')).split('x')[0])
                    scale = float(str(entry.get('scale', '1x')).rstrip('x'))
                except ValueError:
                    return 0
                return size * scale
            try:
                entries = json.loads((folder / 'Contents.json').read_text()).get('images', [])
            except (OSError, ValueError):
                entries = []
            images = [(pixels(e), folder / e['filename']) for e in entries
                      if e.get('filename') and (folder / e['filename']).is_file()]
            images += [(0, f) for f in sorted(folder.iterdir())
                       if f.suffix.lower() in ('.png', '.svg') and f not in [i for _, i in images]]
            images = [i for i in images if i[1].suffix.lower() in ('.png', '.svg')]
            if not images:
                break
            # Desktops show icons up to 512 pixels; a larger one is only bigger.
            fitting = [i for i in images if i[0] <= 512]
            _, image = max(fitting or images, key=lambda i: i[0])
            icon = name + image.suffix.lower()
            shutil.copy2(image, destination / icon)
            print(f'note: application icon: {image.relative_to(project.root)}', file=sys.stderr)
            return icon
        print(f'warning: the app icon set {name} is not in an asset catalog of the target', file=sys.stderr)
        return None

    def build(self):
        include = self.prepare_headers()
        target_objects = {(p, r): self.compile_target(p, r, include) for p, r in self.ordered}
        with concurrent.futures.ThreadPoolExecutor(max_workers=max(1, int(os.environ.get('JOBS', '4')))) as pool:
            list(pool.map(self.compile_one, self.commands))
        archives = []
        for project, ref in self.ordered:
            if (project, ref) == self.selected:
                continue
            archive = self.directory(project, ref) / ('lib' + self.name(project, ref) + '.a')
            archive_command = ['ar', 'rcs', str(archive), *map(str, target_objects[project, ref])]
            signature = archive.with_suffix('.command')
            key = shlex.join(archive_command)
            if not archive.exists() or not signature.exists() or signature.read_text() != key or any(o.stat().st_mtime_ns > archive.stat().st_mtime_ns for o in target_objects[project, ref]):
                archive.unlink(missing_ok=True)
                subprocess.run(archive_command, check=True)
                signature.write_text(key)
            archives.append(archive)
        project, ref = self.selected
        settings = project.settings(ref)
        executable = self.executable()
        executable.parent.mkdir(parents=True, exist_ok=True)
        resources = executable.parent / 'Resources' if executable.parent.suffix == '.app' else self.build_dir / 'Resources'
        if resources.exists():
            shutil.rmtree(resources)
        resources.mkdir(parents=True)
        for p, r in self.ordered:
            self.resources(p, r, resources)
        if self.sdk:
            self.sdk.prepare_resources(resources)
        icon = self.app_icon(project, ref, settings, resources)
        info = read_plist(project.root / project.expand(settings['INFOPLIST_FILE'], ref, settings)) if settings.get('INFOPLIST_FILE') else {}
        name = self.name(project, ref)
        settings = dict(settings, PRODUCT_NAME=name, EXECUTABLE_NAME=name)
        def expand_info(value):
            if isinstance(value, str):
                return project.expand(value, ref, settings)
            if isinstance(value, dict):
                return {k: expand_info(v) for k, v in value.items()}
            if isinstance(value, list):
                return [expand_info(v) for v in value]
            return value
        info.update({key[len('INFOPLIST_KEY_'):]: value for key, value in settings.items() if key.startswith('INFOPLIST_KEY_')})
        info = expand_info(info)
        info.update(CFBundleExecutable=name, NSExecutable=name, NSPrincipalClass=info.get('NSPrincipalClass', 'NSApplication'))
        if icon and not info.get('NSIcon'):
            # GNUstep's application icon. A CFBundleIconFile that names
            # something else still wins, as it does in GNUstep.
            info['NSIcon'] = icon
        exported = {entry['UTTypeIdentifier']: entry for entry in info.get('UTExportedTypeDeclarations', []) if entry.get('UTTypeIdentifier')}
        for document in info.get('CFBundleDocumentTypes', []):
            # GNUstep dispatches document APIs using CFBundleTypeName, whereas
            # Cocoa uses the UTI declared in LSItemContentTypes.
            types = document.get('LSItemContentTypes', [])
            if types:
                document['CFBundleTypeName'] = types[0]
                tags = exported.get(types[0], {}).get('UTTypeTagSpecification', {})
                extensions = tags.get('public.filename-extension')
                if extensions and not document.get('CFBundleTypeExtensions'):
                    document['CFBundleTypeExtensions'] = extensions if isinstance(extensions, list) else [extensions]
            if not document.get('NSDocumentClass'):
                document.pop('NSDocumentClass', None)
        (resources / 'Info-gnustep.plist').write_bytes(plistlib.dumps(info))
        libs = words(output(['pkg-config', '--libs', self.theme_package])) if self.theme_package else []
        libs += words(output(['gnustep-config', '--gui-libs']))
        if self.sdk:
            libs += self.sdk.link_flags()
        # Native SDK frameworks are supplied by GNUstep; local products are
        # compiled above. Unknown external libraries must not disappear silently.
        for p, r in self.ordered:
            for fileid, _ in p.files(r, 'PBXFrameworksBuildPhase'):
                file = p.objects[fileid]
                stem = Path(file.get('path', '')).stem
                if stem in self.replacements:
                    print(f'note: {stem}: {self.replacements[stem]}', file=sys.stderr)
                elif self.dependency(p, fileid) or stem in ('Cocoa', 'Foundation', 'AppKit'):
                    continue
                else:
                    raise ValueError(f'Unsupported external library: {file.get("path")}')
            for phaseid in p.objects[r].get('buildPhases', []):
                phase = p.objects[phaseid]
                if phase['isa'] == 'PBXShellScriptBuildPhase':
                    script = phase.get('shellScript', '')
                    if 'signing' in script or 'codesign' in script:
                        print('note: Apple code-signing phase is not used by GNUstep', file=sys.stderr)
                    else:
                        raise ValueError('Shell build phases are not supported by the native compiler')
        command = [os.environ.get('CXX', 'clang++'), *map(str, target_objects[self.selected])]
        if archives:
            command += ['-Wl,--whole-archive', *map(str, archives), '-Wl,--no-whole-archive']
        command += ['-o', str(executable), *libs]
        signature = self.build_dir / (name + '.link-command')
        inputs = [*target_objects[self.selected], *archives]
        if self.theme_package:
            inputs += [Path(p) for p in words(output(['pkg-config', '--variable=archives', self.theme_package]))]
        key = shlex.join(command)
        if not executable.exists() or not signature.exists() or signature.read_text() != key or any(p.stat().st_mtime_ns > executable.stat().st_mtime_ns for p in inputs):
            subprocess.run(command, check=True)
            signature.write_text(key)
        print(executable, flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--project', type=Path, required=True)
    parser.add_argument('--target', action='append')
    parser.add_argument('--configuration', default='Debug')
    parser.add_argument('--build-dir', type=Path)
    parser.add_argument('--theme')
    parser.add_argument('--describe', action='store_true')
    parser.add_argument('--action', choices=('build', 'clean'), default='build')
    args = parser.parse_args()
    build = Build(args)
    if args.describe:
        print(json.dumps(build.describe()))
    else:
        build.build_dir.mkdir(parents=True, exist_ok=True)
        # Two IDEs or an IDE and a command-line build may share a product tree.
        with (build.build_dir / '.build.lock').open('a') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            if args.action == 'clean':
                for p, r in build.ordered:
                    shutil.rmtree(build.directory(p, r), ignore_errors=True)
                executable = build.executable()
                if executable.parent.suffix == '.app':
                    shutil.rmtree(executable.parent, ignore_errors=True)
                elif executable.is_file():
                    executable.unlink()
            else:
                build.build()



if __name__ == '__main__':
    try:
        main()
    except (ValueError, KeyError, FileNotFoundError, subprocess.CalledProcessError) as error:
        print(f'error: {error}', file=sys.stderr)
        sys.exit(1)
