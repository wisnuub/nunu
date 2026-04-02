cmake_minimum_required(VERSION 3.22)
project(AVM VERSION 0.1.0 LANGUAGES C CXX OBJCXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

# ── Platform detection ──────────────────────────────────────────────────────
if(UNIX AND NOT APPLE)
    set(AVM_PLATFORM_LINUX   TRUE)
elseif(WIN32)
    set(AVM_PLATFORM_WINDOWS TRUE)
elseif(APPLE)
    set(AVM_PLATFORM_MACOS   TRUE)
    # Detect Apple Silicon vs Intel
    execute_process(COMMAND uname -m OUTPUT_VARIABLE HOST_ARCH OUTPUT_STRIP_TRAILING_WHITESPACE)
    if(HOST_ARCH STREQUAL "arm64")
        set(AVM_APPLE_SILICON TRUE)
        message(STATUS "AVM: Apple Silicon (arm64) detected")
    else()
        set(AVM_APPLE_SILICON FALSE)
        message(STATUS "AVM: Intel Mac (x86_64) detected")
    endif()
endif()

# ── Build options ───────────────────────────────────────────────────────────
option(AVM_ENABLE_KVM         "KVM hypervisor (Linux)"            ${AVM_PLATFORM_LINUX})
option(AVM_ENABLE_HVF         "Hypervisor.framework (macOS)"      ${AVM_PLATFORM_MACOS})
option(AVM_ENABLE_WHPX        "WHPX hypervisor (Windows)"         ${AVM_PLATFORM_WINDOWS})
option(AVM_ENABLE_VULKAN      "Vulkan host renderer"              ON)
option(AVM_ENABLE_MOLTENVK    "MoltenVK Vulkan-on-Metal (macOS)" ${AVM_PLATFORM_MACOS})
option(AVM_ENABLE_OVERLAY     "Build in-window overlay UI"        ON)

# ── Compiler flags ──────────────────────────────────────────────────────────
if(MSVC)
    add_compile_options(/W3 /MP /utf-8)
    add_compile_definitions(_CRT_SECURE_NO_WARNINGS NOMINMAX WIN32_LEAN_AND_MEAN)
else()
    add_compile_options(-Wall -Wextra -Wno-unused-parameter)
    if(AVM_PLATFORM_MACOS)
        # Universal binary support: build fat binary if desired
        # set(CMAKE_OSX_ARCHITECTURES "arm64;x86_64")
        set(CMAKE_OSX_DEPLOYMENT_TARGET "12.0")
    endif()
endif()

# ── Find SDL2 ───────────────────────────────────────────────────────────────
if(AVM_PLATFORM_MACOS)
    # Prefer Homebrew SDL2
    execute_process(COMMAND brew --prefix sdl2
        OUTPUT_VARIABLE BREW_SDL2 OUTPUT_STRIP_TRAILING_WHITESPACE ERROR_QUIET)
    execute_process(COMMAND brew --prefix sdl2_ttf
        OUTPUT_VARIABLE BREW_SDL2_TTF OUTPUT_STRIP_TRAILING_WHITESPACE ERROR_QUIET)
    if(BREW_SDL2)
        list(APPEND CMAKE_PREFIX_PATH "${BREW_SDL2}")
    endif()
    if(BREW_SDL2_TTF)
        list(APPEND CMAKE_PREFIX_PATH "${BREW_SDL2_TTF}")
    endif()
elseif(AVM_PLATFORM_WINDOWS)
    # vcpkg toolchain sets this up; fallback manual hint
    if(DEFINED ENV{SDL2_DIR})
        list(APPEND CMAKE_PREFIX_PATH "$ENV{SDL2_DIR}")
    endif()
endif()

find_package(SDL2   REQUIRED)
find_package(SDL2_ttf QUIET)   # optional; overlay degrades gracefully without it

# ── Find Vulkan / MoltenVK ──────────────────────────────────────────────────
if(AVM_ENABLE_VULKAN)
    if(AVM_PLATFORM_MACOS AND AVM_ENABLE_MOLTENVK)
        # MoltenVK ships inside the Vulkan SDK or can be installed via Homebrew.
        execute_process(COMMAND brew --prefix molten-vk
            OUTPUT_VARIABLE BREW_MVK OUTPUT_STRIP_TRAILING_WHITESPACE ERROR_QUIET)
        if(BREW_MVK)
            list(APPEND CMAKE_PREFIX_PATH "${BREW_MVK}")
            set(ENV{VULKAN_SDK} "${BREW_MVK}")
        elseif(DEFINED ENV{VULKAN_SDK})
            # LunarG SDK path already set by the user
        else()
            message(WARNING
                "MoltenVK not found. Install via: brew install molten-vk\n"
                "Or install the LunarG Vulkan SDK and set VULKAN_SDK.")
            set(AVM_ENABLE_VULKAN OFF)
        endif()
    endif()
    find_package(Vulkan QUIET)
    if(NOT Vulkan_FOUND)
        message(STATUS "Vulkan SDK not found — disabling Vulkan renderer")
        set(AVM_ENABLE_VULKAN OFF)
    endif()
endif()

# ── Global includes ─────────────────────────────────────────────────────────
include_directories(${CMAKE_SOURCE_DIR}/include)

# ── Subdirectories ──────────────────────────────────────────────────────────
add_subdirectory(core)
# gpu / input / overlay are optional — they provide a custom gfxstream/input
# pipeline layered on top of QEMU. QEMU's built-in Cocoa/SDL display and input
# drivers are used instead until those pipelines are complete.
# add_subdirectory(gpu)
# add_subdirectory(input)
# add_subdirectory(overlay)

# ── Main executable ─────────────────────────────────────────────────────────
add_executable(avm src/main.cpp)
target_link_libraries(avm PRIVATE avm_core)

# macOS: link Hypervisor.framework and Metal
if(AVM_PLATFORM_MACOS)
    target_link_libraries(avm PRIVATE
        "-framework Hypervisor"
        "-framework Metal"
        "-framework Foundation"
        "-framework QuartzCore"
    )
endif()

# Windows: link WinHvPlatform for WHPX
if(AVM_PLATFORM_WINDOWS AND AVM_ENABLE_WHPX)
    target_link_libraries(avm PRIVATE WinHvPlatform)
endif()

message(STATUS "AVM v${PROJECT_VERSION} — ${CMAKE_SYSTEM_NAME} ${HOST_ARCH}")
message(STATUS "  KVM=${AVM_ENABLE_KVM}  HVF=${AVM_ENABLE_HVF}  WHPX=${AVM_ENABLE_WHPX}")
message(STATUS "  Vulkan=${AVM_ENABLE_VULKAN}  MoltenVK=${AVM_ENABLE_MOLTENVK}")
