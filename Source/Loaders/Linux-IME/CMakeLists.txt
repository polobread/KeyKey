cmake_minimum_required(VERSION 3.22)

project(KeyKeyLinux VERSION 1.2.8 LANGUAGES CXX)

include(CTest)
include(GNUInstallDirs)
find_package(Iconv REQUIRED)

if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
    set(KEYKEY_FCITX5_DEFAULT ON)
else()
    set(KEYKEY_FCITX5_DEFAULT OFF)
endif()
option(KEYKEY_BUILD_FCITX5 "Build the Fcitx 5 addon" ${KEYKEY_FCITX5_DEFAULT})
option(KEYKEY_BUILD_X11_E2E_HOST "Build the GTK 3 X11 E2E test host" OFF)
option(KEYKEY_ENABLE_SANITIZERS "Enable AddressSanitizer and UBSan" OFF)
option(KEYKEY_INSTALL_STANDALONE_LICENSE_FILES
    "Install the non-Debian standalone license copies" ON)

configure_file(
    "${CMAKE_CURRENT_SOURCE_DIR}/cmake/install-layout.txt.in"
    "${CMAKE_CURRENT_BINARY_DIR}/keykey-install-layout.txt"
    @ONLY
)

get_filename_component(KEYKEY_REPOSITORY_ROOT
    "${CMAKE_CURRENT_SOURCE_DIR}/../../.." ABSOLUTE)
set(KEYKEY_DATA_SOURCE_DIR
    "${KEYKEY_REPOSITORY_ROOT}/Source/DataTables"
    CACHE PATH "Path to the read-only KeyKey CIN data sources")
set(KEYKEY_ASSOCIATED_PHRASE_SOURCE_DIR
    "${KEYKEY_REPOSITORY_ROOT}/DataSource"
    CACHE PATH "Path to the read-only associated-phrase data sources")
set(KEYKEY_LINUX_DATA_SOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/data")
set(KEYKEY_INSTALL_DATA_DIR
    "${CMAKE_INSTALL_DATADIR}/chichi77-keykey/data")
set(KEYKEY_INSTALL_ASSOCIATED_PHRASE_DIR
    "${KEYKEY_INSTALL_DATA_DIR}/associated-phrases")
file(GLOB KEYKEY_ASSOCIATED_PHRASE_CATEGORY_FILES CONFIGURE_DEPENDS
    "${KEYKEY_ASSOCIATED_PHRASE_SOURCE_DIR}/chichi77Collection/phrase.*.tsv"
)
set(KEYKEY_ASSOCIATED_PHRASE_BUILD_DIR
    "${CMAKE_CURRENT_BINARY_DIR}/associated-phrases")
file(MAKE_DIRECTORY "${KEYKEY_ASSOCIATED_PHRASE_BUILD_DIR}")
configure_file(
    "${KEYKEY_ASSOCIATED_PHRASE_SOURCE_DIR}/McBopomofo/phrase.occ"
    "${KEYKEY_ASSOCIATED_PHRASE_BUILD_DIR}/McBopomofo.occ"
    COPYONLY
)
configure_file(
    "${KEYKEY_ASSOCIATED_PHRASE_SOURCE_DIR}/AssociatedPhraseCollectionNames.tsv"
    "${KEYKEY_ASSOCIATED_PHRASE_BUILD_DIR}/display-names.tsv"
    COPYONLY
)
foreach(KEYKEY_ASSOCIATED_PHRASE_CATEGORY_FILE
        IN LISTS KEYKEY_ASSOCIATED_PHRASE_CATEGORY_FILES)
    get_filename_component(KEYKEY_ASSOCIATED_PHRASE_CATEGORY_NAME
        "${KEYKEY_ASSOCIATED_PHRASE_CATEGORY_FILE}" NAME)
    configure_file(
        "${KEYKEY_ASSOCIATED_PHRASE_CATEGORY_FILE}"
        "${KEYKEY_ASSOCIATED_PHRASE_BUILD_DIR}/${KEYKEY_ASSOCIATED_PHRASE_CATEGORY_NAME}"
        COPYONLY
    )
endforeach()

add_library(keykey_linux_engine STATIC
    engine/src/associated_phrase_dictionary.cpp
    engine/src/bopomofo_reading.cpp
    engine/src/candidate_encoding.cpp
    engine/src/cin_dictionary.cpp
    engine/src/engine.cpp
)
target_compile_features(keykey_linux_engine PUBLIC cxx_std_17)
target_include_directories(keykey_linux_engine PUBLIC engine/include)
target_link_libraries(keykey_linux_engine PUBLIC Iconv::Iconv)
set_target_properties(keykey_linux_engine PROPERTIES
    POSITION_INDEPENDENT_CODE ON
    CXX_VISIBILITY_PRESET hidden
    VISIBILITY_INLINES_HIDDEN YES
)
if(CMAKE_CXX_COMPILER_ID MATCHES "Clang|GNU")
    target_compile_options(keykey_linux_engine PRIVATE
        -Wall -Wextra -Wpedantic -Wconversion -Wsign-conversion
    )
endif()
if(KEYKEY_ENABLE_SANITIZERS AND CMAKE_CXX_COMPILER_ID MATCHES "Clang|GNU")
    target_compile_options(keykey_linux_engine PRIVATE
        -fsanitize=address,undefined -fno-omit-frame-pointer
    )
    target_link_options(keykey_linux_engine PUBLIC
        -fsanitize=address,undefined -fno-omit-frame-pointer
    )
endif()

if(BUILD_TESTING)
    add_executable(keykey_linux_engine_tests tests/engine_tests.cpp)
    target_compile_features(keykey_linux_engine_tests PRIVATE cxx_std_17)
    target_link_libraries(keykey_linux_engine_tests PRIVATE keykey_linux_engine)
    target_compile_definitions(keykey_linux_engine_tests PRIVATE
        KEYKEY_TEST_DATA_DIR="${KEYKEY_DATA_SOURCE_DIR}"
        KEYKEY_TEST_LINUX_DATA_DIR="${KEYKEY_LINUX_DATA_SOURCE_DIR}"
        KEYKEY_TEST_ASSOCIATED_PHRASE_DATA_DIR="${KEYKEY_ASSOCIATED_PHRASE_BUILD_DIR}"
    )
    if(CMAKE_CXX_COMPILER_ID MATCHES "Clang|GNU")
        target_compile_options(keykey_linux_engine_tests PRIVATE
            -Wall -Wextra -Wpedantic -Wconversion -Wsign-conversion
        )
    endif()
    add_test(NAME keykey_linux_engine COMMAND keykey_linux_engine_tests)
    add_test(NAME keykey_linux_support_matrix
        COMMAND "${CMAKE_COMMAND}" -P
                "${CMAKE_CURRENT_SOURCE_DIR}/ci/validate-support-matrix.cmake"
    )
    add_custom_target(check
        COMMAND "${CMAKE_CTEST_COMMAND}" --output-on-failure
        DEPENDS keykey_linux_engine_tests
        WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}"
        USES_TERMINAL
    )

    if(KEYKEY_BUILD_X11_E2E_HOST)
        find_package(PkgConfig REQUIRED)
        pkg_check_modules(GTK3 REQUIRED IMPORTED_TARGET gtk+-3.0)
        add_executable(keykey_linux_gtk3_e2e_host tests/gtk3_e2e_host.cpp)
        target_compile_features(keykey_linux_gtk3_e2e_host PRIVATE cxx_std_17)
        target_link_libraries(keykey_linux_gtk3_e2e_host PRIVATE PkgConfig::GTK3)
        if(CMAKE_CXX_COMPILER_ID MATCHES "Clang|GNU")
            target_compile_options(keykey_linux_gtk3_e2e_host PRIVATE
                -Wall -Wextra -Wpedantic -Wconversion -Wsign-conversion
            )
        endif()
    endif()
endif()

if(KEYKEY_BUILD_FCITX5)
    find_package(Fcitx5Core REQUIRED)
    include("${FCITX_INSTALL_CMAKECONFIG_DIR}/Fcitx5Utils/Fcitx5CompilerSettings.cmake")
    add_subdirectory(adapters/fcitx5)
endif()

configure_file(
    "${CMAKE_CURRENT_SOURCE_DIR}/cmake/uninstall.cmake.in"
    "${CMAKE_CURRENT_BINARY_DIR}/cmake_uninstall.cmake"
    @ONLY
)
add_custom_target(uninstall
    COMMAND "${CMAKE_COMMAND}" -P
            "${CMAKE_CURRENT_BINARY_DIR}/cmake_uninstall.cmake"
    USES_TERMINAL
)

install(FILES
    "${KEYKEY_DATA_SOURCE_DIR}/bpmf-ext.cin"
    "${KEYKEY_DATA_SOURCE_DIR}/cj-ext.cin"
    "${KEYKEY_DATA_SOURCE_DIR}/simplex-ext.cin"
    "${KEYKEY_DATA_SOURCE_DIR}/bpmf-punctuations.cin"
    DESTINATION "${KEYKEY_INSTALL_DATA_DIR}"
)
install(FILES "${KEYKEY_LINUX_DATA_SOURCE_DIR}/tc2sc.cin"
    DESTINATION "${KEYKEY_INSTALL_DATA_DIR}"
)
install(FILES
    "${KEYKEY_ASSOCIATED_PHRASE_SOURCE_DIR}/McBopomofo/phrase.occ"
    DESTINATION "${KEYKEY_INSTALL_ASSOCIATED_PHRASE_DIR}"
    RENAME "McBopomofo.occ"
)
install(FILES
    "${KEYKEY_ASSOCIATED_PHRASE_SOURCE_DIR}/AssociatedPhraseCollectionNames.tsv"
    DESTINATION "${KEYKEY_INSTALL_ASSOCIATED_PHRASE_DIR}"
    RENAME "display-names.tsv"
)
install(FILES ${KEYKEY_ASSOCIATED_PHRASE_CATEGORY_FILES}
    DESTINATION "${KEYKEY_INSTALL_ASSOCIATED_PHRASE_DIR}"
)
if(KEYKEY_INSTALL_STANDALONE_LICENSE_FILES)
    install(FILES LICENSE.txt
        RENAME LICENSE-linux-frontend.txt
        DESTINATION "${CMAKE_INSTALL_DATADIR}/doc/chichi77-keykey"
    )
    install(FILES "${KEYKEY_REPOSITORY_ROOT}/LICENSES/MIT.txt"
        RENAME LICENSE-MIT.txt
        DESTINATION "${CMAKE_INSTALL_DATADIR}/doc/chichi77-keykey"
    )
    install(FILES "${KEYKEY_REPOSITORY_ROOT}/LICENSE.txt"
        RENAME LICENSE-yahoo-bsd.txt
        DESTINATION "${CMAKE_INSTALL_DATADIR}/doc/chichi77-keykey"
    )
    install(FILES
        "${KEYKEY_ASSOCIATED_PHRASE_SOURCE_DIR}/McBopomofo/LICENSE.txt"
        RENAME LICENSE-McBopomofo.txt
        DESTINATION "${CMAKE_INSTALL_DATADIR}/doc/chichi77-keykey"
    )
    install(FILES
        "${KEYKEY_ASSOCIATED_PHRASE_SOURCE_DIR}/chichi77Collection/LICENSE.txt"
        RENAME LICENSE-associated-phrase-collections.txt
        DESTINATION "${CMAKE_INSTALL_DATADIR}/doc/chichi77-keykey"
    )
endif()
