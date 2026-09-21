from pathlib import Path
import plistlib
objects={}; n=0
def add(isa,**kw):
 global n
 n+=1; key=f'{n:024X}';objects[key]=dict(isa=isa,**kw);return key
files={name:add('PBXFileReference',lastKnownFileType='sourcecode.swift',path=name,sourceTree='<group>') for name in ['Host.swift','Widget.swift','Intent.swift','ProxyState.swift','Bridge.swift','Core.swift']}
app=add('PBXFileReference',explicitFileType='wrapper.application',path='Clash Meta Switch.app',sourceTree='BUILT_PRODUCTS_DIR')
ext=add('PBXFileReference',explicitFileType='wrapper.app-extension',path='MetaSwitch.appex',sourceTree='BUILT_PRODUCTS_DIR')
products=add('PBXGroup',children=[app,ext],name='Products',sourceTree='<group>')
main=add('PBXGroup',children=list(files.values())+[products],sourceTree='<group>')
def configs(settings):
 refs=[add('XCBuildConfiguration',name=name,buildSettings=dict(settings,SWIFT_OPTIMIZATION_LEVEL='-Onone' if name=='Debug' else '-O')) for name in ['Debug','Release']]
 return add('XCConfigurationList',buildConfigurations=refs,defaultConfigurationIsVisible=0,defaultConfigurationName='Debug')
def sources(names):return add('PBXSourcesBuildPhase',buildActionMask=2147483647,files=[add('PBXBuildFile',fileRef=files[name]) for name in names],runOnlyForDeploymentPostprocessing=0)
common=dict(SDKROOT='macosx',MACOSX_DEPLOYMENT_TARGET='14.0',SWIFT_VERSION='5.0',CODE_SIGN_IDENTITY='-',CODE_SIGN_STYLE='Manual',ENABLE_HARDENED_RUNTIME='YES',CODE_SIGN_INJECT_BASE_ENTITLEMENTS='NO',ALWAYS_SEARCH_USER_PATHS='NO',COMBINE_HIDPI_IMAGES='YES',ARCHS='arm64 x86_64')
extsettings=dict(common,PRODUCT_NAME='MetaSwitch',PRODUCT_BUNDLE_IDENTIFIER='local.clash.metaswitch.widget',INFOPLIST_FILE='Widget-Info.plist',CODE_SIGN_ENTITLEMENTS='Widget.entitlements',SKIP_INSTALL='YES',APPLICATION_EXTENSION_API_ONLY='YES',SWIFT_ACTIVE_COMPILATION_CONDITIONS='WIDGET_EXTENSION',LD_RUNPATH_SEARCH_PATHS='$(inherited) @executable_path/../Frameworks @executable_path/../../../../Frameworks')
exttarget=add('PBXNativeTarget',name='MetaSwitch',buildConfigurationList=configs(extsettings),buildPhases=[sources(['Widget.swift','Bridge.swift'])],buildRules=[],dependencies=[],productName='MetaSwitch',productReference=ext,productType='com.apple.product-type.app-extension')
dep=add('PBXTargetDependency',target=exttarget)
embed=add('PBXCopyFilesBuildPhase',buildActionMask=2147483647,dstPath='',dstSubfolderSpec=13,files=[add('PBXBuildFile',fileRef=ext,settings={'ATTRIBUTES':['RemoveHeadersOnCopy']})],name='Embed App Extensions',runOnlyForDeploymentPostprocessing=0)
appsettings=dict(common,PRODUCT_NAME='Clash Meta Switch',PRODUCT_MODULE_NAME='ClashMetaSwitch',PRODUCT_BUNDLE_IDENTIFIER='local.clash.metaswitch',INFOPLIST_FILE='Host-Info.plist',CODE_SIGN_ENTITLEMENTS='Host.entitlements',LD_RUNPATH_SEARCH_PATHS='$(inherited) @executable_path/../Frameworks')
apptarget=add('PBXNativeTarget',name='ClashMetaSwitch',buildConfigurationList=configs(appsettings),buildPhases=[sources(['Host.swift','Intent.swift','ProxyState.swift','Bridge.swift','Core.swift']),embed],buildRules=[],dependencies=[dep],productName='Clash Meta Switch',productReference=app,productType='com.apple.product-type.application')
project=add('PBXProject',attributes={'LastUpgradeCheck':'2600'},buildConfigurationList=configs(common),compatibilityVersion='Xcode 14.0',developmentRegion='zh_CN',hasScannedForEncodings=0,knownRegions=['zh_CN','en','Base'],mainGroup=main,productRefGroup=products,projectDirPath='',projectRoot='',targets=[apptarget,exttarget])
p=Path('ClashMetaSwitch.xcodeproj');p.mkdir(exist_ok=True)
(p/'project.pbxproj').write_bytes(plistlib.dumps(dict(archiveVersion='1',classes={},objectVersion='56',objects=objects,rootObject=project)))
base=dict(CFBundleDevelopmentRegion='zh_CN',CFBundleExecutable='$(EXECUTABLE_NAME)',CFBundleIdentifier='$(PRODUCT_BUNDLE_IDENTIFIER)',CFBundleName='$(PRODUCT_NAME)',CFBundleShortVersionString='1.0',CFBundleVersion='8',LSMinimumSystemVersion='14.0')
Path('Host-Info.plist').write_bytes(plistlib.dumps(dict(base,CFBundlePackageType='APPL',LSUIElement=True,CFBundleURLTypes=[dict(CFBundleURLName='local.clash.metaswitch',CFBundleURLSchemes=['clash-meta-switch'])],NSAppleEventsUsageDescription='仅调用 ClashX Meta 官方命令，按你的操作开启或关闭系统代理。')))
Path('Widget-Info.plist').write_bytes(plistlib.dumps(dict(base,CFBundlePackageType='XPC!',NSExtension={'NSExtensionPointIdentifier':'com.apple.widgetkit-extension'})))
Path('Widget.entitlements').write_bytes(plistlib.dumps({'com.apple.security.app-sandbox':True,'com.apple.security.temporary-exception.files.home-relative-path.read-only':['/Library/Application Support/ClashMetaSwitch/']}))
Path('Host.entitlements').write_bytes(plistlib.dumps({'com.apple.security.automation.apple-events':True}))
