# This fixture writes only to its dedicated build-tree DESTDIR, never /usr.
if(NOT IS_DIRECTORY "${BUILD_DIR}" OR
   NOT STAGE_DIR STREQUAL "${BUILD_DIR}/desktop-input/stage")
    message(FATAL_ERROR "Invalid private desktop test stage")
endif()
file(REMOVE_RECURSE "${STAGE_DIR}")
set(ENV{DESTDIR} "${STAGE_DIR}")
execute_process(COMMAND "${CMAKE_COMMAND}" --install "${BUILD_DIR}" --prefix /usr
    COMMAND_ERROR_IS_FATAL ANY)
