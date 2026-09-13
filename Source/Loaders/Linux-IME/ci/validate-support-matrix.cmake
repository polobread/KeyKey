cmake_minimum_required(VERSION 3.22)

file(READ "${CMAKE_CURRENT_LIST_DIR}/support-matrix.json" matrix)
string(JSON target_count LENGTH "${matrix}" targets)

if(NOT target_count EQUAL 20)
    message(FATAL_ERROR
        "The Linux support matrix must contain exactly 20 distro versions; found ${target_count}")
endif()

math(EXPR last_target "${target_count} - 1")
set(target_ids)
set(primary_count 0)
set(active_count 0)
set(future_count 0)
set(allowed_statuses pending build-only desktop-tested release-qualified)

foreach(index RANGE 0 ${last_target})
    string(JSON distro GET "${matrix}" targets ${index} distro)
    string(JSON version GET "${matrix}" targets ${index} version)
    string(JSON priority GET "${matrix}" targets ${index} priority)
    string(JSON phase GET "${matrix}" targets ${index} phase)
    string(JSON required GET "${matrix}" targets ${index} required)
    string(JSON status GET "${matrix}" targets ${index} status)
    set(target_id "${distro}-${version}")

    if(target_id IN_LIST target_ids)
        message(FATAL_ERROR "Duplicate Linux support target: ${target_id}")
    endif()
    list(APPEND target_ids "${target_id}")

    if(NOT status IN_LIST allowed_statuses)
        message(FATAL_ERROR "Unknown support status for ${target_id}: ${status}")
    endif()

    if(priority STREQUAL "primary")
        math(EXPR primary_count "${primary_count} + 1")
        if(NOT target_id STREQUAL "ubuntu-24.04")
            message(FATAL_ERROR "Only Ubuntu 24.04 may be the primary target")
        endif()
    endif()

    if(distro STREQUAL "ubuntu")
        if(NOT phase STREQUAL "active")
            message(FATAL_ERROR "Ubuntu target is not active: ${target_id}")
        endif()
        math(EXPR active_count "${active_count} + 1")
    elseif(distro STREQUAL "debian" OR distro STREQUAL "fedora")
        if(NOT phase STREQUAL "future-todo" OR required)
            message(FATAL_ERROR
                "Deferred target must be a non-required future TODO: ${target_id}")
        endif()
        math(EXPR future_count "${future_count} + 1")
    else()
        message(FATAL_ERROR "Unknown Linux distro family: ${distro}")
    endif()
endforeach()

if(NOT primary_count EQUAL 1)
    message(FATAL_ERROR
        "The Linux support matrix must contain one primary target; found ${primary_count}")
endif()

if(NOT active_count EQUAL 9 OR NOT future_count EQUAL 11)
    message(FATAL_ERROR
        "Expected 9 active Ubuntu and 11 deferred Debian/Fedora targets; found ${active_count} and ${future_count}")
endif()
