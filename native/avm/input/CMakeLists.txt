set(AVM_INPUT_SOURCES
    input_bridge_sdl.cpp
    input_bridge_adb.cpp
    gamepad_bridge_sdl.cpp
    adb_injector.cpp
)

# virtio_input: Unix domain sockets — Linux and macOS only
if(NOT AVM_PLATFORM_WINDOWS)
    list(APPEND AVM_INPUT_SOURCES virtio_input.cpp)
endif()

add_library(avm_input STATIC ${AVM_INPUT_SOURCES})

target_include_directories(avm_input PUBLIC
    ${CMAKE_SOURCE_DIR}/include
)

target_link_libraries(avm_input PUBLIC SDL2::SDL2)
get_target_property(_sdl2_inc SDL2::SDL2 INTERFACE_INCLUDE_DIRECTORIES)
get_filename_component(_sdl2_parent "${_sdl2_inc}" DIRECTORY)
target_include_directories(avm_input SYSTEM PUBLIC "${_sdl2_parent}")

# Windows: link Winsock for ADB socket transport
if(AVM_PLATFORM_WINDOWS)
    target_link_libraries(avm_input PUBLIC ws2_32)
    target_compile_definitions(avm_input PUBLIC AVM_VIRTIO_DISABLED=1)
endif()
