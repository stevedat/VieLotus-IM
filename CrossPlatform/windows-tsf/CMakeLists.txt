cmake_minimum_required(VERSION 3.20)
project(VieLotusTIP VERSION 2.0.2 LANGUAGES CXX)

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

set(CORE_WIN_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../Sources/VieLotusCoreWindows")
if(EXISTS "${CORE_WIN_DIR}/WindowsNativeEngine.cpp")
    find_package(Python3 QUIET COMPONENTS Interpreter)
    if(Python3_Interpreter_FOUND AND EXISTS "${CORE_WIN_DIR}/scripts/generate_lexicon_hashes.py")
        set(WIN_GENERATED_DIR "${CMAKE_CURRENT_BINARY_DIR}/generated")
        set(WIN_GENERATED_SUBDIR "${WIN_GENERATED_DIR}/VieLotusLexicon")
        set(WIN_GENERATED_INC "${WIN_GENERATED_SUBDIR}/WindowsNativeLexiconGenerated.inc")
        set(WIN_LEXICON_FILES
            "${CORE_WIN_DIR}/lexicon/00_initial_onsets.txt"
            "${CORE_WIN_DIR}/lexicon/01_final_codas.txt"
            "${CORE_WIN_DIR}/lexicon/02_stop_codas.txt"
            "${CORE_WIN_DIR}/lexicon/03_double_o_codas.txt"
            "${CORE_WIN_DIR}/lexicon/04_unconditional_english_words.txt"
            "${CORE_WIN_DIR}/lexicon/05_context_english_collision_words.txt"
            "${CORE_WIN_DIR}/lexicon/06_english_context_anchors.txt"
            "${CORE_WIN_DIR}/lexicon/07_sex_loanword_preceding_heads.txt"
            "${CORE_WIN_DIR}/lexicon/08_vietnamese_context_resets.txt"
            "${CORE_WIN_DIR}/lexicon/09_turn_phrasal_followers.txt"
            "${CORE_WIN_DIR}/lexicon/10_sex_english_followers.txt"
            "${CORE_WIN_DIR}/lexicon/11_extended_english_escapes.txt"
        )
        add_custom_command(
            OUTPUT "${WIN_GENERATED_INC}"
            COMMAND ${CMAKE_COMMAND} -E make_directory "${WIN_GENERATED_SUBDIR}"
            COMMAND "${Python3_EXECUTABLE}" "${CORE_WIN_DIR}/scripts/generate_lexicon_hashes.py"
                    --lexicon-dir "${CORE_WIN_DIR}/lexicon"
                    --output "${WIN_GENERATED_INC}"
            DEPENDS "${CORE_WIN_DIR}/scripts/generate_lexicon_hashes.py" ${WIN_LEXICON_FILES}
            COMMENT "Generating VieLotusLexicon/WindowsNativeLexiconGenerated.inc for Windows TSF"
            VERBATIM
        )
        include_directories("${WIN_GENERATED_DIR}")
        list(APPEND SOURCES "${WIN_GENERATED_INC}")
    elseif(EXISTS "${CORE_WIN_DIR}/prebuilt/VieLotusLexicon/WindowsNativeLexiconGenerated.inc")
        include_directories("${CORE_WIN_DIR}/prebuilt")
    else()
        message(FATAL_ERROR "Python3 interpreter is required to generate VieLotusLexicon/WindowsNativeLexiconGenerated.inc")
    endif()
    include_directories("${CORE_WIN_DIR}")
    list(APPEND SOURCES "${CORE_WIN_DIR}/WindowsNativeEngine.cpp")
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
    VieLotusSettings.manifest
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
