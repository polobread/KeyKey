cmake_minimum_required(VERSION 3.22)

project(KeyKeyFreeBSD VERSION 1.3.1 LANGUAGES CXX)

include(CTest)
add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../Fcitx5-Common"
    "${CMAKE_CURRENT_BINARY_DIR}/fcitx5-common")
