set(AVM_OVERLAY_SOURCES
    overlay.cpp
    fps_overlay.cpp
    keymapper_editor.cpp
)

add_library(avm_overlay STATIC ${AVM_OVERLAY_SOURCES})

target_include_directories(avm_overlay PUBLIC
    ${CMAKE_SOURCE_DIR}/include
)

target_link_libraries(avm_overlay PUBLIC SDL2::SDL2)
get_target_property(_sdl2_inc SDL2::SDL2 INTERFACE_INCLUDE_DIRECTORIES)
get_filename_component(_sdl2_parent "${_sdl2_inc}" DIRECTORY)
target_include_directories(avm_overlay SYSTEM PUBLIC "${_sdl2_parent}")

# SDL2_ttf is optional: FPS overlay degrades to a simple console counter without it
if(SDL2_ttf_FOUND)
    target_link_libraries(avm_overlay PUBLIC SDL2_ttf::SDL2_ttf)
    target_compile_definitions(avm_overlay PUBLIC AVM_HAS_SDL2_TTF=1)
else()
    message(STATUS "Overlay: SDL2_ttf not found — FPS text rendering disabled")
endif()
