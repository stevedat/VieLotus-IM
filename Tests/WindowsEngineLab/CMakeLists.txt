cmake_minimum_required(VERSION 3.16)
project(VieLotusWinEngineLab LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Python3 REQUIRED COMPONENTS Interpreter)

set(REPO_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../..")
set(CORE_WIN_DIR "${REPO_ROOT}/Sources/VieLotusCoreWindows")
set(CORE_CPP_SRC "${CORE_WIN_DIR}/WindowsNativeEngine.cpp")
set(CORE_H_SRC "${CORE_WIN_DIR}/WindowsNativeEngine.h")
set(LEXICON_DIR "${CORE_WIN_DIR}/lexicon")
set(LEXICON_GEN_SCRIPT "${CORE_WIN_DIR}/scripts/generate_lexicon_hashes.py")

file(GLOB LEXICON_FILES "${LEXICON_DIR}/*.txt")
list(SORT LEXICON_FILES)

foreach(REQUIRED_SRC "${CORE_CPP_SRC}" "${CORE_H_SRC}" "${LEXICON_GEN_SCRIPT}")
    if(NOT EXISTS "${REQUIRED_SRC}")
        message(FATAL_ERROR "Missing required VieLotusCoreWindows source file: ${REQUIRED_SRC}")
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

add_executable(VieLotusWinEngineLab
    main.cpp
    "${CORE_CPP_SRC}"
    "${GENERATED_LEXICON_INC}"
)

# Deliberately exclude prebuilt/ so the binary compiles exclusively from the
# generated table under ${GENERATED_DIR}.
target_include_directories(VieLotusWinEngineLab PRIVATE
    "${GENERATED_DIR}"
    "${CORE_WIN_DIR}"
    "${REPO_ROOT}/Sources/VieLotusCAPI/include"
    "${REPO_ROOT}/CrossPlatform/common"
)

target_compile_definitions(VieLotusWinEngineLab PRIVATE
    NOMINMAX
    _CRT_SECURE_NO_WARNINGS
)

if(MSVC)
    target_compile_options(VieLotusWinEngineLab PRIVATE /utf-8 /EHsc /W3)
else()
    target_compile_options(VieLotusWinEngineLab PRIVATE -O2 -Wall -Wextra)
endif()
