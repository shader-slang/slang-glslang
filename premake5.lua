-- premake5.lua

-- This file describes the build configuration for Slang GLSLANG libray so
-- that premake can generate platform-specific build files
-- using Premake 5 (https://premake.github.io/).

local modulePath = "external/slang-binaries/lua-modules/?.lua"
--local modulePath = "../slang-binaries-jsmall-nvidia/lua-modules/?.lua"

package.path = package.path .. ";" .. modulePath

-- Load the slack package manager module
slangPack = require("slang-pack")
slangUtil = require("slang-util")

-- Load the dependencies from the json file

deps = slangPack.loadDependencies("deps/target-deps.json")

-- Determine the target info

targetInfo = slangUtil.getTargetInfo()

--
-- Update the dependencies for the target
--

deps:update(targetInfo.name)

-- This is needed for gcc, for the 'fileno' functions on cygwin
-- _GNU_SOURCE makes realpath available in gcc
if targetInfo.targetDetail == "cygwin" then
    buildoptions { "-D_POSIX_SOURCE" }
    filter { "toolset:gcc*" }
        buildoptions { "-D_GNU_SOURCE" }
end

workspace "slang-glslang"
    -- We will support debug/release configuration and x86/x64 builds.
    configurations { "Debug", "Release" }
    platforms { "x86", "x64", "aarch64"}
    
    if os.target() == "linux" then
        platforms {"aarch64" }
    end
    
    -- 
    -- Make slang-glslang the startup project.
    --
    -- https://premake.github.io/docs/startproject
    startproject "slang-glslang"
    
    -- The output binary directory will be derived from the OS
    -- and configuration options, e.g. `bin/windows-x64/debug/`
    targetdir("bin/" .. targetInfo.tokenName .. "/%{cfg.buildcfg:lower()}")

    -- C++11 
    cppdialect "C++11"
    
    -- Exceptions have to be turned off for linking against LLVM
    --exceptionhandling("Off")
    --rtti("Off")
    
    -- Our `x64` platform should (obviously) target the x64
     -- architecture and similarly for x86.
     filter { "platforms:x64" }
         architecture "x64"
     filter { "platforms:x86" }
         architecture "x86"
     filter { "platforms:aarch64"}
         architecture "ARM"
         editandcontinue "Off"
    
    -- Statically link to the C/C++ runtime rather than create a DLL dependency.
    staticruntime "On"
    
    -- Once we've set up the common settings, we will make some tweaks
    -- that only apply in a subset of cases. Each call to `filter()`
    -- changes the "active" filter for subsequent commands. In
    -- effect, those commands iwll be ignored when the conditions of
    -- the filter aren't satisfied.

    filter { "toolset:clang or gcc*" }  
        buildoptions { "-fvisibility=hidden" } 
        -- Warnings
        buildoptions { "-Wno-unused-parameter", "-Wno-type-limits", "-Wno-sign-compare", "-Wno-unused-variable", "-Wno-reorder", "-Wno-switch", "-Wno-return-type", "-Wno-unused-local-typedefs", "-Wno-parentheses", "-Wno-ignored-optimization-argument", "-Wno-unknown-warning-option", "-Wno-class-memaccess", "-Wno-error", "-Wno-error=comment"} 
        
    filter { "toolset:gcc*"}
        buildoptions { "-Wno-unused-but-set-variable", "-Wno-implicit-fallthrough"  }
        
    filter { "toolset:clang" }
        buildoptions { "-Wno-deprecated-register", "-Wno-tautological-compare", "-Wno-missing-braces", "-Wno-undefined-var-template", "-Wno-unused-function", "-Wno-return-std-move"}
        
    -- When compiling the debug configuration, we want to turn
    -- optimization off, make sure debug symbols are output,
    -- and add the same preprocessor definition that VS
    -- would add by default.
    filter { "configurations:debug" }
        optimize "Off"
        symbols "On"
        defines { "_DEBUG" }
    
    -- For the release configuration we will turn optimizations on
    -- (we do not yet micro-manage the optimization settings)
    -- and set the preprocessor definition that VS would add by default.
    filter { "configurations:release" }
        optimize "On"
        defines { "NDEBUG" }
            
    filter { "system:linux" }
        buildoptions { "-fno-semantic-interposition", "-ffunction-sections", "-fdata-sections" }
        -- z is for zlib support
        -- tinfo is for terminal info
        links { "pthread", "stdc++", "dl", "rt"}
        linkoptions{  "-Wl,-rpath,'$$ORIGIN',--no-as-needed,--no-undefined,--start-group" }
                         
--
-- We are now going to start defining the projects, where
-- each project builds some binary artifact (an executable,
-- library, etc.).
--
-- All of our projects follow a common structure, so rather
-- than reiterate a bunch of build settings, we define
-- some subroutines that make the configuration as concise
-- as possible.
--
-- First, we will define a helper routine for adding all
-- the relevant files from a given directory path:
--
-- Note that this does not work recursively 
-- so projects that spread their source over multiple
-- directories will need to take more steps.
function addSourceDir(path)
    files
    {
        path .. "/*.cpp",       -- C++ source files
        path .. "/*.h",         -- Header files
        path .. "/*.hpp",       -- C++ style headers (for glslang)
        path .. "/*.natvis",    -- Visual Studio debugger visualization files
    }
end

--
-- Next we will define a helper routine that all of our
-- projects will bottleneck through. Here `name` is
-- the name for the project (and the base name for
-- whatever output file it produces), while `sourceDir`
-- is the directory that holds the source.
--
-- E.g., for the `slang-llvm` project, the source code
-- is nested in `source/`, so we'd (indirectly) call:
--
--      baseroject("slang-llvm", "source/slang-llvm")
--
-- NOTE! This function will add any source from the sourceDir, *if* it's specified. 
-- Pass nil if adding files is not wanted.
function baseProject(name, sourceDir)

    -- Start a new project in premake. This switches
    -- the "current" project over to the newly created
    -- one, so that subsequent commands affect this project.
    --
    project(name)

    -- We need every project to have a stable UUID for
    -- output formats (like Visual Studio and XCode projects)
    -- that use UUIDs rather than names to uniquely identify
    -- projects. If we don't have a stable UUID, then the
    -- output files might have spurious diffs whenever we
    -- re-run premake generation.
    
    if sourceDir then
        uuid(os.uuid(name .. '|' .. sourceDir))
    else
        -- If we don't have a sourceDir, the name will have to be enough
        uuid(os.uuid(name))
    end

    -- Location could do with a better name than 'other' - but it seems as if %{cfg.buildcfg:lower()} and similar variables
    -- is not available for location to expand. 
    location("build/" .. slangUtil.getBuildLocationName(targetInfo) .. "/" .. name)

    -- The intermediate ("object") directory will use a similar
    -- naming scheme to the output directory, but will also use
    -- the project name to avoid cases where multiple projects
    -- have source files with the same name.
    --
    objdir("intermediate/" .. targetInfo.tokenName .. "/%{cfg.buildcfg:lower()}/%{prj.name}")
    
    -- All of our projects are written in C++.
    --
    language "C++"

    -- By default, Premake generates VS project files that
    -- reflect the directory structure of the source code.
    -- While this is nice in principle, it creates messy
    -- results in practice for our projects.
    --
    -- Instead, we will use the `vpaths` feature to imitate
    -- the default VS behavior of grouping files into
    -- virtual subdirectories (VS calls them "filters") for
    -- header and source files respectively.
    --
    -- Note: We are setting `vpaths` using a list of key/value
    -- tables instead of just a key/value table, since this
    -- appears to be an (undocumented) way to fix the order
    -- in which the filters are tested. Otherwise we have
    -- issues where premake will nondeterministically decide
    -- the check something against the `**.cpp` filter first,
    -- and decide that a `foo.cpp.h` file should go into
    -- the `"Source Files"` vpath. That behavior seems buggy,
    -- but at least we appear to have a workaround.
    --
    vpaths {
       { ["Header Files"] = { "**.h", "**.hpp"} },
       { ["Source Files"] = { "**.cpp", "**.slang", "**.natvis" } },
    }
    
    --
    -- Add the files in the sourceDir
    -- NOTE! This doesn't recursively add files in subdirectories
    --
    
    if not not sourceDir then
        addSourceDir(sourceDir)
    end
end


-- We can now use the `baseProject()` subroutine to
-- define helpers for the different categories of project
-- in our source tree.
--
-- For example, the Slang project has several tools that
-- are used during building/testing, but don't need to
-- be distributed. These always have their source code in
-- `tools/<project-name>/`.
--
function tool(name)
    -- We use the `group` command here to specify that the
    -- next project we create shold be placed into a group
    -- named "tools" in a generated IDE solution/workspace.
    --
    -- This is used in the generated Visual Studio solution
    -- to group all the tools projects together in a logical
    -- sub-directory of the solution.
    --
    group "tools"

    -- Now we invoke our shared project configuration logic,
    -- specifying that the project lives under the `tools/` path.
    --
    baseProject(name, "tools/" .. name)
    
    -- Finally, we set the project "kind" to produce a console
    -- application. This is a reasonable default for tools,
    -- and it can be overriden because Premake is stateful,
    -- and a subsequent call to `kind()` would overwrite this
    -- default.
    --
    kind "ConsoleApp"
end

-- "Standard" projects will be those that go to make the binary
-- packages the shared libraries and executables.
--
function standardProject(name, sourceDir)
    -- Because Premake is stateful, any `group()` call by another
    -- project would still be in effect when we create a project
    -- here (e.g., if somebody had called `tool()` before
    -- `standardProject()`), so we are careful here to set the
    -- group to an emptry string, which Premake treats as "no group."
    --
    group ""

    baseProject(name, sourceDir)
end

-- Finally we have the example programs that show how to use Slang.
--
function example(name)
    -- Example programs go into an "example" group
    group "examples"

    -- They have their source code under `examples/<project-name>/`
    baseProject(name, "examples/" .. name)

    -- Set up working directory to be the source directory
    debugdir("examples/" .. name)

    -- By default, all of our examples are console applications. 
    kind "ConsoleApp"
    
    -- The examples also need to link against the core slang library.
    links { "core"  }
end

 standardProject("slang-spirv-tools", nil)
     uuid "C36F6185-49B3-467E-8388-D0E9BF5F7BB8"
     kind "StaticLib"
     pic "On"
 
     includedirs 
     { 
        "external/spirv-tools", 
        "external/spirv-tools/include", 
        "external/spirv-headers/include",  
        -- Currently generated files are part of the slang project
        "external/slang/external/spirv-tools-generated"
     }
 
     addSourceDir("external/spirv-tools/source")
     addSourceDir("external/spirv-tools/source/opt")
     addSourceDir("external/spirv-tools/source/util")
     addSourceDir("external/spirv-tools/source/val")
 
     filter { "system:linux or macosx" }
         links { "dl"}
 --
 -- The single most complicated part of our build is our custom version of glslang.
 -- Is not really set up to produce a shared library with a usable API, so we have
 -- our own custom shim API around it to invoke GLSL->SPIRV compilation.
 --
 -- Glslang normally relies on a CMake-based build process, and its code is spread
 -- across multiple directories with implicit dependencies on certain command-line
 -- definitions.
 --
 -- The following is a tailored build of glslang that pulls in the pieces we care
 -- about whle trying to leave out the rest:
 --
 standardProject("slang-glslang", "external/slang/source/slang-glslang")
     uuid "C495878A-832C-485B-B347-0998A90CC936"
     kind "SharedLib"
     pic "On"
 
     includedirs 
     { 
        "external/glslang", 
        "external/spirv-tools", "external/spirv-tools/include", 
        "external/spirv-headers/include",  
        -- Currently the generted headers are held in the slang subproject
        "external/slang/external/spirv-tools-generated", 
        "external/slang/external/glslang-generated" 
     }
 
     defines
     {
         -- `ENABLE_OPT` must be defined (to either zero or one) for glslang to compile at all
         "ENABLE_OPT=1",
 
         -- We want to build a version of glslang that supports every feature possible,
         -- so we will enable all of the supported vendor-specific extensions so
         -- that they can be used in Slang-generated GLSL code when required.
         --
         "AMD_EXTENSIONS",
         "NV_EXTENSIONS",
     }
 
     -- We will add source code from every directory that is required to get a
     -- minimal GLSL->SPIR-V compilation path working.
     addSourceDir("external/glslang/glslang/GenericCodeGen")
     addSourceDir("external/glslang/glslang/MachineIndependent")
     addSourceDir("external/glslang/glslang/MachineIndependent/preprocessor")
     addSourceDir("external/glslang/OGLCompilersDLL")
     addSourceDir("external/glslang/SPIRV")
     addSourceDir("external/glslang/StandAlone")
 
     -- Unfortunately, blindly adding files like that also pulled in a declaration
     -- of a main entry point that we do *not* want, so we will specifically
     -- exclude that file from our build.
     removefiles { "external/glslang/StandAlone/StandAlone.cpp" }
 
     -- Glslang includes some platform-specific code around DLL setup/teardown
     -- and handling of thread-local storage for its multi-threaded mode. We
     -- don't really care about *any* of that, but we can't remove it from the
     -- build so we need to include the appropriate platform-specific sources.
 
     links { "slang-spirv-tools" }
 
     filter { "system:windows" }
         -- On Windows we need to add the platform-specific sources and then
         -- remove the `main.cpp` file since it tries to define a `DllMain`
         -- and we don't want the default glslang one.
         addSourceDir( "external/glslang/glslang/OSDependent/Windows")
         removefiles { "external/glslang/glslang/OSDependent/Windows/main.cpp" }
 
     filter { "system:linux or macosx" }
         addSourceDir( "external/glslang/glslang/OSDependent/Unix")
         links { "dl" }
 