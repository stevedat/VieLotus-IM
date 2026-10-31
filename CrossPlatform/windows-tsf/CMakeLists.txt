cmake_minimum_required(VERSION 3.20)
project(VieLotusTIP VERSION 2.0.0 LANGUAGES CXX)

# Use static MSVC runtime (/MT) so VieLotusTIP.dll has zero external VC++ Redistributable dependencies
set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_compile_options($<$<CXX_COMPILER_ID:MSVC>:/utf-8>)

include_directories(
    ${CMAKE_CURRENT_SOURCE_DIR}/src
    ${CMAKE_CURRENT_SOURCE_DIR}/../../Sources/VieLotusCAPI/include
)

set(SOURCES
    src/Globals.cpp
    src/ClassFactory.cpp
    src/EditSession.cpp
    src/VieLotusTIP.cpp
    src/Register.cpp
    src/dllmain.cpp
)

if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/../../Sources/VieLotusCoreWindows/WindowsNativeEngine.cpp")
    include_directories(${CMAKE_CURRENT_SOURCE_DIR}/../../Sources/VieLotusCoreWindows)
    list(APPEND SOURCES "${CMAKE_CURRENT_SOURCE_DIR}/../../Sources/VieLotusCoreWindows/WindowsNativeEngine.cpp")
    add_compile_definitions(VIELOTUS_EMBEDDED_ENGINE=1)
else()
    if(CMAKE_VS_PLATFORM_NAME STREQUAL "ARM64" OR CMAKE_GENERATOR_PLATFORM STREQUAL "ARM64" OR CMAKE_SYSTEM_PROCESSOR MATCHES "ARM64|aarch64")
        set(PREBUILT_ENGINE_OBJ "${CMAKE_CURRENT_SOURCE_DIR}/../../Binaries/windows/VieLotusCoreWindows-arm64.obj")
    else()
        set(PREBUILT_ENGINE_OBJ "${CMAKE_CURRENT_SOURCE_DIR}/../../Binaries/windows/VieLotusCoreWindows-x64.obj")
    endif()
    if(EXISTS "${PREBUILT_ENGINE_OBJ}")
        list(APPEND SOURCES "${PREBUILT_ENGINE_OBJ}")
        add_compile_definitions(VIELOTUS_EMBEDDED_ENGINE=1)
    endif()
endif()

add_library(VieLotusTIP SHARED
    ${SOURCES}
    VieLotusTIP.def
    VieLotusTIP.rc
)

# NOTE: Do NOT statically link VieLotusCAPI.lib into VieLotusTIP.dll.
# VieLotusTIP.dll is loaded in-process by host applications and by regsvr32.exe.
target_link_libraries(VieLotusTIP PRIVATE
    ole32
    oleaut32
    uuid
    advapi32
    user32
    gdi32
    gdiplus
    dwmapi
    shell32
)

set_target_properties(VieLotusTIP PROPERTIES
    OUTPUT_NAME "VieLotusTIP"
    PREFIX ""
)

add_executable(VieLotusSettings WIN32
    src/SettingsMain.cpp
    VieLotusSettings.rc
)

target_link_libraries(VieLotusSettings PRIVATE
    user32
    shell32
    advapi32
    ole32
)

set_target_properties(VieLotusSettings PROPERTIES
    OUTPUT_NAME "VieLotusSettings"
)
