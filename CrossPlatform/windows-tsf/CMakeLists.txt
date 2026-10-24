cmake_minimum_required(VERSION 3.20)
project(VieLotusTIP VERSION 1.1.1 LANGUAGES CXX)

# Use static MSVC runtime (/MT) so VieLotusTIP.dll has zero external VC++ Redistributable dependencies
set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

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

add_library(VieLotusTIP SHARED
    ${SOURCES}
    VieLotusTIP.def
    VieLotusTIP.rc
)

# NOTE: Do NOT statically link VieLotusCAPI.lib into VieLotusTIP.dll.
# VieLotusTIP.dll is loaded in-process by arbitrary host applications and by regsvr32.exe.
# It dynamically loads VieLotusCAPI.dll from its own installation folder using
# LoadLibraryExW(..., LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR | LOAD_LIBRARY_SEARCH_DEFAULT_DIRS)
# so regsvr32.exe never fails with 0x3 and host apps always locate Swift runtime DLLs.
target_link_libraries(VieLotusTIP PRIVATE
    ole32
    oleaut32
    uuid
    advapi32
    user32
)

set_target_properties(VieLotusTIP PROPERTIES
    OUTPUT_NAME "VieLotusTIP"
    PREFIX ""
)
