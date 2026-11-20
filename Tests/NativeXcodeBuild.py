"""Exercise the built-in compiler using only PBX metadata and referenced inputs."""
from pathlib import Path
import json
import plistlib
import subprocess
import sys
import tempfile

engine = Path(sys.argv[1]).resolve()
with tempfile.TemporaryDirectory(prefix='pc-native-pbx-') as temporary:
    root = Path(temporary)
    project = root / 'Fixture.xcodeproj'
    project.mkdir()
    library = root / 'Dependency/Library.xcodeproj'
    library.mkdir(parents=True)
    (root / 'GNUmakefile').write_text('$(error Source GNUmakefile must never be read)\n')
    (root / 'Excluded.m').write_text('#error Non-member source compiled\n')
    (root / 'Message.txt').write_text('original')
    (root / 'Info.plist').write_bytes(plistlib.dumps({
        'CFBundleDocumentTypes': [{'CFBundleTypeName':'Fixture Text', 'LSItemContentTypes':['org.fixture.text'], 'NSDocumentClass':'FixtureDocument'}],
        'UTExportedTypeDeclarations': [{'UTTypeIdentifier':'org.fixture.text', 'UTTypeTagSpecification':{'public.filename-extension':'fixture'}}]}))
    (root / 'Settings.xcconfig').write_text('FIXTURE = 7\nGCC_PREPROCESSOR_DEFINITIONS = FIXTURE=$(FIXTURE)\nCLANG_ENABLE_OBJC_ARC = YES\n')
    (root / 'Main.m').write_text('''#import <Foundation/Foundation.h>
#if FIXTURE != 7
#error XCConfig settings were not applied
#endif
#if !__has_feature(objc_arc)
#error Target ARC setting ignored
#endif
extern NSString *Message(void);
extern int DependencyValue(void);
int main(void) { @autoreleasepool {
 NSString *path=[[NSBundle mainBundle] pathForResource:@"Message" ofType:@"txt"];
 NSString *text=[NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL];
 if(![text isEqual:Message()] || DependencyValue()!=42) return 1;
 puts(text.UTF8String);
} return 0; }
''')
    for name, value in [('Original', 'original'), ('Added', 'added')]:
        (root / (name + '.m')).write_text('#import <Foundation/Foundation.h>\n#if __has_feature(objc_arc)\n#error Per-file ARC override ignored\n#endif\nNSString *Message(void) { return @"' + value + '"; }\n')
    (library.parent / 'Dependency.c').write_text('int DependencyValue(void) { return 42; }\n')
    def config(name):
        return {'isa': 'XCBuildConfiguration', 'name': name, 'baseConfigurationReference': 'SETTINGS', 'buildSettings': {'PRODUCT_NAME': '$(TARGET_NAME)', 'SUPPORTED_PLATFORMS': 'gnustep', 'INFOPLIST_KEY_CFBundleIconFile': 'icon.png', 'INFOPLIST_FILE': 'Info.plist'}}
    objects = {
      'PROJECT': {'isa':'PBXProject','mainGroup':'GROUP','targets':['APP'],'buildConfigurationList':'CONFIGS'},
      'GROUP': {'isa':'PBXGroup','children':['MAIN','ORIGINAL','ADDED','EXCLUDED','RESOURCE','SUBPROJECT','SETTINGS']},
      'APP': {'isa':'PBXNativeTarget','name':'Fixture','productType':'com.apple.product-type.application','productReference':'PRODUCT','buildConfigurationList':'CONFIGS','buildPhases':['SOURCES','RESOURCES','LINK']},
      'PRODUCT': {'isa':'PBXFileReference','path':'Fixture.app','sourceTree':'BUILT_PRODUCTS_DIR'},
      'CONFIGS': {'isa':'XCConfigurationList','buildConfigurations':['DEBUG','RELEASE']},
      'DEBUG': config('Debug'), 'RELEASE': config('Release'),
      'SOURCES': {'isa':'PBXSourcesBuildPhase','files':['MAIN_BUILD','ORIGINAL_BUILD']},
      'RESOURCES': {'isa':'PBXResourcesBuildPhase','files':['RESOURCE_BUILD']},
      'LINK': {'isa':'PBXFrameworksBuildPhase','files':['LIB_BUILD']},
      'LIB_BUILD': {'isa':'PBXBuildFile','fileRef':'LIB_PROXY'},
      'LIB_PROXY': {'isa':'PBXReferenceProxy','path':'Library.framework','remoteRef':'PROXY','sourceTree':'BUILT_PRODUCTS_DIR'},
      'PROXY': {'isa':'PBXContainerItemProxy','containerPortal':'SUBPROJECT','remoteGlobalIDString':'LIB_PRODUCT'},
    }
    for key, name in [('MAIN','Main.m'),('ORIGINAL','Original.m'),('ADDED','Added.m'),('EXCLUDED','Excluded.m'),('RESOURCE','Message.txt'),('SETTINGS','Settings.xcconfig'),('SUBPROJECT','Dependency/Library.xcodeproj')]:
        objects[key] = {'isa':'PBXFileReference','path':name,'sourceTree':'<group>'}
        objects[key+'_BUILD'] = {'isa':'PBXBuildFile','fileRef':key,'settings':{'COMPILER_FLAGS':'-fno-objc-arc'} if key in ('ORIGINAL','ADDED') else {}}
    dep = {
      'PROJECT': {'isa':'PBXProject','mainGroup':'GROUP','targets':['LIB'],'buildConfigurationList':'CONFIGS'},
      'GROUP': {'isa':'PBXGroup','children':['SOURCE']},
      'LIB': {'isa':'PBXNativeTarget','name':'Library','productType':'com.apple.product-type.framework','productReference':'LIB_PRODUCT','buildConfigurationList':'CONFIGS','buildPhases':['SOURCES']},
      'LIB_PRODUCT': {'isa':'PBXFileReference','path':'Library.framework','sourceTree':'BUILT_PRODUCTS_DIR'},
      'SOURCE': {'isa':'PBXFileReference','path':'Dependency.c','sourceTree':'<group>'},
      'SOURCE_BUILD': {'isa':'PBXBuildFile','fileRef':'SOURCE'},
      'SOURCES': {'isa':'PBXSourcesBuildPhase','files':['SOURCE_BUILD']},
      'CONFIGS': {'isa':'XCConfigurationList','buildConfigurations':['DEBUG','RELEASE']},
      'DEBUG': {'isa':'XCBuildConfiguration','name':'Debug','buildSettings':{}},
      'RELEASE': {'isa':'XCBuildConfiguration','name':'Release','buildSettings':{}},
    }
    def save():
        (project/'project.pbxproj').write_bytes(plistlib.dumps({'rootObject':'PROJECT','objects':objects}))
        (library/'project.pbxproj').write_bytes(plistlib.dumps({'rootObject':'PROJECT','objects':dep}))
    # A separate macOS application target must not make GNUstep ambiguous.
    objects['PROJECT']['targets'].append('MAC_APP')
    objects['MAC_APP'] = dict(objects['APP'], name='MacFixture', buildConfigurationList='MAC_CONFIGS', buildPhases=['MAC_SOURCES'])
    objects['MAC_CONFIGS'] = {'isa':'XCConfigurationList','buildConfigurations':['MAC_DEBUG','MAC_RELEASE']}
    for name in ('DEBUG','RELEASE'):
        objects['MAC_'+name] = {'isa':'XCBuildConfiguration','name':name.title(),'buildSettings':{'SUPPORTED_PLATFORMS':'macosx'}}
    objects['MAC_SOURCES'] = {'isa':'PBXSourcesBuildPhase','files':['EXCLUDED_BUILD']}
    (root/'Images.xcassets/AppIcon.appiconset').mkdir(parents=True)
    (root/'Images.xcassets/AppIcon.appiconset/icon.png').write_bytes(b'fixture-raster-resource')
    objects['GROUP']['children'].append('ASSETS')
    objects['ASSETS'] = {'isa':'PBXFileReference','path':'Images.xcassets','sourceTree':'<group>'}
    objects['ASSETS_BUILD'] = {'isa':'PBXBuildFile','fileRef':'ASSETS'}
    objects['RESOURCES']['files'].append('ASSETS_BUILD')
    save()
    command=[sys.executable,str(engine),'--project',str(project),'--theme','Default']
    plan=json.loads(subprocess.check_output([*command,'--describe'],text=True))
    assert [t['target'] for t in plan['targets']]==['Library','Fixture']
    executable=Path(plan['executable'])
    def build(extra=()):
        result=subprocess.run([*command,*extra],stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True)
        if result.returncode: raise AssertionError(result.stdout)
    build()
    assert subprocess.check_output([executable],text=True).strip()=='original'
    resources = executable.parent/'Resources'
    assert (resources/'icon.png').read_bytes() == b'fixture-raster-resource'
    info = plistlib.loads((resources/'Info-gnustep.plist').read_bytes())
    assert info['CFBundleIconFile']=='icon.png'
    assert info['CFBundleDocumentTypes'][0]['CFBundleTypeName']=='org.fixture.text'
    assert info['CFBundleDocumentTypes'][0]['CFBundleTypeExtensions']==['fixture']
    before=executable.stat().st_mtime_ns
    concurrent=[subprocess.Popen(command,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True) for _ in range(2)]
    for process in concurrent:
        text,_=process.communicate()
        assert process.returncode==0,text
    build()
    assert before==executable.stat().st_mtime_ns,'Unchanged project relinked'
    objects['SOURCES']['files']=['MAIN_BUILD','ADDED_BUILD']
    (root/'Message.txt').write_text('added')
    save(); build()
    assert subprocess.check_output([executable],text=True).strip()=='added'
    build(['--configuration','Release'])
    release=Path(json.loads(subprocess.check_output([*command,'--configuration','Release','--describe'],text=True))['executable'])
    assert release!=executable and release.exists()
    build(['--action','clean'])
    assert not executable.exists() and release.exists(),'Clean affected another configuration'
    assert not (root/'GNUstep/ProjectCenter.plist').exists()
print('PASS built-in PBX compiler: native target selection, raster assets, bundle settings, source membership, external project product, xcconfig, ARC overrides, resources, concurrent/incremental build, configuration, clean; no makefile/script/sidecar required')
