cmake_minimum_required(VERSION 3.20)
project(VieLotusTIP VERSION 2.0.6 LANGUAGES CXX)

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
    message(FATAL_ERROR "Sources/VieLotusCoreWindows/WindowsNativeEngine.cpp is required to build VieLotusTIP")
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

option(VIELOTUS_BUILD_SETTINGS "Build VieLotusSettings.exe" ON)
set(VIELOTUS_ARM64X_PASS "" CACHE STRING "Two-pass ARM64X build phase: ARM64 or ARM64EC")
set(VIELOTUS_ARM64X_REPRO_DIR "" CACHE PATH "Directory holding native ARM64 /LINKREPRO artifacts for ARM64X linking")

if(CMAKE_SIZEOF_VOID_P EQUAL 4)
    set(VIELOTUS_TIP_OUTPUT_NAME "VieLotusTIP32")
else()
    set(VIELOTUS_TIP_OUTPUT_NAME "VieLotusTIP")
endif()

set_target_properties(VieLotusTIP PROPERTIES
    OUTPUT_NAME "${VIELOTUS_TIP_OUTPUT_NAME}"
    PREFIX ""
)

if(MSVC AND VIELOTUS_ARM64X_PASS STREQUAL "ARM64")
    if(NOT VIELOTUS_ARM64X_REPRO_DIR)
        message(FATAL_ERROR "VIELOTUS_ARM64X_REPRO_DIR is required when VIELOTUS_ARM64X_PASS=ARM64")
    endif()
    file(MAKE_DIRECTORY "${VIELOTUS_ARM64X_REPRO_DIR}")
    target_link_options(VieLotusTIP PRIVATE "/LINKREPROFULLPATHRSP:${VIELOTUS_ARM64X_REPRO_DIR}/VieLotusTIP.rsp")
elseif(MSVC AND VIELOTUS_ARM64X_PASS STREQUAL "ARM64EC")
    set(VIELOTUS_ARM64_RSP "${VIELOTUS_ARM64X_REPRO_DIR}/VieLotusTIP.rsp")
    if(NOT EXISTS "${VIELOTUS_ARM64_RSP}")
        message(FATAL_ERROR "ARM64 link repro RSP '${VIELOTUS_ARM64_RSP}' not found. Run ARM64 pass first.")
    endif()
    file(STRINGS "${VIELOTUS_ARM64_RSP}" VIELOTUS_ARM64_RSP_LINES)
    set(VIELOTUS_ARM64_OBJS "")
    set(VIELOTUS_ARM64_LIBS "")
    foreach(_rsp_line IN LISTS VIELOTUS_ARM64_RSP_LINES)
        string(STRIP "${_rsp_line}" _clean)
        string(REGEX REPLACE "^\"(.*)\"$" "\\1" _unquoted "${_clean}")
        if(_unquoted MATCHES "^[/-]")
            continue()
        endif()
        file(TO_CMAKE_PATH "${_unquoted}" _norm_path)
        string(TOLOWER "${_norm_path}" _lower)
        if(_lower MATCHES "\\.obj$" AND EXISTS "${_norm_path}")
            list(APPEND VIELOTUS_ARM64_OBJS "${_norm_path}")
        elseif(_lower MATCHES "\\.lib$" AND EXISTS "${_norm_path}")
            list(APPEND VIELOTUS_ARM64_LIBS "${_norm_path}")
        endif()
    endforeach()
    if(NOT VIELOTUS_ARM64_OBJS)
        message(FATAL_ERROR "No ARM64 .obj entries parsed from '${VIELOTUS_ARM64_RSP}'")
    endif()
    list(REMOVE_DUPLICATES VIELOTUS_ARM64_OBJS)
    if(VIELOTUS_ARM64_LIBS)
        list(REMOVE_DUPLICATES VIELOTUS_ARM64_LIBS)
    endif()
    list(LENGTH VIELOTUS_ARM64_OBJS _arm64_obj_count)
    list(LENGTH VIELOTUS_ARM64_LIBS _arm64_lib_count)
    message(STATUS "ARM64X link pass: ${_arm64_obj_count} ARM64 .obj + ${_arm64_lib_count} ARM64 .lib inputs from ${VIELOTUS_ARM64_RSP}")
    target_sources(VieLotusTIP PRIVATE ${VIELOTUS_ARM64_OBJS})
    if(VIELOTUS_ARM64_LIBS)
        target_link_libraries(VieLotusTIP PRIVATE ${VIELOTUS_ARM64_LIBS})
    endif()
    target_link_options(VieLotusTIP PRIVATE
        /MACHINE:ARM64X
        "/defArm64Native:${CMAKE_CURRENT_SOURCE_DIR}/VieLotusTIP.def"
    )
endif()

if(VIELOTUS_BUILD_SETTINGS AND NOT CMAKE_SIZEOF_VOID_P EQUAL 4)
    add_executable(VieLotusSettings WIN32
        src/SettingsMain.cpp
        VieLotusSettings.rc
        VieLotusSettings.manifest
    )

    target_link_libraries(VieLotusSettings PRIVATE
        user32
        gdi32
        shell32
        advapi32
        ole32
        uuid
    )

    set_target_properties(VieLotusSettings PROPERTIES
        OUTPUT_NAME "VieLotusSettings"
    )
endif()
