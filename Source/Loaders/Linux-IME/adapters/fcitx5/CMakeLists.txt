add_library(chichi77-keykey SHARED fcitx5_engine.cpp)
target_compile_features(chichi77-keykey PRIVATE cxx_std_17)
target_link_libraries(chichi77-keykey PRIVATE
    Fcitx5::Core
    keykey_linux_engine
)
target_compile_definitions(chichi77-keykey PRIVATE
    KEYKEY_LINUX_DATA_DIR="${CMAKE_INSTALL_FULL_DATADIR}/chichi77-keykey/data"
)
set_target_properties(chichi77-keykey PROPERTIES PREFIX "")

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
