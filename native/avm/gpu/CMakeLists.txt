set(AVM_GPU_SOURCES
    gfxstream_bridge.cpp
    frame_presenter.cpp
)

# Vulkan renderer (all platforms, MoltenVK on macOS)
if(AVM_ENABLE_VULKAN AND Vulkan_FOUND)
    list(APPEND AVM_GPU_SOURCES vulkan_renderer.cpp)
    message(STATUS "GPU: Vulkan renderer enabled")
else()
    list(APPEND AVM_GPU_SOURCES opengl_renderer.cpp)
    message(STATUS "GPU: Vulkan unavailable — using OpenGL renderer")
endif()

add_library(avm_gpu STATIC ${AVM_GPU_SOURCES})

target_include_directories(avm_gpu PUBLIC
    ${CMAKE_SOURCE_DIR}/include
)

# SDL2 — also add parent of SDL2 include dir so <SDL2/SDL.h> resolves correctly
target_link_libraries(avm_gpu PUBLIC SDL2::SDL2)
get_target_property(_sdl2_inc SDL2::SDL2 INTERFACE_INCLUDE_DIRECTORIES)
get_filename_component(_sdl2_parent "${_sdl2_inc}" DIRECTORY)
target_include_directories(avm_gpu SYSTEM PUBLIC "${_sdl2_parent}")

# Vulkan
if(AVM_ENABLE_VULKAN AND Vulkan_FOUND)
    target_link_libraries(avm_gpu PUBLIC Vulkan::Vulkan)
    target_compile_definitions(avm_gpu PUBLIC AVM_ENABLE_VULKAN=1)
endif()

# MoltenVK: set ICD env var at build time for dev convenience
if(AVM_PLATFORM_MACOS AND AVM_ENABLE_MOLTENVK)
    target_compile_definitions(avm_gpu PUBLIC AVM_RENDERER_MOLTENVK=1)
    # MoltenVK requires MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS at runtime
    target_compile_definitions(avm_gpu PUBLIC
        MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS=1)
endif()

# OpenGL fallback — not needed on macOS (deprecated in macOS 14)
if(NOT AVM_PLATFORM_MACOS)
    find_package(OpenGL QUIET)
    if(OpenGL_FOUND)
        target_link_libraries(avm_gpu PUBLIC OpenGL::GL)
    endif()
endif()
