find_package(PkgConfig REQUIRED)
pkg_check_modules(CANBERRA REQUIRED IMPORTED_TARGET libcanberra)

add_library(chichi77-keykey SHARED
    error_sound.cpp
    fcitx5_engine.cpp
)
target_compile_features(chichi77-keykey PRIVATE cxx_std_17)
target_link_libraries(chichi77-keykey PRIVATE
    Fcitx5::Core
    PkgConfig::CANBERRA
    keykey_linux_engine
)
target_compile_definitions(chichi77-keykey PRIVATE
    KEYKEY_LINUX_DATA_DIR="${CMAKE_INSTALL_FULL_DATADIR}/chichi77-keykey/data"
    KEYKEY_VERSION_STRING="${PROJECT_VERSION}"
)
set_target_properties(chichi77-keykey PROPERTIES PREFIX "")

if(BUILD_TESTING)
    # Exercise the real adapter's mode-key handling with Fcitx KeyEvent flags,
    # independently of a display server or toolkit's modifier bookkeeping.
    add_executable(keykey_linux_fcitx5_mode_key_tests
        ../../tests/fcitx5_mode_key_tests.cpp
        error_sound.cpp
    )
    target_compile_features(keykey_linux_fcitx5_mode_key_tests PRIVATE cxx_std_17)
    target_link_libraries(keykey_linux_fcitx5_mode_key_tests PRIVATE
        Fcitx5::Core PkgConfig::CANBERRA keykey_linux_engine
    )
    target_compile_definitions(keykey_linux_fcitx5_mode_key_tests PRIVATE
        KEYKEY_LINUX_DATA_DIR="${CMAKE_INSTALL_FULL_DATADIR}/chichi77-keykey/data"
        KEYKEY_VERSION_STRING="${PROJECT_VERSION}"
    )
    add_test(NAME keykey_linux_fcitx5_mode_keys
        COMMAND keykey_linux_fcitx5_mode_key_tests)
    add_dependencies(check keykey_linux_fcitx5_mode_key_tests)
endif()

configure_file(chichi77-keykey-addon.conf.in chichi77-keykey-addon.conf)
install(TARGETS chichi77-keykey
    DESTINATION "${CMAKE_INSTALL_LIBDIR}/fcitx5"
)
install(FILES "${CMAKE_CURRENT_BINARY_DIR}/chichi77-keykey-addon.conf"
    RENAME chichi77-keykey.conf
    DESTINATION "${CMAKE_INSTALL_DATADIR}/fcitx5/addon"
)
install(FILES
    chichi77-keykey-bopomofo.conf
    chichi77-keykey-cangjie.conf
    chichi77-keykey-simplex.conf
    DESTINATION "${CMAKE_INSTALL_DATADIR}/fcitx5/inputmethod"
)
