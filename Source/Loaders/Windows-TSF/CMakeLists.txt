cmake_minimum_required(VERSION 3.25)

project(KeyKeyWindowsTsf VERSION 1.2.2 LANGUAGES C CXX)

include(CTest)

if(NOT WIN32)
    message(FATAL_ERROR "The Windows TSF frontend can only be built on Windows.")
endif()

if(MSVC)
    # A TSF DLL is injected into many client processes. Statically link the
    # runtime so deployment does not depend on a particular VC redist version.
    set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
endif()

get_filename_component(KEYKEY_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../../.." ABSOLUTE)
set(KEYKEY_SOURCE "${KEYKEY_ROOT}/Source")
set(KEYKEY_DATABASE_PATH
    "${KEYKEY_SOURCE}/Distributions/Takao/CookedDatabase/KeyKey.db"
    CACHE FILEPATH "Path to the cooked KeyKey SQLite database")
set(KEYKEY_CATEGORIZED_COLLECTION_DIR
    "${KEYKEY_ROOT}/DataSource/chichi77Collection")

add_library(keykey_third_party STATIC
    "${KEYKEY_SOURCE}/ExternalLibraries/sqlite/sqlite3.c"
    "${KEYKEY_SOURCE}/ExternalLibraries/expat/lib/xmlparse.c"
    "${KEYKEY_SOURCE}/ExternalLibraries/expat/lib/xmlrole.c"
    "${KEYKEY_SOURCE}/ExternalLibraries/expat/lib/xmltok.c"
    "${KEYKEY_SOURCE}/ExternalLibraries/expat/lib/xmltok_impl.c"
    "${KEYKEY_SOURCE}/ExternalLibraries/expat/lib/xmltok_ns.c"
)
target_include_directories(keykey_third_party PUBLIC
    "${KEYKEY_SOURCE}/ExternalLibraries/sqlite"
    "${KEYKEY_SOURCE}/ExternalLibraries/expat/lib"
)
target_compile_definitions(keykey_third_party PRIVATE
    COMPILED_FROM_DSP
    XML_STATIC
    SQLITE_THREADSAFE=1
    SQLITE_OMIT_LOAD_EXTENSION
    _CRT_SECURE_NO_WARNINGS
)
set_target_properties(keykey_third_party PROPERTIES POSITION_INDEPENDENT_CODE ON)

add_library(keykey_core STATIC
    "${KEYKEY_SOURCE}/Frameworks/OpenVanilla/Source/OVFrameworkInfo.cpp"
    "${KEYKEY_SOURCE}/Frameworks/PlainVanilla/Source/PVPropertyListExpat.cpp"
    "${KEYKEY_SOURCE}/Frameworks/Formosa/Source/Mandarin.cpp"
    "${KEYKEY_SOURCE}/ModulePackages/OVIMMandarin/OVIMTraditionalMandarin.cpp"
    "${KEYKEY_SOURCE}/ModulePackages/OVIMMandarin/OVAFAssociatedPhrase.cpp"
    KeyKeyEngine.cpp
)
target_compile_features(keykey_core PUBLIC cxx_std_17)
target_compile_definitions(keykey_core PUBLIC
    OV_USE_SQLITE
    OVIMMANDARIN_IDENTIFIER=\"Mandarin\"
    OVIMMANDARIN_PUNCTUATIONS_TABLE_PREFIX=\"Punctuations\"
    OVIMTRADITIONALMANDARIN_IDENTIFIER=\"TraditionalMandarin\"
    OVIMTRADITIONALMANDARIN_USE_ABSOLUTE_ORDER_QUERY_STRING
    OVAFASSOCIATEDPHRASE_IDENTIFIER=\"AssociatedPhrase\"
    XML_STATIC
    UNICODE
    _UNICODE
    WIN32_LEAN_AND_MEAN
    NOMINMAX
    _CRT_SECURE_NO_WARNINGS
)
target_include_directories(keykey_core PUBLIC
    "${KEYKEY_SOURCE}/Frameworks/OpenVanilla/Headers"
    "${KEYKEY_SOURCE}/Frameworks/PlainVanilla/Headers"
    "${KEYKEY_SOURCE}/Frameworks/Formosa/Headers"
    "${KEYKEY_SOURCE}/ModulePackages/OVIMMandarin"
    "${CMAKE_CURRENT_SOURCE_DIR}"
)
target_link_libraries(keykey_core PUBLIC keykey_third_party)
set_target_properties(keykey_core PROPERTIES POSITION_INDEPENDENT_CODE ON)
if(MSVC)
    target_compile_options(keykey_core PRIVATE /utf-8)
endif()

set(KEYKEY_DEPLOY_DATABASE "${KEYKEY_DATABASE_PATH}")
if(NOT EXISTS "${KEYKEY_DATABASE_PATH}")
    add_executable(KeyKeyDatabaseCooker DatabaseCooker.cpp)
    target_compile_features(KeyKeyDatabaseCooker PRIVATE cxx_std_17)
    target_link_libraries(KeyKeyDatabaseCooker PRIVATE keykey_core)
    if(MSVC)
        target_compile_options(KeyKeyDatabaseCooker PRIVATE /W4 /permissive- /utf-8)
    endif()

    set(KEYKEY_COLLECTION_INPUTS
        "${KEYKEY_ROOT}/DataSource/AssociatedPhraseCollectionNames.tsv"
        "${KEYKEY_ROOT}/DataSource/McBopomofo/phrase.occ")
    file(GLOB KEYKEY_CATEGORIZED_COLLECTION_INPUTS CONFIGURE_DEPENDS
        "${KEYKEY_CATEGORIZED_COLLECTION_DIR}/phrase.*.tsv")
    if(NOT KEYKEY_CATEGORIZED_COLLECTION_INPUTS)
        message(FATAL_ERROR
            "Categorized associated-phrase data not found: ${KEYKEY_CATEGORIZED_COLLECTION_DIR}")
    endif()
    list(APPEND KEYKEY_COLLECTION_INPUTS ${KEYKEY_CATEGORIZED_COLLECTION_INPUTS})
    message(STATUS
        "Including categorized associated-phrase data from: ${KEYKEY_CATEGORIZED_COLLECTION_DIR}")
    set(KEYKEY_NATIVE_DATABASE "${CMAKE_CURRENT_BINARY_DIR}/Databases/KeyKey.db")
    add_custom_command(
        OUTPUT "${KEYKEY_NATIVE_DATABASE}"
        COMMAND "${CMAKE_COMMAND}" -E make_directory
                "${CMAKE_CURRENT_BINARY_DIR}/Databases"
        COMMAND "$<TARGET_FILE:KeyKeyDatabaseCooker>"
                "${KEYKEY_SOURCE}"
                "${KEYKEY_ROOT}/DataSource"
                "${KEYKEY_CATEGORIZED_COLLECTION_DIR}"
                "${KEYKEY_NATIVE_DATABASE}"
        DEPENDS
            KeyKeyDatabaseCooker
            "${KEYKEY_SOURCE}/Distributions/Takao/DatabaseCooker/Schema.sql"
            "${KEYKEY_SOURCE}/DataTables/bpmf-ext.cin"
            "${KEYKEY_SOURCE}/DataTables/bpmf-punctuations.cin"
            "${KEYKEY_SOURCE}/DataTables/cj-ext.cin"
            "${KEYKEY_SOURCE}/DataTables/simplex-ext.cin"
            "${KEYKEY_SOURCE}/DataTables/cj-punctuations-halfwidth.cin"
            "${KEYKEY_SOURCE}/DataTables/cj-punctuations-mixedwidth.cin"
            "${KEYKEY_SOURCE}/DataTables/bopomofo-correction.cin"
            "${KEYKEY_SOURCE}/Distributions/Takao/OnlineData/OneKey.plist"
            "${KEYKEY_SOURCE}/Distributions/Takao/OnlineData/CannedMessages.plist"
            ${KEYKEY_COLLECTION_INPUTS}
        COMMENT "Cooking KeyKey.db with the native Windows database cooker"
        VERBATIM
    )
    add_custom_target(keykey_database ALL DEPENDS "${KEYKEY_NATIVE_DATABASE}")
    set(KEYKEY_DEPLOY_DATABASE "${KEYKEY_NATIVE_DATABASE}")
endif()

add_library(KeyKeyTsf SHARED
    CandidateWindow.cpp
    ComServer.cpp
    Diagnostics.cpp
    FrontendSettings.cpp
    LangBarButton.cpp
    KeyKeyTsf.rc
    TextService.cpp
    KeyKeyTsf.def
)
target_compile_features(KeyKeyTsf PRIVATE cxx_std_17)
target_compile_definitions(KeyKeyTsf PRIVATE
    UNICODE
    _UNICODE
    WIN32_LEAN_AND_MEAN
    NOMINMAX
    _CRT_SECURE_NO_WARNINGS
)
if(MSVC)
    target_compile_options(KeyKeyTsf PRIVATE /W4 /permissive- /utf-8)
endif()
target_link_libraries(KeyKeyTsf PRIVATE
    keykey_core
    advapi32
    gdi32
    ole32
    shell32
    user32
    uuid
)

add_executable(KeyKeySettings WIN32
    FrontendSettings.cpp
    SettingsApp.cpp
    KeyKeySettings.rc
)
target_compile_features(KeyKeySettings PRIVATE cxx_std_17)
target_compile_definitions(KeyKeySettings PRIVATE
    UNICODE
    _UNICODE
    WIN32_LEAN_AND_MEAN
    NOMINMAX
    _CRT_SECURE_NO_WARNINGS
)
if(MSVC)
    target_compile_options(KeyKeySettings PRIVATE /W4 /permissive- /utf-8)
endif()
target_link_libraries(KeyKeySettings PRIVATE
    keykey_third_party
    comctl32
    shell32
    user32
)
set_target_properties(KeyKeySettings PROPERTIES
    OUTPUT_NAME "KeyKeySettings"
)
set_target_properties(KeyKeyTsf PROPERTIES
    OUTPUT_NAME "KeyKeyTsf"
    PREFIX ""
)

if(TARGET keykey_database)
    add_dependencies(KeyKeyTsf keykey_database)
endif()

if(TARGET keykey_database OR EXISTS "${KEYKEY_DEPLOY_DATABASE}")
    add_custom_command(TARGET KeyKeyTsf POST_BUILD
        COMMAND "${CMAKE_COMMAND}" -E make_directory
                "$<TARGET_FILE_DIR:KeyKeyTsf>/Databases"
        COMMAND "${CMAKE_COMMAND}" -E copy_if_different
                "${KEYKEY_DEPLOY_DATABASE}"
                "$<TARGET_FILE_DIR:KeyKeyTsf>/Databases/KeyKey.db"
        VERBATIM
    )
endif()

if(BUILD_TESTING)
    add_executable(KeyKeyTsfInterfaceSmokeTest TsfInterfaceSmokeTest.cpp)
    target_compile_features(KeyKeyTsfInterfaceSmokeTest PRIVATE cxx_std_17)
    target_compile_definitions(KeyKeyTsfInterfaceSmokeTest PRIVATE
        UNICODE
        _UNICODE
        WIN32_LEAN_AND_MEAN
        NOMINMAX
    )
    if(MSVC)
        target_compile_options(KeyKeyTsfInterfaceSmokeTest PRIVATE /W4 /permissive- /utf-8)
    endif()
    target_link_libraries(KeyKeyTsfInterfaceSmokeTest PRIVATE ole32 oleaut32 uuid)
    add_dependencies(KeyKeyTsfInterfaceSmokeTest KeyKeyTsf)
    add_test(NAME KeyKeyTsfConfigureInterface COMMAND KeyKeyTsfInterfaceSmokeTest)

    add_executable(KeyKeyEngineSmokeTest EngineSmokeTest.cpp)
    target_compile_features(KeyKeyEngineSmokeTest PRIVATE cxx_std_17)
    target_compile_definitions(KeyKeyEngineSmokeTest PRIVATE
        UNICODE
        _UNICODE
        WIN32_LEAN_AND_MEAN
        NOMINMAX
    )
    if(MSVC)
        target_compile_options(KeyKeyEngineSmokeTest PRIVATE /W4 /permissive- /utf-8)
    endif()
    target_link_libraries(KeyKeyEngineSmokeTest PRIVATE
        keykey_core
        advapi32
        gdi32
        ole32
        shell32
        user32
        uuid
    )
    if(TARGET keykey_database)
        add_dependencies(KeyKeyEngineSmokeTest keykey_database)
    endif()
    add_test(NAME KeyKeyEngineBopomofo COMMAND KeyKeyEngineSmokeTest)

    add_executable(KeyKeyCandidateStateTest CandidateStateTest.cpp)
    target_compile_features(KeyKeyCandidateStateTest PRIVATE cxx_std_17)
    target_compile_definitions(KeyKeyCandidateStateTest PRIVATE
        UNICODE
        _UNICODE
        WIN32_LEAN_AND_MEAN
        NOMINMAX
    )
    if(MSVC)
        target_compile_options(KeyKeyCandidateStateTest PRIVATE /W4 /permissive- /utf-8)
    endif()
    target_link_libraries(KeyKeyCandidateStateTest PRIVATE
        keykey_core
        advapi32
        gdi32
        ole32
        shell32
        user32
        uuid
    )
    if(TARGET keykey_database)
        add_dependencies(KeyKeyCandidateStateTest keykey_database)
    endif()
    add_test(NAME KeyKeyCandidateKeyStateMachine COMMAND KeyKeyCandidateStateTest)
endif()

install(TARGETS KeyKeyTsf RUNTIME DESTINATION . LIBRARY DESTINATION .)
install(TARGETS KeyKeySettings RUNTIME DESTINATION .)
if(TARGET keykey_database OR EXISTS "${KEYKEY_DEPLOY_DATABASE}")
    install(FILES "${KEYKEY_DEPLOY_DATABASE}" DESTINATION Databases)
endif()
