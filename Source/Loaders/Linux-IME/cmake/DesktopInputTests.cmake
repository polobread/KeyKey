# Ordinary reviewed input contracts, separate from the manual migration baseline.
if(KEYKEY_ENABLE_DESKTOP_STABILITY_TESTS AND
   (NOT BUILD_TESTING OR NOT KEYKEY_BUILD_X11_E2E_HOST OR
    NOT KEYKEY_BUILD_FCITX5 OR NOT CMAKE_SYSTEM_NAME STREQUAL "Linux"))
    message(FATAL_ERROR "Desktop stability tests require BUILD_TESTING, X11 hosts and Fcitx on Linux")
endif()
if(NOT BUILD_TESTING)
    return()
endif()

add_test(NAME keykey_linux_desktop_core_boundaries
    COMMAND "${Python3_EXECUTABLE}"
        "${KEYKEY_REPOSITORY_ROOT}/tests/desktop_input/core_boundaries.py"
        --library "${KEYKEY_GUANYINMA_SHARED_LIBRARY}"
        --model "${KEYKEY_SMART_DB}"
        --output "${CMAKE_CURRENT_BINARY_DIR}/desktop-input/core-boundaries")
set_tests_properties(keykey_linux_desktop_core_boundaries PROPERTIES
    LABELS "desktop-core" TIMEOUT 120)

if(NOT KEYKEY_BUILD_X11_E2E_HOST OR NOT KEYKEY_BUILD_FCITX5 OR
   NOT CMAKE_SYSTEM_NAME STREQUAL "Linux")
    return()
endif()
set(KEYKEY_DESKTOP_PROFILES shared-eight-key linux-nine-key)
if(NOT KEYKEY_DESKTOP_STABILITY_PROFILE IN_LIST KEYKEY_DESKTOP_PROFILES)
    message(FATAL_ERROR "Unknown KEYKEY_DESKTOP_STABILITY_PROFILE")
endif()

set(KEYKEY_DESKTOP_STAGE "${CMAKE_CURRENT_BINARY_DIR}/desktop-input/stage")
add_test(NAME keykey_linux_desktop_stage
    COMMAND "${CMAKE_COMMAND}" "-DBUILD_DIR=${CMAKE_CURRENT_BINARY_DIR}"
        "-DSTAGE_DIR=${KEYKEY_DESKTOP_STAGE}"
        -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/DesktopInputStage.cmake")
set_tests_properties(keykey_linux_desktop_stage PROPERTIES
    FIXTURES_SETUP keykey_desktop_install LABELS "desktop-fixture" TIMEOUT 120)

foreach(toolkit IN ITEMS GTK3 GTK4 QT6)
    add_test(NAME keykey_linux_desktop_${toolkit}
        COMMAND bash "${CMAKE_CURRENT_SOURCE_DIR}/ci/run-guanyinma-smoke.sh"
            "${CMAKE_CURRENT_BINARY_DIR}" "${KEYKEY_DESKTOP_STAGE}" desktop)
    set_tests_properties(keykey_linux_desktop_${toolkit} PROPERTIES
        WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
        FIXTURES_REQUIRED keykey_desktop_install LABELS "desktop-input" TIMEOUT 600
        ENVIRONMENT "KEYKEY_E2E_DESKTOP_TOOLKITS=${toolkit};KEYKEY_E2E_DESKTOP_CATEGORIES=settings,boundary,stability;KEYKEY_E2E_DESKTOP_ROUNDS=1;KEYKEY_E2E_DESKTOP_PROFILE=shared-eight-key;KEYKEY_E2E_KEY_DELAY_MS=35;KEYKEY_E2E_ARTIFACT_ROOT=${CMAKE_CURRENT_BINARY_DIR}/desktop-input/${toolkit}")
    if(KEYKEY_ENABLE_DESKTOP_STABILITY_TESTS)
        add_test(NAME keykey_linux_desktop_stability_${toolkit}
            COMMAND bash "${CMAKE_CURRENT_SOURCE_DIR}/ci/run-guanyinma-smoke.sh"
                "${CMAKE_CURRENT_BINARY_DIR}" "${KEYKEY_DESKTOP_STAGE}" desktop)
        set_tests_properties(keykey_linux_desktop_stability_${toolkit} PROPERTIES
            WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
            FIXTURES_REQUIRED keykey_desktop_install LABELS "desktop-stability" TIMEOUT 1800
            ENVIRONMENT "KEYKEY_E2E_DESKTOP_TOOLKITS=${toolkit};KEYKEY_E2E_DESKTOP_CATEGORIES=stability;KEYKEY_E2E_DESKTOP_ROUNDS=100;KEYKEY_E2E_DESKTOP_PROFILE=${KEYKEY_DESKTOP_STABILITY_PROFILE};KEYKEY_E2E_KEY_DELAY_MS=35;KEYKEY_E2E_ARTIFACT_ROOT=${CMAKE_CURRENT_BINARY_DIR}/desktop-input/stability-${toolkit}")
    endif()
endforeach()
add_dependencies(check chichi77-keykey keykey_linux_gtk3_e2e_host
    keykey_linux_gtk4_e2e_host keykey_linux_qt6_e2e_host)
