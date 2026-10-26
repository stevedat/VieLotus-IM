cmake_minimum_required(VERSION 3.16)
project(fcitx5-vielotus VERSION 1.1.1 LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_BUILD_WITH_INSTALL_RPATH TRUE)
set(CMAKE_INSTALL_RPATH "/usr/lib:/usr/lib/vielotus")

find_package(ECM 1.0.0 REQUIRED NO_MODULE)
set(CMAKE_MODULE_PATH ${ECM_MODULE_PATH} "${CMAKE_CURRENT_SOURCE_DIR}/cmake" ${CMAKE_MODULE_PATH})

find_package(Fcitx5Core 5.0.0 REQUIRED)
find_package(Fcitx5Module REQUIRED COMPONENTS QuickPhrase)

include(GNUInstallDirs)
include(FeatureSummary)

# Path to VieLotusCAPI C header and built library
set(VIELOTUS_INCLUDE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../Sources/VieLotusCAPI/include")

if(WIN32)
    set(VIELOTUS_LIB_FILENAME "VieLotusCAPI.lib")
else()
    set(VIELOTUS_LIB_FILENAME "libVieLotusCAPI.so")
endif()

if(NOT DEFINED VIELOTUS_LIB_PATH)
    if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/../../.build/release/${VIELOTUS_LIB_FILENAME}")
        set(VIELOTUS_LIB_PATH "${CMAKE_CURRENT_SOURCE_DIR}/../../.build/release/${VIELOTUS_LIB_FILENAME}")
    else()
        file(GLOB_RECURSE CANDIDATE_SO "${CMAKE_CURRENT_SOURCE_DIR}/../../.build/*/${VIELOTUS_LIB_FILENAME}")
        if(CANDIDATE_SO)
            list(GET CANDIDATE_SO 0 VIELOTUS_LIB_PATH)
        elseif(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/../../Binaries/linux/${VIELOTUS_LIB_FILENAME}")
            set(VIELOTUS_LIB_PATH "${CMAKE_CURRENT_SOURCE_DIR}/../../Binaries/linux/${VIELOTUS_LIB_FILENAME}")
        else()
            set(VIELOTUS_LIB_PATH "${CMAKE_CURRENT_SOURCE_DIR}/../../.build/release/${VIELOTUS_LIB_FILENAME}")
        endif()
    endif()
endif()

message(STATUS "Using VieLotus library: ${VIELOTUS_LIB_PATH}")

include_directories(
    ${VIELOTUS_INCLUDE_DIR}
    ${CMAKE_CURRENT_SOURCE_DIR}/src
)

add_library(vielotus-addon MODULE
    src/vielotus_engine.cpp
)

target_link_libraries(vielotus-addon PRIVATE
    Fcitx5::Core
    "${VIELOTUS_LIB_PATH}"
)

set_target_properties(vielotus-addon PROPERTIES
    PREFIX ""
    OUTPUT_NAME "vielotus"
)

# Install addon configuration metadata
configure_file(vielotus.conf.in vielotus.conf @ONLY)
install(FILES "${CMAKE_CURRENT_BINARY_DIR}/vielotus.conf" DESTINATION "${FCITX_INSTALL_PKGDATADIR}/addon")
install(TARGETS vielotus-addon DESTINATION "${FCITX_INSTALL_LIBDIR}/fcitx5")
