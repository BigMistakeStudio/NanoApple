#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Frédéric Genevey / BigMistakeStudio
# SPDX-License-Identifier: GPL-3.0-only

"""Create the standalone NanoApple Xcode project from its source tree."""

from __future__ import annotations

import hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE_ROOT = ROOT / "NanoApple"
PROJECT = ROOT / "NanoApple.xcodeproj"
APP = "NanoApple"


def oid(*parts: str) -> str:
    return hashlib.sha256("|".join(parts).encode()).hexdigest().upper()[:24]


def main() -> None:
    swift_files = sorted(SOURCE_ROOT.rglob("*.swift"))
    resources = [
        SOURCE_ROOT / "Resources" / "Assets.xcassets",
        SOURCE_ROOT / "Resources" / "Localizable.xcstrings",
        SOURCE_ROOT / "Resources" / "Runtime" / "qwen_runtime.py",
        SOURCE_ROOT / "Resources" / "Runtime" / "prompt_enhancer.py",
        SOURCE_ROOT / "Resources" / "Runtime" / "nsfw_classifier.py",
        SOURCE_ROOT / "Resources" / "Runtime" / "uv",
        SOURCE_ROOT / "Resources" / "Runtime" / "Python",
        SOURCE_ROOT / "Resources" / "GGUF",
        SOURCE_ROOT / "Resources" / "Legal",
    ]

    project_id = oid("project", APP)
    target_id = oid("target", APP)
    product_id = oid("product", APP)
    main_group = oid("group", "main")
    source_group = oid("group", "source")
    product_group = oid("group", "products")
    sources_phase = oid("phase", "sources")
    resources_phase = oid("phase", "resources")
    frameworks_phase = oid("phase", "frameworks")
    project_configs = {name: oid("project-config", name) for name in ("Debug", "Release")}
    target_configs = {name: oid("target-config", name) for name in ("Debug", "Release")}
    project_config_list = oid("project-config-list")
    target_config_list = oid("target-config-list")

    source_entries = []
    for path in swift_files:
        relative = path.relative_to(ROOT).as_posix()
        source_entries.append((oid("file", relative), oid("build", relative), path.name, relative))

    resource_entries = []
    for path in resources:
        relative = path.relative_to(ROOT).as_posix()
        if path.suffix == ".xcassets":
            file_type = "folder.assetcatalog"
        elif path.suffix == ".xcstrings":
            file_type = "text.json.xcstrings"
        elif path.name == "uv":
            file_type = "compiled.mach-o.executable"
        elif path.name in {"Python", "GGUF", "Legal"}:
            file_type = "folder"
        else:
            file_type = "text.script.python"
        resource_entries.append((oid("file", relative), oid("build", relative), path.name, relative, file_type))

    lines: list[str] = []
    add = lines.append
    add("// !$*UTF8*$!")
    add("{")
    add("\tarchiveVersion = 1;")
    add("\tclasses = {};")
    add("\tobjectVersion = 60;")
    add("\tobjects = {")

    add("\n/* Begin PBXBuildFile section */")
    for ref, build, name, _ in source_entries:
        add(f"\t\t{build} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {ref} /* {name} */; }};")
    for ref, build, name, _, _ in resource_entries:
        add(f"\t\t{build} /* {name} in Resources */ = {{isa = PBXBuildFile; fileRef = {ref} /* {name} */; }};")
    add("/* End PBXBuildFile section */")

    add("\n/* Begin PBXFileReference section */")
    for ref, _, name, relative in source_entries:
        add(f'\t\t{ref} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "{relative}"; sourceTree = SOURCE_ROOT; }};')
    for ref, _, name, relative, file_type in resource_entries:
        add(f'\t\t{ref} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = {file_type}; path = "{relative}"; sourceTree = SOURCE_ROOT; }};')
    add(f'\t\t{product_id} /* {APP}.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = "{APP}.app"; sourceTree = BUILT_PRODUCTS_DIR; }};')
    add("/* End PBXFileReference section */")

    add("\n/* Begin PBXFrameworksBuildPhase section */")
    add(f"\t\t{frameworks_phase} /* Frameworks */ = {{isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0; }};")
    add("/* End PBXFrameworksBuildPhase section */")

    add("\n/* Begin PBXGroup section */")
    add(f"\t\t{main_group} = {{isa = PBXGroup; children = ({source_group} /* {APP} */, {product_group} /* Products */,); sourceTree = \"<group>\"; }};")
    add(f"\t\t{source_group} /* {APP} */ = {{")
    add("\t\t\tisa = PBXGroup;")
    add("\t\t\tchildren = (")
    for ref, _, name, _ in source_entries:
        add(f"\t\t\t\t{ref} /* {name} */,")
    for ref, _, name, _, _ in resource_entries:
        add(f"\t\t\t\t{ref} /* {name} */,")
    add("\t\t\t);")
    add(f"\t\t\tname = {APP};")
    add("\t\t\tsourceTree = \"<group>\";")
    add("\t\t};")
    add(f"\t\t{product_group} /* Products */ = {{isa = PBXGroup; children = ({product_id} /* {APP}.app */,); name = Products; sourceTree = \"<group>\"; }};")
    add("/* End PBXGroup section */")

    add("\n/* Begin PBXNativeTarget section */")
    add(f"\t\t{target_id} /* {APP} */ = {{")
    add("\t\t\tisa = PBXNativeTarget;")
    add(f"\t\t\tbuildConfigurationList = {target_config_list};")
    add(f"\t\t\tbuildPhases = ({sources_phase}, {frameworks_phase}, {resources_phase},);")
    add("\t\t\tbuildRules = (); dependencies = ();")
    add(f"\t\t\tname = {APP}; productName = {APP}; productReference = {product_id};")
    add("\t\t\tproductType = \"com.apple.product-type.application\";")
    add("\t\t};")
    add("/* End PBXNativeTarget section */")

    add("\n/* Begin PBXProject section */")
    add(f"\t\t{project_id} /* Project object */ = {{")
    add("\t\t\tisa = PBXProject;")
    add(f"\t\t\tattributes = {{BuildIndependentTargetsInParallel = 1; LastSwiftUpdateCheck = 2700; LastUpgradeCheck = 2700; TargetAttributes = {{{target_id} = {{CreatedOnToolsVersion = 27.0;}};}};}};")
    add(f"\t\t\tbuildConfigurationList = {project_config_list}; compatibilityVersion = \"Xcode 15.0\";")
    add("\t\t\tdevelopmentRegion = fr; hasScannedForEncodings = 0; knownRegions = (fr, en, Base);")
    add(f"\t\t\tmainGroup = {main_group}; productRefGroup = {product_group}; projectDirPath = \"\"; projectRoot = \"\"; targets = ({target_id},);")
    add("\t\t};")
    add("/* End PBXProject section */")

    add("\n/* Begin PBXResourcesBuildPhase section */")
    add(f"\t\t{resources_phase} /* Resources */ = {{isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = (")
    for _, build, name, _, _ in resource_entries:
        add(f"\t\t\t{build} /* {name} in Resources */,")
    add("\t\t); runOnlyForDeploymentPostprocessing = 0; };")
    add("/* End PBXResourcesBuildPhase section */")

    add("\n/* Begin PBXSourcesBuildPhase section */")
    add(f"\t\t{sources_phase} /* Sources */ = {{isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (")
    for _, build, name, _ in source_entries:
        add(f"\t\t\t{build} /* {name} in Sources */,")
    add("\t\t); runOnlyForDeploymentPostprocessing = 0; };")
    add("/* End PBXSourcesBuildPhase section */")

    add("\n/* Begin XCBuildConfiguration section */")
    for name, config_id in project_configs.items():
        debug = name == "Debug"
        add(f"\t\t{config_id} /* {name} */ = {{isa = XCBuildConfiguration; buildSettings = {{")
        add("\t\t\tALWAYS_SEARCH_USER_PATHS = NO; CLANG_ENABLE_MODULES = YES; CLANG_ENABLE_OBJC_ARC = YES;")
        add(f"\t\t\tDEBUG_INFORMATION_FORMAT = {'dwarf' if debug else '\"dwarf-with-dsym\"'}; MACOSX_DEPLOYMENT_TARGET = 14.0; SDKROOT = macosx;")
        add(f"\t\t\tSWIFT_OPTIMIZATION_LEVEL = {'\"-Onone\"' if debug else '\"-O\"'};")
        if debug:
            add("\t\t\tENABLE_TESTABILITY = YES; SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;")
        else:
            add("\t\t\tSWIFT_COMPILATION_MODE = wholemodule;")
        add(f"\t\t}}; name = {name}; }};")

    for name, config_id in target_configs.items():
        add(f"\t\t{config_id} /* {name} */ = {{isa = XCBuildConfiguration; buildSettings = {{")
        add("\t\t\tARCHS = arm64;")
        add("\t\t\tASSETCATALOG_COMPILER_ACCENT_COLOR_NAME = AccentColor; ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;")
        add("\t\t\tCODE_SIGN_STYLE = Automatic;")
        add("\t\t\tCURRENT_PROJECT_VERSION = 1; DEVELOPMENT_TEAM = FR87VAA3FS; ENABLE_APP_SANDBOX = NO; ENABLE_HARDENED_RUNTIME = YES;")
        add("\t\t\tGENERATE_INFOPLIST_FILE = NO; INFOPLIST_FILE = NanoApple/Resources/Info.plist;")
        add("\t\t\tLD_RUNPATH_SEARCH_PATHS = \"$(inherited) @executable_path/../Frameworks\"; MARKETING_VERSION = 0.1.0;")
        add("\t\t\tPRODUCT_BUNDLE_IDENTIFIER = ch.genevey.NanoApple; PRODUCT_NAME = NanoApple;")
        add("\t\t\tSUPPORTED_PLATFORMS = macosx; SWIFT_EMIT_LOC_STRINGS = YES; SWIFT_VERSION = 6.0;")
        add(f"\t\t}}; name = {name}; }};")
    add("/* End XCBuildConfiguration section */")

    add("\n/* Begin XCConfigurationList section */")
    add(f"\t\t{project_config_list} = {{isa = XCConfigurationList; buildConfigurations = ({project_configs['Debug']}, {project_configs['Release']},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;}};")
    add(f"\t\t{target_config_list} = {{isa = XCConfigurationList; buildConfigurations = ({target_configs['Debug']}, {target_configs['Release']},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;}};")
    add("/* End XCConfigurationList section */")

    add("\t};")
    add(f"\trootObject = {project_id};")
    add("}")

    PROJECT.mkdir(parents=True, exist_ok=True)
    (PROJECT / "project.pbxproj").write_text("\n".join(lines) + "\n")

    scheme_dir = PROJECT / "xcshareddata" / "xcschemes"
    scheme_dir.mkdir(parents=True, exist_ok=True)
    scheme = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2700" version="1.7">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES">
    <BuildActionEntries>
      <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">
        <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target_id}" BuildableName="NanoApple.app" BlueprintName="NanoApple" ReferencedContainer="container:NanoApple.xcodeproj"/>
      </BuildActionEntry>
    </BuildActionEntries>
  </BuildAction>
  <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"/>
  <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES">
    <BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target_id}" BuildableName="NanoApple.app" BlueprintName="NanoApple" ReferencedContainer="container:NanoApple.xcodeproj"/></BuildableProductRunnable>
  </LaunchAction>
  <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target_id}" BuildableName="NanoApple.app" BlueprintName="NanoApple" ReferencedContainer="container:NanoApple.xcodeproj"/></BuildableProductRunnable></ProfileAction>
  <AnalyzeAction buildConfiguration="Debug"/>
  <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
'''
    (scheme_dir / "NanoApple.xcscheme").write_text(scheme)


if __name__ == "__main__":
    main()
