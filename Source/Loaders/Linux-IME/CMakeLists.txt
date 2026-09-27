cmake_minimum_required(VERSION 3.22)

project(KeyKeyLinux VERSION 1.3.0 LANGUAGES CXX)

include(CTest)
include(GNUInstallDirs)
option(KEYKEY_BUILD_X11_E2E_HOST
    "Build the GTK 3, GTK 4, and Qt 6 X11 E2E test hosts" OFF)

configure_file(
    "${CMAKE_CURRENT_SOURCE_DIR}/cmake/install-layout.txt.in"
    "${CMAKE_CURRENT_BINARY_DIR}/keykey-install-layout.txt"
    @ONLY
)

add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../Fcitx5-Common"
    "${CMAKE_CURRENT_BINARY_DIR}/fcitx5-common")

if(BUILD_TESTING)
    add_test(NAME keykey_linux_support_matrix
        COMMAND "${CMAKE_COMMAND}" -P
                "${CMAKE_CURRENT_SOURCE_DIR}/ci/validate-support-matrix.cmake")
    add_custom_target(check
        COMMAND "${CMAKE_CTEST_COMMAND}" --output-on-failure
        DEPENDS keykey_linux_engine_tests
        WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}"
        USES_TERMINAL)
    if(KEYKEY_BUILD_X11_E2E_HOST)
        find_package(PkgConfig REQUIRED)
        pkg_check_modules(GTK3 REQUIRED IMPORTED_TARGET gtk+-3.0)
        pkg_check_modules(GTK4 REQUIRED IMPORTED_TARGET gtk4)
        find_package(Qt6 REQUIRED COMPONENTS Widgets)
        add_executable(keykey_linux_gtk3_e2e_host tests/gtk3_e2e_host.cpp)
        target_compile_features(keykey_linux_gtk3_e2e_host PRIVATE cxx_std_17)
        target_link_libraries(keykey_linux_gtk3_e2e_host PRIVATE PkgConfig::GTK3)
        if(CMAKE_CXX_COMPILER_ID MATCHES "Clang|GNU")
            target_compile_options(keykey_linux_gtk3_e2e_host PRIVATE
                -Wall -Wextra -Wpedantic -Wconversion -Wsign-conversion
            )
        endif()
        add_executable(keykey_linux_gtk4_e2e_host tests/gtk4_e2e_host.cpp)
        target_compile_features(keykey_linux_gtk4_e2e_host PRIVATE cxx_std_17)
        target_link_libraries(keykey_linux_gtk4_e2e_host PRIVATE PkgConfig::GTK4)
        if(CMAKE_CXX_COMPILER_ID MATCHES "Clang|GNU")
            target_compile_options(keykey_linux_gtk4_e2e_host PRIVATE
                -Wall -Wextra -Wpedantic -Wconversion -Wsign-conversion
            )
        endif()
        add_executable(keykey_linux_qt6_e2e_host tests/qt6_e2e_host.cpp)
        target_compile_features(keykey_linux_qt6_e2e_host PRIVATE cxx_std_17)
        target_link_libraries(keykey_linux_qt6_e2e_host PRIVATE Qt6::Widgets)
        if(CMAKE_CXX_COMPILER_ID MATCHES "Clang|GNU")
            target_compile_options(keykey_linux_qt6_e2e_host PRIVATE
                -Wall -Wextra -Wpedantic -Wconversion -Wsign-conversion
            )
        endif()
    endif()
endif()

if(KEYKEY_BUILD_FCITX5)
    install(PROGRAMS tools/keykey-fcitx-app
        DESTINATION "${CMAKE_INSTALL_BINDIR}")
    install(FILES data/org.chichi77.KeyKey.TextEditor.desktop
        DESTINATION "${CMAKE_INSTALL_DATADIR}/applications")
    install(FILES docs/keykey-fcitx-app.1
        DESTINATION "${CMAKE_INSTALL_MANDIR}/man1")
endif()

configure_file(
    "${CMAKE_CURRENT_SOURCE_DIR}/cmake/uninstall.cmake.in"
    "${CMAKE_CURRENT_BINARY_DIR}/cmake_uninstall.cmake"
    @ONLY)
add_custom_target(uninstall
    COMMAND "${CMAKE_COMMAND}" -P
            "${CMAKE_CURRENT_BINARY_DIR}/cmake_uninstall.cmake"
    USES_TERMINAL)
