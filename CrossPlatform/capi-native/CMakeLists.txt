cmake_minimum_required(VERSION 3.16)
project(VieLotusCAPI VERSION 2.0.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

include(GNUInstallDirs)

set(REPO_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../..")
set(CORE_CPP_SRC "${REPO_ROOT}/Sources/VieLotusCoreWindows/WindowsNativeEngine.cpp")

if(EXISTS "${CORE_CPP_SRC}")
    add_library(VieLotusCAPI SHARED
        "${CORE_CPP_SRC}"
    )

    target_include_directories(VieLotusCAPI
        PUBLIC
            "${REPO_ROOT}/Sources/VieLotusCAPI/include"
        PRIVATE
            "${REPO_ROOT}/Sources/VieLotusCoreWindows"
    )

    target_compile_options(VieLotusCAPI PRIVATE
        -O2
        -Wall
        -Wextra
        -fvisibility=hidden
    )

    set_target_properties(VieLotusCAPI PROPERTIES
        OUTPUT_NAME "VieLotusCAPI"
        SOVERSION 0
        VERSION 0.2.0
    )

    install(TARGETS VieLotusCAPI
        LIBRARY DESTINATION "${CMAKE_INSTALL_LIBDIR}"
    )
else()
    if(CMAKE_SYSTEM_PROCESSOR MATCHES "aarch64|arm64")
        set(DEB_ARCH "arm64")
        set(MULTIARCH_DIR "aarch64-linux-gnu")
    else()
        set(DEB_ARCH "amd64")
        set(MULTIARCH_DIR "x86_64-linux-gnu")
    endif()
    set(PREBUILT_DEB "${REPO_ROOT}/Binaries/linux/libvielotus0_2.0.0_${DEB_ARCH}.deb")
    set(OUT_SO "${CMAKE_CURRENT_BINARY_DIR}/libVieLotusCAPI.so.0.2.0")

    add_custom_command(
        OUTPUT "${OUT_SO}"
               "${CMAKE_CURRENT_BINARY_DIR}/libVieLotusCAPI.so.0"
               "${CMAKE_CURRENT_BINARY_DIR}/libVieLotusCAPI.so"
        COMMAND ${CMAKE_COMMAND} -E make_directory "${CMAKE_CURRENT_BINARY_DIR}/extracted"
        COMMAND dpkg-deb -x "${PREBUILT_DEB}" "${CMAKE_CURRENT_BINARY_DIR}/extracted"
        COMMAND ${CMAKE_COMMAND} -E copy "${CMAKE_CURRENT_BINARY_DIR}/extracted/usr/lib/${MULTIARCH_DIR}/libVieLotusCAPI.so.0" "${OUT_SO}"
        COMMAND ${CMAKE_COMMAND} -E create_symlink "libVieLotusCAPI.so.0.2.0" "${CMAKE_CURRENT_BINARY_DIR}/libVieLotusCAPI.so.0"
        COMMAND ${CMAKE_COMMAND} -E create_symlink "libVieLotusCAPI.so.0" "${CMAKE_CURRENT_BINARY_DIR}/libVieLotusCAPI.so"
        COMMENT "Staging prebuilt libVieLotusCAPI.so (${DEB_ARCH})"
        VERBATIM
    )
    add_custom_target(VieLotusCAPI ALL
        DEPENDS "${OUT_SO}"
                "${CMAKE_CURRENT_BINARY_DIR}/libVieLotusCAPI.so.0"
                "${CMAKE_CURRENT_BINARY_DIR}/libVieLotusCAPI.so"
    )
    install(FILES
        "${OUT_SO}"
        "${CMAKE_CURRENT_BINARY_DIR}/libVieLotusCAPI.so.0"
        "${CMAKE_CURRENT_BINARY_DIR}/libVieLotusCAPI.so"
        DESTINATION "${CMAKE_INSTALL_LIBDIR}"
    )
endif()

install(FILES "${REPO_ROOT}/Sources/VieLotusCAPI/include/vielotus.h"
    DESTINATION "${CMAKE_INSTALL_INCLUDEDIR}"
)
