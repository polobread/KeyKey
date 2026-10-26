# Required shared Rust core; C++ code only adapts native platform services.
if(CMAKE_CROSSCOMPILING)
    message(FATAL_ERROR "Guanyinma Unix frontend currently requires a native Rust/C++ build")
endif()
find_package(PkgConfig REQUIRED)
pkg_check_modules(JSONC REQUIRED IMPORTED_TARGET json-c)
pkg_check_modules(PANGOFT2 REQUIRED IMPORTED_TARGET pangoft2)
set(KEYKEY_GUANYINMA_SOURCE_DIR "${KEYKEY_REPOSITORY_ROOT}/Source/Guanyinma"
    CACHE PATH "Path to the Guanyinma crate")
if(DEFINED ENV{CARGO} AND NOT DEFINED CARGO)
    set(CARGO "$ENV{CARGO}" CACHE FILEPATH "Cargo executable")
endif()
find_program(CARGO NAMES cargo HINTS "$ENV{CARGO_HOME}/bin" REQUIRED)
option(KEYKEY_GUANYINMA_OFFLINE "Build using prepared locked Cargo sources only" OFF)
set(KEYKEY_GUANYINMA_OUTPUT_DIR "${CMAKE_CURRENT_BINARY_DIR}/guanyinma")
set(KEYKEY_GUANYINMA_LIBRARY "${KEYKEY_GUANYINMA_OUTPUT_DIR}/libguanyinma.a")
set(KEYKEY_GUANYINMA_NOTICES "${KEYKEY_GUANYINMA_OUTPUT_DIR}/Guanyinma-NOTICES.txt")
file(GLOB_RECURSE KEYKEY_GUANYINMA_SOURCES CONFIGURE_DEPENDS
    "${KEYKEY_GUANYINMA_SOURCE_DIR}/src/*.rs"
    "${KEYKEY_GUANYINMA_SOURCE_DIR}/include/*.h"
    "${KEYKEY_GUANYINMA_SOURCE_DIR}/LICENSES/*"
    "${KEYKEY_REPOSITORY_ROOT}/Source/Shared/*.h")
file(GLOB_RECURSE KEYKEY_GUANYINMA_REPOSITORY_NOTICES CONFIGURE_DEPENDS
    "${KEYKEY_REPOSITORY_ROOT}/LICENSES/*")
set(KEYKEY_GUANYINMA_OFFLINE_ARGS)
if(KEYKEY_GUANYINMA_OFFLINE)
    list(APPEND KEYKEY_GUANYINMA_OFFLINE_ARGS --offline)
endif()
if(CMAKE_SYSTEM_NAME STREQUAL "FreeBSD")
    set(KEYKEY_GUANYINMA_NOTICE_PLATFORM freebsd)
else()
    set(KEYKEY_GUANYINMA_NOTICE_PLATFORM linux)
endif()
add_custom_command(
    OUTPUT "${KEYKEY_GUANYINMA_OUTPUT_DIR}/build.stamp"
    BYPRODUCTS "${KEYKEY_GUANYINMA_LIBRARY}" "${KEYKEY_GUANYINMA_NOTICES}"
        "${KEYKEY_GUANYINMA_OUTPUT_DIR}/native-static-libs.rsp"
    COMMAND "${Python3_EXECUTABLE}" "${KEYKEY_GUANYINMA_SOURCE_DIR}/tools/build-unix-core.py"
        --output-dir "${KEYKEY_GUANYINMA_OUTPUT_DIR}" --cargo "${CARGO}"
        --sqlite-include "${SQLite3_INCLUDE_DIR}" --sqlite-library "${SQLite3_LIBRARY}"
        ${KEYKEY_GUANYINMA_OFFLINE_ARGS}
    COMMAND "${Python3_EXECUTABLE}" "${KEYKEY_GUANYINMA_SOURCE_DIR}/tools/package-runtime-notices.py"
        --platform "${KEYKEY_GUANYINMA_NOTICE_PLATFORM}" --cargo "${CARGO}"
        --output "${KEYKEY_GUANYINMA_NOTICES}" ${KEYKEY_GUANYINMA_OFFLINE_ARGS}
    COMMAND "${CMAKE_COMMAND}" -E touch "${KEYKEY_GUANYINMA_OUTPUT_DIR}/build.stamp"
    DEPENDS ${KEYKEY_GUANYINMA_SOURCES}
        ${KEYKEY_GUANYINMA_REPOSITORY_NOTICES}
        "${KEYKEY_REPOSITORY_ROOT}/LICENSE.txt"
        "${KEYKEY_REPOSITORY_ROOT}/LICENSING.md"
        "${KEYKEY_REPOSITORY_ROOT}/THIRD-PARTY-NOTICES.md"
        "${KEYKEY_GUANYINMA_SOURCE_DIR}/LICENSE.txt"
        "${CMAKE_CURRENT_SOURCE_DIR}/LICENSE.txt"
        "${KEYKEY_REPOSITORY_ROOT}/DataSource/McBopomofo/LICENSE.txt"
        "${KEYKEY_REPOSITORY_ROOT}/DataSource/AISyntheticBigram/LICENSE.txt"
        "${KEYKEY_REPOSITORY_ROOT}/DataSource/chichi77Collection/LICENSE.txt"
        "${SQLite3_INCLUDE_DIR}/sqlite3.h" "${SQLite3_LIBRARY}"
        "${KEYKEY_GUANYINMA_SOURCE_DIR}/Cargo.toml"
        "${KEYKEY_GUANYINMA_SOURCE_DIR}/Cargo.lock"
        "${KEYKEY_GUANYINMA_SOURCE_DIR}/rust-toolchain.toml"
        "${KEYKEY_GUANYINMA_SOURCE_DIR}/build.rs"
        "${KEYKEY_GUANYINMA_SOURCE_DIR}/tools/build-unix-core.py"
        "${KEYKEY_GUANYINMA_SOURCE_DIR}/tools/package-runtime-notices.py"
    WORKING_DIRECTORY "${KEYKEY_GUANYINMA_SOURCE_DIR}"
    USES_TERMINAL VERBATIM)
add_custom_target(keykey_guanyinma_build DEPENDS
    "${KEYKEY_GUANYINMA_OUTPUT_DIR}/build.stamp")
add_library(guanyinma_core STATIC IMPORTED GLOBAL)
set_target_properties(guanyinma_core PROPERTIES
    IMPORTED_LOCATION "${KEYKEY_GUANYINMA_LIBRARY}"
    INTERFACE_INCLUDE_DIRECTORIES "${KEYKEY_GUANYINMA_SOURCE_DIR}/include")
add_dependencies(guanyinma_core keykey_guanyinma_build)
add_library(keykey_linux_guanyinma STATIC
    engine/src/guanyinma_session.cpp engine/src/candidate_font_support.cpp)
target_compile_features(keykey_linux_guanyinma PUBLIC cxx_std_17)
target_include_directories(keykey_linux_guanyinma PUBLIC engine/include)
target_link_libraries(keykey_linux_guanyinma PUBLIC keykey_linux_support
    guanyinma_core PkgConfig::JSONC PkgConfig::PANGOFT2 SQLite::SQLite3
    "-Wl,@${KEYKEY_GUANYINMA_OUTPUT_DIR}/native-static-libs.rsp")
set_target_properties(keykey_linux_guanyinma PROPERTIES POSITION_INDEPENDENT_CODE ON
    CXX_VISIBILITY_PRESET hidden VISIBILITY_INLINES_HIDDEN YES)
if(CMAKE_CXX_COMPILER_ID MATCHES "Clang|GNU")
    target_compile_options(keykey_linux_guanyinma PRIVATE
        -Wall -Wextra -Wpedantic -Wconversion -Wsign-conversion)
endif()
# Required even when Debian disables standalone copies of repository licenses.
install(FILES "${KEYKEY_GUANYINMA_NOTICES}"
    DESTINATION "${CMAKE_INSTALL_DATADIR}/doc/chichi77-keykey")
