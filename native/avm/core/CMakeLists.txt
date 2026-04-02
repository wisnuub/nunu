set(AVM_CORE_SOURCES
    vm_manager.cpp
    android_version.cpp
    image_manager.cpp
    profile.cpp
    fps_limiter.cpp
    hypervisor/hypervisor_detect.cpp
)

add_library(avm_core STATIC ${AVM_CORE_SOURCES})

target_include_directories(avm_core PUBLIC
    ${CMAKE_SOURCE_DIR}/include
)

target_compile_features(avm_core PUBLIC cxx_std_17)

# macOS: Hypervisor.framework + CoreFoundation
if(APPLE)
    target_link_libraries(avm_core PUBLIC
        "-framework Hypervisor"
        "-framework CoreFoundation"
    )
endif()

# Windows: Winsock
if(WIN32)
    target_link_libraries(avm_core PUBLIC ws2_32)
endif()
