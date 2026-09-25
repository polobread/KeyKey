cmake_minimum_required(VERSION 3.25)

project(KeyKeyWindowsTsf VERSION 1.3.0 LANGUAGES C CXX)

set(KEYKEY_VERSION_TWEAK 0)
if(NOT "${PROJECT_VERSION_TWEAK}" STREQUAL "")
    set(KEYKEY_VERSION_TWEAK "${PROJECT_VERSION_TWEAK}")
endif()
set(KEYKEY_VERSION_STRING
    "${PROJECT_VERSION_MAJOR}.${PROJECT_VERSION_MINOR}.${PROJECT_VERSION_PATCH}.${KEYKEY_VERSION_TWEAK}")
set(KEYKEY_VERSION_DEFINITIONS
    "KEYKEY_VERSION_MAJOR=${PROJECT_VERSION_MAJOR}"
    "KEYKEY_VERSION_MINOR=${PROJECT_VERSION_MINOR}"
    "KEYKEY_VERSION_PATCH=${PROJECT_VERSION_PATCH}"
    "KEYKEY_VERSION_TWEAK=${KEYKEY_VERSION_TWEAK}"
    "KEYKEY_MARKETING_VERSION=\"${PROJECT_VERSION}\""
    "KEYKEY_VERSION_STRING=\"${KEYKEY_VERSION_STRING}\""
)

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
    ""
    CACHE FILEPATH "Path to the cooked KeyKey SQLite database")
if(KEYKEY_DATABASE_PATH AND NOT EXISTS "${KEYKEY_DATABASE_PATH}")
    message(FATAL_ERROR "KEYKEY_DATABASE_PATH does not exist: ${KEYKEY_DATABASE_PATH}")
endif()
set(KEYKEY_CATEGORIZED_COLLECTION_DIR
    "${KEYKEY_ROOT}/DataSource/chichi77Collection")

add_library(keykey_third_party STATIC
    "${KEYKEY_SOURCE}/ExternalLibraries/expat/lib/xmlparse.c"
    "${KEYKEY_SOURCE}/ExternalLibraries/expat/lib/xmlrole.c"
    "${KEYKEY_SOURCE}/ExternalLibraries/expat/lib/xmltok.c"
    "${KEYKEY_SOURCE}/ExternalLibraries/expat/lib/xmltok_impl.c"
    "${KEYKEY_SOURCE}/ExternalLibraries/expat/lib/xmltok_ns.c"
)
target_include_directories(keykey_third_party PUBLIC
    "${CMAKE_CURRENT_SOURCE_DIR}"
    "${KEYKEY_SOURCE}/ExternalLibraries/expat/lib"
)
target_compile_definitions(keykey_third_party PRIVATE
    COMPILED_FROM_DSP
    XML_STATIC
    _CRT_SECURE_NO_WARNINGS
)
target_link_libraries(keykey_third_party PUBLIC winsqlite3)
set_target_properties(keykey_third_party PROPERTIES POSITION_INDEPENDENT_CODE ON)

add_library(keykey_core STATIC
    FrontendSettings.cpp
    "${KEYKEY_SOURCE}/Frameworks/OpenVanilla/Source/OVFrameworkInfo.cpp"
    "${KEYKEY_SOURCE}/Frameworks/PlainVanilla/Source/PVPropertyListExpat.cpp"
    "${KEYKEY_SOURCE}/Frameworks/Formosa/Source/Mandarin.cpp"
    "${KEYKEY_SOURCE}/Frameworks/Manjusri/Source/Node.cpp"
    "${KEYKEY_SOURCE}/ModulePackages/OVIMMandarin/OVIMTraditionalMandarin.cpp"
    "${KEYKEY_SOURCE}/ModulePackages/OVIMMandarin/OVIMSmartMandarin.cpp"
    "${KEYKEY_SOURCE}/ModulePackages/OVIMMandarin/OVAFAssociatedPhrase.cpp"
    KeyKeyEngine.cpp
)
target_compile_features(keykey_core PUBLIC cxx_std_17)
target_compile_definitions(keykey_core PUBLIC
    OV_USE_SQLITE
    OVIMMANDARIN_IDENTIFIER=\"Mandarin\"
    OVIMMANDARIN_PUNCTUATIONS_TABLE_PREFIX=\"Punctuations\"
    OVIMTRADITIONALMANDARIN_IDENTIFIER=\"TraditionalMandarin\"
    OVIMSMARTMANDARIN_IDENTIFIER=\"SmartMandarin\"
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
    "${KEYKEY_SOURCE}/Frameworks/Manjusri/Headers"
    "${KEYKEY_SOURCE}/ModulePackages/OVIMMandarin"
    "${CMAKE_CURRENT_SOURCE_DIR}"
)
target_link_libraries(keykey_core PUBLIC keykey_third_party)
set_target_properties(keykey_core PROPERTIES POSITION_INDEPENDENT_CODE ON)
if(MSVC)
    target_compile_options(keykey_core PRIVATE /utf-8)
endif()

set(KEYKEY_DEPLOY_DATABASE "${KEYKEY_DATABASE_PATH}")
find_package(Python3 REQUIRED COMPONENTS Interpreter)
if(NOT KEYKEY_DATABASE_PATH)
    find_package(Ruby REQUIRED COMPONENTS Interpreter)
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
    set(KEYKEY_SMART_SQL "${CMAKE_CURRENT_BINARY_DIR}/Databases/SmartMandarin.sql")
    set(KEYKEY_ABSOLUTE_CIN "${CMAKE_CURRENT_BINARY_DIR}/Databases/bpmf-absorder.cin")
    set(KEYKEY_SMART_COOKER
        "${KEYKEY_SOURCE}/Distributions/Takao/DatabaseCooker/SmartMandarinCooker.rb")
    set(KEYKEY_SMART_CORPORA
        "${KEYKEY_ROOT}/DataSource/AISyntheticBigram/corpus-v1.txt"
        "${KEYKEY_ROOT}/DataSource/AISyntheticBigram/corpus-v2.txt"
        "${KEYKEY_ROOT}/DataSource/AISyntheticBigram/corpus-v3.txt"
        "${KEYKEY_ROOT}/DataSource/AISyntheticBigram/corpus-typing-feedback.txt"
        "${KEYKEY_ROOT}/DataSource/AISyntheticBigram/article-corpus-2300-exact-dedup.txt")
    set(KEYKEY_SMART_LEXICONS
        "${KEYKEY_ROOT}/DataSource/AISyntheticBigram/supplemental-lexicon.tsv"
        "${KEYKEY_ROOT}/DataSource/AISyntheticBigram/numeric-unit-lexicon.tsv")
    foreach(KEYKEY_SMART_INPUT IN LISTS KEYKEY_SMART_CORPORA KEYKEY_SMART_LEXICONS)
        if(NOT EXISTS "${KEYKEY_SMART_INPUT}")
            message(FATAL_ERROR "Smart Mandarin source data not found: ${KEYKEY_SMART_INPUT}")
        endif()
    endforeach()
    message(STATUS
        "Including categorized associated-phrase data from: ${KEYKEY_CATEGORIZED_COLLECTION_DIR}")
    set(KEYKEY_NATIVE_DATABASE "${CMAKE_CURRENT_BINARY_DIR}/Databases/KeyKey.db")
    set(KEYKEY_NATIVE_DATABASE_STAMP "${CMAKE_CURRENT_BINARY_DIR}/Databases/KeyKey.db.complete")
    add_custom_command(
        OUTPUT "${KEYKEY_NATIVE_DATABASE_STAMP}"
        BYPRODUCTS "${KEYKEY_NATIVE_DATABASE}" "${KEYKEY_ABSOLUTE_CIN}" "${KEYKEY_SMART_SQL}"
        COMMAND "${CMAKE_COMMAND}" -E make_directory
                "${CMAKE_CURRENT_BINARY_DIR}/Databases"
        COMMAND "$<TARGET_FILE:KeyKeyDatabaseCooker>"
                "${KEYKEY_SOURCE}"
                "${KEYKEY_ROOT}/DataSource"
                "${KEYKEY_CATEGORIZED_COLLECTION_DIR}"
                "${KEYKEY_NATIVE_DATABASE}"
                "${KEYKEY_ABSOLUTE_CIN}"
        COMMAND "${Ruby_EXECUTABLE}"
                "${CMAKE_CURRENT_SOURCE_DIR}/GenerateSmartMandarinSql.rb"
                "${KEYKEY_SMART_SQL}"
                "${KEYKEY_SMART_COOKER}"
                "${KEYKEY_ROOT}/DataSource/McBopomofo/phrase.occ"
                "${KEYKEY_ROOT}/DataSource/McBopomofo/BPMFMappings.txt"
                "${KEYKEY_ABSOLUTE_CIN}"
                --lexicon
                "${KEYKEY_ROOT}/DataSource/AISyntheticBigram/supplemental-lexicon.tsv"
                --lexicon
                "${KEYKEY_ROOT}/DataSource/AISyntheticBigram/numeric-unit-lexicon.tsv"
                ${KEYKEY_SMART_CORPORA}
        COMMAND "$<TARGET_FILE:KeyKeyDatabaseCooker>"
                --append-smart-sql
                "${KEYKEY_NATIVE_DATABASE}"
                "${KEYKEY_SMART_SQL}"
        COMMAND "${Python3_EXECUTABLE}"
                "${KEYKEY_SOURCE}/Distributions/Takao/DatabaseCooker/verify-smart-mandarin-db.py"
                "${KEYKEY_NATIVE_DATABASE}"
        COMMAND "${CMAKE_COMMAND}" -E touch "${KEYKEY_NATIVE_DATABASE_STAMP}"
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
            "${KEYKEY_SMART_COOKER}"
            "${KEYKEY_SOURCE}/Distributions/Takao/DatabaseCooker/verify-smart-mandarin-db.py"
            "${CMAKE_CURRENT_SOURCE_DIR}/GenerateSmartMandarinSql.rb"
            "${KEYKEY_ROOT}/DataSource/McBopomofo/BPMFMappings.txt"
            ${KEYKEY_SMART_LEXICONS}
            ${KEYKEY_SMART_CORPORA}
            "${KEYKEY_SOURCE}/Distributions/Takao/OnlineData/OneKey.plist"
            "${KEYKEY_SOURCE}/Distributions/Takao/OnlineData/CannedMessages.plist"
            ${KEYKEY_COLLECTION_INPUTS}
        COMMENT "Cooking KeyKey.db with the native Windows database cooker"
        VERBATIM
    )
    add_custom_target(keykey_database ALL DEPENDS "${KEYKEY_NATIVE_DATABASE_STAMP}")
    set(KEYKEY_DEPLOY_DATABASE "${KEYKEY_NATIVE_DATABASE}")
endif()

if(KEYKEY_DATABASE_PATH)
    add_custom_target(keykey_database ALL
        COMMAND "${Python3_EXECUTABLE}"
                "${KEYKEY_SOURCE}/Distributions/Takao/DatabaseCooker/verify-smart-mandarin-db.py"
                "${KEYKEY_DATABASE_PATH}"
        DEPENDS
            "${KEYKEY_DATABASE_PATH}"
            "${KEYKEY_SOURCE}/Distributions/Takao/DatabaseCooker/verify-smart-mandarin-db.py"
        VERBATIM)
endif()

add_library(KeyKeyTsf SHARED
    CandidateWindow.cpp
    ComServer.cpp
    Diagnostics.cpp
    LangBarButton.cpp
    KeyKeyTsf.rc
    TextService.cpp
    KeyKeyTsf.def
)
target_compile_features(KeyKeyTsf PRIVATE cxx_std_17)
target_compile_definitions(KeyKeyTsf PRIVATE
    ${KEYKEY_VERSION_DEFINITIONS}
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
    shcore
    shell32
    user32
    uuid
)

add_library(KeyKeySettingsBackend SHARED
    UserDataStore.cpp
    SettingsModern/SettingsBackend.cpp
)
target_compile_features(KeyKeySettingsBackend PRIVATE cxx_std_17)
target_compile_definitions(KeyKeySettingsBackend PRIVATE
    UNICODE
    _UNICODE
    WIN32_LEAN_AND_MEAN
    NOMINMAX
    _CRT_SECURE_NO_WARNINGS
)
if(MSVC)
    target_compile_options(KeyKeySettingsBackend PRIVATE /W4 /permissive- /utf-8)
endif()
target_link_libraries(KeyKeySettingsBackend PRIVATE
    keykey_core
    shell32
    user32
)
find_program(KEYKEY_DOTNET_EXECUTABLE dotnet REQUIRED)
if(CMAKE_SIZEOF_VOID_P EQUAL 8)
    set(KEYKEY_SETTINGS_RID win-x64)
else()
    set(KEYKEY_SETTINGS_RID win-x86)
endif()
file(GLOB KEYKEY_SETTINGS_SOURCES CONFIGURE_DEPENDS
    "${CMAKE_CURRENT_SOURCE_DIR}/SettingsModern/*.cs"
    "${CMAKE_CURRENT_SOURCE_DIR}/SettingsModern/*.xaml"
    "${CMAKE_CURRENT_SOURCE_DIR}/SettingsModern/*.csproj")
add_custom_target(KeyKeySettings ALL
    COMMAND "${KEYKEY_DOTNET_EXECUTABLE}" publish
            "${CMAKE_CURRENT_SOURCE_DIR}/SettingsModern/KeyKeySettings.csproj"
            --configuration Release --runtime ${KEYKEY_SETTINGS_RID} --self-contained true
            -p:PublishSingleFile=true
            -p:IncludeNativeLibrariesForSelfExtract=true
            -p:NuGetAudit=false
            -p:Version=${PROJECT_VERSION}
            --output "$<TARGET_FILE_DIR:KeyKeyTsf>"
    DEPENDS KeyKeySettingsBackend KeyKeyTsf ${KEYKEY_SETTINGS_SOURCES}
    VERBATIM
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
    # A language-model update can rebuild KeyKey.db without relinking the DLL.
    # Keep the runtime copy current in that case as well as on a fresh build.
    add_custom_target(keykey_database_deploy ALL
        COMMAND "${CMAKE_COMMAND}" -E make_directory
                "$<TARGET_FILE_DIR:KeyKeyTsf>/Databases"
        COMMAND "${CMAKE_COMMAND}" -E copy_if_different
                "${KEYKEY_DEPLOY_DATABASE}"
                "$<TARGET_FILE_DIR:KeyKeyTsf>/Databases/KeyKey.db"
        DEPENDS KeyKeyTsf keykey_database
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
    add_test(NAME KeyKeyEngineBopomofo COMMAND KeyKeyEngineSmokeTest legacy)
    add_test(NAME KeyKeyEngineEscapeKeep COMMAND KeyKeyEngineSmokeTest keep)
    add_test(NAME KeyKeyEngineEscapeClear COMMAND KeyKeyEngineSmokeTest clear)

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
install(TARGETS KeyKeySettingsBackend RUNTIME DESTINATION .)
install(FILES "$<TARGET_FILE_DIR:KeyKeyTsf>/KeyKeySettings.exe" DESTINATION .)
if(TARGET keykey_database OR EXISTS "${KEYKEY_DEPLOY_DATABASE}")
    install(FILES "${KEYKEY_DEPLOY_DATABASE}" DESTINATION Databases)
endif()
