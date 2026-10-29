cmake_minimum_required(VERSION 3.16)
project(ibus-vielotus VERSION 2.0.0 LANGUAGES C)

set(CMAKE_BUILD_WITH_INSTALL_RPATH TRUE)
set(CMAKE_INSTALL_RPATH "/usr/lib:/usr/lib/vielotus")

find_package(PkgConfig REQUIRED)
pkg_check_modules(IBUS REQUIRED ibus-1.0>=1.5.0)
pkg_check_modules(GLIB REQUIRED glib-2.0 gobject-2.0 gio-2.0)

include(GNUInstallDirs)

# Path to VieLotusCAPI header and library
set(VIELOTUS_CAPI_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../Sources/VieLotusCAPI")
set(VIELOTUS_CAPI_INCLUDE_DIR "${VIELOTUS_CAPI_DIR}/include")

if(NOT DEFINED VIELOTUS_LIB_PATH)
    if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/../../.build/release/libVieLotusCAPI.so")
        set(VIELOTUS_LIB_PATH "${CMAKE_CURRENT_SOURCE_DIR}/../../.build/release/libVieLotusCAPI.so")
    else()
        file(GLOB_RECURSE CANDIDATE_SO "${CMAKE_CURRENT_SOURCE_DIR}/../../.build/*/libVieLotusCAPI.so")
        if(CANDIDATE_SO)
            list(GET CANDIDATE_SO 0 VIELOTUS_LIB_PATH)
        elseif(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/../../Binaries/linux/libVieLotusCAPI.so")
            set(VIELOTUS_LIB_PATH "${CMAKE_CURRENT_SOURCE_DIR}/../../Binaries/linux/libVieLotusCAPI.so")
        else()
            set(VIELOTUS_LIB_PATH "${CMAKE_CURRENT_SOURCE_DIR}/../../.build/release/libVieLotusCAPI.so")
        endif()
    endif()
endif()

get_filename_component(VIELOTUS_LIB_DIR "${VIELOTUS_LIB_PATH}" DIRECTORY)
set(VIELOTUS_RPATH_LINK_FLAGS "-Wl,-rpath-link,${VIELOTUS_LIB_DIR}")
if(EXISTS "${VIELOTUS_LIB_DIR}/swift-runtime")
    list(APPEND VIELOTUS_RPATH_LINK_FLAGS "-Wl,-rpath-link,${VIELOTUS_LIB_DIR}/swift-runtime")
endif()
if(EXISTS "/usr/lib/swift/linux")
    list(APPEND VIELOTUS_RPATH_LINK_FLAGS "-Wl,-rpath-link,/usr/lib/swift/linux")
endif()

include_directories(
    ${IBUS_INCLUDE_DIRS}
    ${GLIB_INCLUDE_DIRS}
    ${VIELOTUS_CAPI_INCLUDE_DIR}
)

add_executable(ibus-engine-vielotus src/main.c)

target_link_libraries(ibus-engine-vielotus
    ${IBUS_LIBRARIES}
    ${GLIB_LIBRARIES}
    "${VIELOTUS_LIB_PATH}"
    ${VIELOTUS_RPATH_LINK_FLAGS}
    "-Wl,--no-undefined"
)

target_compile_options(ibus-engine-vielotus PRIVATE
    ${IBUS_CFLAGS_OTHER}
    ${GLIB_CFLAGS_OTHER}
    -Wall
    -Wextra
)

# Configure component XML (default to /usr/lib/ibus to match Debian/Ubuntu package layout)
if(NOT DEFINED LIBEXECDIR)
    set(LIBEXECDIR "/usr/lib/ibus")
endif()
configure_file(
    vielotus.xml.in
    ${CMAKE_CURRENT_BINARY_DIR}/vielotus.xml
    @ONLY
)

# Installation paths
install(TARGETS ibus-engine-vielotus DESTINATION ${CMAKE_INSTALL_LIBEXECDIR})
install(FILES ${CMAKE_CURRENT_BINARY_DIR}/vielotus.xml DESTINATION ${CMAKE_INSTALL_DATADIR}/ibus/component)
