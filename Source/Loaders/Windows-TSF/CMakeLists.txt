cmake_minimum_required(VERSION 3.25)

project(KeyKeyWindowsTsf VERSION 1.3.1 LANGUAGES C CXX)

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
    "${KEYKEY_ROOT}/Source/Distributions/Takao/CookedDatabase/KeyKey.db"
    CACHE FILEPATH "Path to the canonical shared KeyKey SQLite database")
if(KEYKEY_DATABASE_PATH AND NOT EXISTS "${KEYKEY_DATABASE_PATH}")
    message(FATAL_ERROR "KEYKEY_DATABASE_PATH does not exist: ${KEYKEY_DATABASE_PATH}")
endif()
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
    WindowsTableInputMethod.cpp
    "${KEYKEY_SOURCE}/Frameworks/OpenVanilla/Source/OVFrameworkInfo.cpp"
    "${KEYKEY_SOURCE}/Frameworks/PlainVanilla/Source/PVPropertyListExpat.cpp"
    "${KEYKEY_SOURCE}/Frameworks/Formosa/Source/Mandarin.cpp"
    "${KEYKEY_SOURCE}/Frameworks/Manjusri/Source/Node.cpp"
    "${KEYKEY_SOURCE}/ModulePackages/OVIMMandarin/OVIMTraditionalMandarin.cpp"
    "${KEYKEY_SOURCE}/ModulePackages/OVIMMandarin/OVIMSmartMandarin.cpp"
    "${KEYKEY_SOURCE}/ModulePackages/OVIMMandarin/OVAFAssociatedPhrase.cpp"
    "${KEYKEY_SOURCE}/ModulePackages/OVIMGeneric/OVIMGeneric.cpp"
    KeyKeyEngine.cpp
)
target_compile_features(keykey_core PUBLIC cxx_std_17)
target_compile_definitions(keykey_core PUBLIC
    OV_USE_SQLITE
    OVIMGENERIC_IDENTIFIER_PREFIX=\"Generic\"
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
    "${KEYKEY_SOURCE}/ModulePackages/OVIMGeneric"
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
    message(FATAL_ERROR
        "KEYKEY_DATABASE_PATH must name the pre-generated shared KeyKey.db")
endif()
add_custom_target(keykey_database ALL
    COMMAND "${Python3_EXECUTABLE}"
            "${KEYKEY_SOURCE}/Distributions/Takao/DatabaseCooker/verify-smart-mandarin-db.py"
            "${KEYKEY_DATABASE_PATH}"
    DEPENDS
        "${KEYKEY_DATABASE_PATH}"
        "${KEYKEY_SOURCE}/Distributions/Takao/DatabaseCooker/verify-smart-mandarin-db.py"
        "${KEYKEY_SOURCE}/Distributions/Takao/DatabaseCooker/smart_mandarin_model.py"
        "${KEYKEY_ROOT}/DataSource/AISyntheticBigram/smart-mandarin-model-manifest.json"
    VERBATIM)

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
    oleaut32
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

file(GLOB KEYKEY_DEPLOYMENT_SOURCES CONFIGURE_DEPENDS
    "${CMAKE_CURRENT_SOURCE_DIR}/Deployment/*.cs"
    "${CMAKE_CURRENT_SOURCE_DIR}/Deployment/*.csproj"
    "${CMAKE_CURRENT_SOURCE_DIR}/Deployment/*.manifest")
add_executable(KeyKeyRegistration RegistrationTool.cpp)
target_compile_features(KeyKeyRegistration PRIVATE cxx_std_17)
target_compile_definitions(KeyKeyRegistration PRIVATE UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX)
add_custom_target(KeyKeyDeployment ALL
    COMMAND "${KEYKEY_DOTNET_EXECUTABLE}" publish
            "${CMAKE_CURRENT_SOURCE_DIR}/Deployment/KeyKeyDeployment.csproj"
            --configuration Release --runtime ${KEYKEY_SETTINGS_RID} --self-contained true
            -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true
            -p:Version=${PROJECT_VERSION} -p:NuGetAudit=false
            --output "$<TARGET_FILE_DIR:KeyKeyTsf>"
    DEPENDS KeyKeyTsf KeyKeyRegistration ${KEYKEY_DEPLOYMENT_SOURCES}
        "${KEYKEY_ROOT}/DataSource/AISyntheticBigram/smart-mandarin-model-manifest.json"
    VERBATIM)
add_dependencies(KeyKeySettings KeyKeyDeployment)

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
    add_test(NAME KeyKeyDeploymentTransactions
        COMMAND "${KEYKEY_DOTNET_EXECUTABLE}" run
            --project "${CMAKE_CURRENT_SOURCE_DIR}/Deployment.Tests/Deployment.Tests.csproj"
            --configuration Release)
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
    target_link_libraries(KeyKeyTsfInterfaceSmokeTest PRIVATE ole32 oleaut32 uuid advapi32)
    add_dependencies(KeyKeyTsfInterfaceSmokeTest KeyKeyTsf)
    add_test(NAME KeyKeyTsfConfigureInterface COMMAND KeyKeyTsfInterfaceSmokeTest)

    add_executable(KeyKeyTsfSystemTrayTest TsfSystemTrayTest.cpp
        LangBarButton.cpp TextService.cpp CandidateWindow.cpp Diagnostics.cpp)
    target_compile_features(KeyKeyTsfSystemTrayTest PRIVATE cxx_std_17)
    target_compile_definitions(KeyKeyTsfSystemTrayTest PRIVATE UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX)
    if(MSVC)
        target_compile_options(KeyKeyTsfSystemTrayTest PRIVATE /W4 /permissive- /utf-8)
    endif()
    target_link_libraries(KeyKeyTsfSystemTrayTest PRIVATE keykey_core ole32 oleaut32 uuid advapi32 gdi32 shell32 shcore user32)
    add_dependencies(KeyKeyTsfSystemTrayTest KeyKeyTsf keykey_database_deploy)
    add_test(NAME KeyKeyTsfSystemTrayModes COMMAND KeyKeyTsfSystemTrayTest)

    add_executable(KeyKeySharedInputMethodTest SharedInputMethodTest.cpp)
    target_compile_features(KeyKeySharedInputMethodTest PRIVATE cxx_std_17)
    target_compile_definitions(KeyKeySharedInputMethodTest PRIVATE UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX)
    if(MSVC)
        target_compile_options(KeyKeySharedInputMethodTest PRIVATE /W4 /permissive- /utf-8)
    endif()
    target_link_libraries(KeyKeySharedInputMethodTest PRIVATE keykey_core ole32 oleaut32 uuid userenv)
    add_dependencies(KeyKeySharedInputMethodTest keykey_database_deploy)
    add_test(NAME KeyKeySharedInputMethodProcesses COMMAND KeyKeySharedInputMethodTest)
    add_test(NAME KeyKeySharedInputMethodAppContainer COMMAND KeyKeySharedInputMethodTest --container)

    add_executable(KeyKeyTsfRegistrationIntegrationTest TsfRegistrationIntegrationTest.cpp)
    target_compile_features(KeyKeyTsfRegistrationIntegrationTest PRIVATE cxx_std_17)
    target_compile_definitions(KeyKeyTsfRegistrationIntegrationTest PRIVATE UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX)
    if(MSVC)
        target_compile_options(KeyKeyTsfRegistrationIntegrationTest PRIVATE /W4 /permissive- /utf-8)
    endif()
    target_link_libraries(KeyKeyTsfRegistrationIntegrationTest PRIVATE ole32 uuid advapi32)
    add_dependencies(KeyKeyTsfRegistrationIntegrationTest KeyKeyTsf)
    add_test(NAME KeyKeyTsfRegistrationIsolated COMMAND KeyKeyTsfRegistrationIntegrationTest)

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

    add_executable(KeyKeyTableInputTest TableInputTest.cpp)
    target_compile_features(KeyKeyTableInputTest PRIVATE cxx_std_17)
    target_compile_definitions(KeyKeyTableInputTest PRIVATE UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX)
    if(MSVC)
        target_compile_options(KeyKeyTableInputTest PRIVATE /W4 /permissive- /utf-8)
    endif()
    target_link_libraries(KeyKeyTableInputTest PRIVATE keykey_core advapi32 gdi32 ole32 shell32 user32 uuid)
    add_dependencies(KeyKeyTableInputTest keykey_database_deploy)
    add_test(NAME KeyKeyTableInputBasics COMMAND KeyKeyTableInputTest basic)
    add_test(NAME KeyKeyTableLiveLookup COMMAND KeyKeyTableInputTest compose)
    add_test(NAME KeyKeyTableLegacyAlias COMMAND KeyKeyTableInputTest alias)
    add_test(NAME KeyKeyTableConcurrentLearning COMMAND KeyKeyTableInputTest dynamic)
    add_test(NAME KeyKeyTableSettingsAndUnicode COMMAND KeyKeyTableInputTest settings)
    add_test(NAME KeyKeySettingsPreferences
        COMMAND "${KEYKEY_DOTNET_EXECUTABLE}" run
            --project "${CMAKE_CURRENT_SOURCE_DIR}/SettingsModern.Tests/SettingsModern.Tests.csproj"
            --configuration Release)
    if(CMAKE_SIZEOF_VOID_P EQUAL 8)
        add_test(NAME KeyKeySettingsWpfControls
            COMMAND "${KEYKEY_DOTNET_EXECUTABLE}" run
                --project "${CMAKE_CURRENT_SOURCE_DIR}/SettingsModern.UiTests/SettingsModern.UiTests.csproj"
                --configuration Release "--property:KeyKeyRuntimeDirectory=$<TARGET_FILE_DIR:KeyKeyTsf>")
    endif()

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
install(FILES "$<TARGET_FILE_DIR:KeyKeyTsf>/KeyKeyDeployment.exe" DESTINATION .)
if(TARGET keykey_database OR EXISTS "${KEYKEY_DEPLOY_DATABASE}")
    install(FILES "${KEYKEY_DEPLOY_DATABASE}" DESTINATION Databases)
endif()
