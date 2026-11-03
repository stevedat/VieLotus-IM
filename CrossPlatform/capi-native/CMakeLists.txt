cmake_minimum_required(VERSION 3.16)
project(VieLotusCAPI VERSION 2.0.2 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

include(GNUInstallDirs)
find_package(Python3 REQUIRED COMPONENTS Interpreter)

set(REPO_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../..")
set(CORE_WIN_DIR "${REPO_ROOT}/Sources/VieLotusCoreWindows")
set(CORE_CPP_SRC "${CORE_WIN_DIR}/WindowsNativeEngine.cpp")
set(CORE_H_SRC "${CORE_WIN_DIR}/WindowsNativeEngine.h")
set(LEXICON_DIR "${CORE_WIN_DIR}/lexicon")
set(LEXICON_GEN_SCRIPT "${CORE_WIN_DIR}/scripts/generate_lexicon_hashes.py")

set(LEXICON_FILES
    "${LEXICON_DIR}/00_initial_onsets.txt"
    "${LEXICON_DIR}/01_final_codas.txt"
    "${LEXICON_DIR}/02_stop_codas.txt"
    "${LEXICON_DIR}/03_double_o_codas.txt"
    "${LEXICON_DIR}/04_unconditional_english_words.txt"
    "${LEXICON_DIR}/05_context_english_collision_words.txt"
    "${LEXICON_DIR}/06_english_context_anchors.txt"
    "${LEXICON_DIR}/07_sex_loanword_preceding_heads.txt"
    "${LEXICON_DIR}/08_vietnamese_context_resets.txt"
    "${LEXICON_DIR}/09_turn_phrasal_followers.txt"
    "${LEXICON_DIR}/10_sex_english_followers.txt"
    "${LEXICON_DIR}/11_extended_english_escapes.txt"
)

foreach(REQUIRED_SRC "${CORE_CPP_SRC}" "${CORE_H_SRC}" "${LEXICON_GEN_SCRIPT}" ${LEXICON_FILES})
    if(NOT EXISTS "${REQUIRED_SRC}")
        message(FATAL_ERROR
            "Missing required VieLotusIM C++20 source or lexicon file: ${REQUIRED_SRC}. "
            "Binary fallback is disabled; libVieLotusCAPI must be built from full unobfuscated source."
        )
    endif()
endforeach()

set(GENERATED_DIR "${CMAKE_CURRENT_BINARY_DIR}/generated")
set(GENERATED_INCLUDE_SUBDIR "${GENERATED_DIR}/VieLotusLexicon")
set(GENERATED_LEXICON_INC "${GENERATED_INCLUDE_SUBDIR}/WindowsNativeLexiconGenerated.inc")

add_custom_command(
    OUTPUT "${GENERATED_LEXICON_INC}"
    COMMAND ${CMAKE_COMMAND} -E make_directory "${GENERATED_INCLUDE_SUBDIR}"
    COMMAND "${Python3_EXECUTABLE}" "${LEXICON_GEN_SCRIPT}"
            --lexicon-dir "${LEXICON_DIR}"
            --output "${GENERATED_LEXICON_INC}"
    DEPENDS "${LEXICON_GEN_SCRIPT}" ${LEXICON_FILES}
    COMMENT "Generating VieLotusLexicon/WindowsNativeLexiconGenerated.inc from UTF-8 NFC wordlists"
    VERBATIM
)

add_library(VieLotusCAPI SHARED
    "${CORE_CPP_SRC}"
    "${GENERATED_LEXICON_INC}"
)

target_include_directories(VieLotusCAPI
    PUBLIC
        "${REPO_ROOT}/Sources/VieLotusCAPI/include"
    PRIVATE
        "${GENERATED_DIR}"
        "${CORE_WIN_DIR}"
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
    VERSION 0.2.1
)

install(TARGETS VieLotusCAPI
    LIBRARY DESTINATION "${CMAKE_INSTALL_LIBDIR}"
    NAMELINK_SKIP
)

if(VIELOTUS_INSTALL_DEV)
    install(FILES "${REPO_ROOT}/Sources/VieLotusCAPI/include/vielotus.h"
        DESTINATION "${CMAKE_INSTALL_INCLUDEDIR}"
    )
endif()
