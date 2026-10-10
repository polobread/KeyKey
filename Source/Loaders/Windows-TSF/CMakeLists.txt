cmake_minimum_required(VERSION 3.25)

project(KeyKeyWindowsTsf VERSION 1.3.2 LANGUAGES C CXX)

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
    if(CMAKE_GENERATOR MATCHES "^Ninja")
        # Capture cl's localized pipe output without transcoding. The compiler
        # launcher below normalizes its prefix for Ninja's byte-based parser.
        set(KEYKEY_INCLUDE_PROBE "${CMAKE_CURRENT_BINARY_DIR}/CMakeFiles/KeyKeyHeaderDependencyProbe")
        file(WRITE "${KEYKEY_INCLUDE_PROBE}.h" "\n")
        file(WRITE "${KEYKEY_INCLUDE_PROBE}.c" "#include \"KeyKeyHeaderDependencyProbe.h\"\n")
        execute_process(COMMAND "${CMAKE_CXX_COMPILER}" /nologo /showIncludes /EP "${KEYKEY_INCLUDE_PROBE}.c"
            OUTPUT_VARIABLE KEYKEY_INCLUDE_OUTPUT ERROR_VARIABLE KEYKEY_INCLUDE_ERRORS
            RESULT_VARIABLE KEYKEY_INCLUDE_STATUS ENCODING NONE)
        string(REGEX MATCH "[^\r\n]*KeyKeyHeaderDependencyProbe.h" KEYKEY_INCLUDE_LINE
            "${KEYKEY_INCLUDE_OUTPUT}\n${KEYKEY_INCLUDE_ERRORS}")
        string(REGEX REPLACE "[A-Za-z]:[\\\\/].*" "" KEYKEY_INCLUDE_PREFIX "${KEYKEY_INCLUDE_LINE}")
        if(NOT KEYKEY_INCLUDE_STATUS EQUAL 0 OR NOT KEYKEY_INCLUDE_PREFIX OR
           KEYKEY_INCLUDE_PREFIX STREQUAL KEYKEY_INCLUDE_LINE)
            message(FATAL_ERROR "Cannot determine MSVC /showIncludes prefix for Ninja header dependencies")
        endif()
        set(KEYKEY_INCLUDE_PREFIX_FILE "${KEYKEY_INCLUDE_PROBE}.prefix")
        file(WRITE "${KEYKEY_INCLUDE_PREFIX_FILE}" "${KEYKEY_INCLUDE_PREFIX}")
        set(CMAKE_CL_SHOWINCLUDES_PREFIX "Note: including file: ")
        set(CMAKE_C_CL_SHOWINCLUDES_PREFIX "Note: including file: ")
        set(CMAKE_CXX_CL_SHOWINCLUDES_PREFIX "Note: including file: ")
    endif()
endif()

find_package(Python3 REQUIRED COMPONENTS Interpreter)
if(MSVC AND CMAKE_GENERATOR MATCHES "^Ninja")
    foreach(language C CXX)
        set(CMAKE_${language}_COMPILER_LAUNCHER "${Python3_EXECUTABLE}"
            "${CMAKE_CURRENT_SOURCE_DIR}/MsvcCompiler.py" "${KEYKEY_INCLUDE_PREFIX_FILE}"
            ${CMAKE_${language}_COMPILER_LAUNCHER})
    endforeach()
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
    Diagnostics.cpp
    FrontendSettings.cpp
    OutputConversion.cpp
    "${KEYKEY_SOURCE}/ModulePackages/OVOFHanConvert/OVOFHanConvert.cpp"
    "${KEYKEY_SOURCE}/ModulePackages/OVOFHanConvert/VXHCTC2SCTable.c"
    "${KEYKEY_SOURCE}/ModulePackages/OVOFHanConvert/VXHCSC2TCTable.c"
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
    KEYKEY_WINDOWS_SHARED_DATA
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
target_link_libraries(keykey_core PUBLIC keykey_third_party shcore)
set_target_properties(keykey_core PROPERTIES POSITION_INDEPENDENT_CODE ON)
if(MSVC)
    target_compile_options(keykey_core PRIVATE /utf-8)
endif()

set(KEYKEY_DEPLOY_DATABASE "${KEYKEY_DATABASE_PATH}")
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
    LangBarButton.cpp
    SymbolPanel.cpp
    KeyKeyTsf.rc
    TextService.cpp
    KeyKeyTsf.def
)
set(KEYKEY_SYMBOL_HEADER "${CMAKE_CURRENT_BINARY_DIR}/generated/SymbolResources.generated.h")
add_custom_command(OUTPUT "${KEYKEY_SYMBOL_HEADER}"
    COMMAND "${CMAKE_COMMAND}" -E make_directory "${CMAKE_CURRENT_BINARY_DIR}/generated"
    COMMAND powershell -NoProfile -ExecutionPolicy Bypass -File
        "${CMAKE_CURRENT_SOURCE_DIR}/Generate-SymbolResources.ps1" -Output "${KEYKEY_SYMBOL_HEADER}"
    DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/Generate-SymbolResources.ps1"
        "${KEYKEY_SOURCE}/Distributions/Takao/OnlineData/CannedMessages.plist"
        "${KEYKEY_SOURCE}/Loaders/iOS-Keyboard/KeyKeyEngine/Sources/KeyKeyEngine/BopomofoEngine.swift"
        "${CMAKE_CURRENT_SOURCE_DIR}/SymbolEmojiSupplement.json"
    VERBATIM)
add_custom_target(keykey_symbol_resources DEPENDS
    "${KEYKEY_SYMBOL_HEADER}")
add_dependencies(KeyKeyTsf keykey_symbol_resources)
target_include_directories(KeyKeyTsf BEFORE PRIVATE "${CMAKE_CURRENT_BINARY_DIR}/generated")
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
    d2d1 dwrite uxtheme
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
    ole32
    oleaut32
    uuid
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
    "${CMAKE_CURRENT_SOURCE_DIR}/SettingsModern/*.manifest"
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
    add_library(KeyKeyTsfLifetimeProbe SHARED ModuleLifetimeProbe.cpp
        ComServer.cpp LangBarButton.cpp TextService.cpp CandidateWindow.cpp SymbolPanel.cpp KeyKeyTsf.def)
    add_dependencies(KeyKeyTsfLifetimeProbe keykey_symbol_resources keykey_database_deploy)
    target_include_directories(KeyKeyTsfLifetimeProbe BEFORE PRIVATE "${CMAKE_CURRENT_BINARY_DIR}/generated")
    target_compile_options(KeyKeyTsfLifetimeProbe PRIVATE /utf-8)
    target_link_libraries(KeyKeyTsfLifetimeProbe PRIVATE keykey_core ole32 oleaut32 uuid advapi32 gdi32 shell32 shcore user32 d2d1 dwrite uxtheme)
    add_executable(KeyKeyModuleLifetimeTest ModuleLifetimeTest.cpp)
    target_compile_features(KeyKeyModuleLifetimeTest PRIVATE cxx_std_17)
    target_compile_options(KeyKeyModuleLifetimeTest PRIVATE /utf-8)
    target_compile_definitions(KeyKeyModuleLifetimeTest PRIVATE UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX)
    target_link_libraries(KeyKeyModuleLifetimeTest PRIVATE ole32 uuid user32 psapi)
    add_dependencies(KeyKeyModuleLifetimeTest KeyKeyTsfLifetimeProbe)
    add_test(NAME KeyKeyModuleLifetime COMMAND KeyKeyModuleLifetimeTest)
    set_tests_properties(KeyKeyModuleLifetime PROPERTIES RUN_SERIAL TRUE LABELS "dll-unload")
    # MSVC ASan does not support unloading instrumented DLLs. Runtime teardown
    # within one module is still covered by KeyKeyTsfOutputCommitBehavior.
    if(CMAKE_CXX_FLAGS MATCHES "fsanitize=address")
        set_tests_properties(KeyKeyModuleLifetime PROPERTIES DISABLED TRUE)
    endif()
    add_executable(KeyKeySharedDataProtectionTest SharedDataProtectionTest.cpp UserDataStore.cpp)
    target_link_libraries(KeyKeySharedDataProtectionTest PRIVATE keykey_core shell32 user32)
    target_compile_options(KeyKeySharedDataProtectionTest PRIVATE /utf-8)
    add_test(NAME KeyKeySharedDataProtection COMMAND KeyKeySharedDataProtectionTest)
    add_executable(KeyKeyDiagnosticsTest DiagnosticsTest.cpp)
    target_link_libraries(KeyKeyDiagnosticsTest PRIVATE keykey_core shell32 user32)
    add_test(NAME KeyKeyDiagnostics COMMAND KeyKeyDiagnosticsTest)
    add_executable(KeyKeyPopupLifecycleTest PopupLifecycleTest.cpp CandidateWindow.cpp SymbolPanel.cpp)
    add_dependencies(KeyKeyPopupLifecycleTest keykey_symbol_resources)
    target_include_directories(KeyKeyPopupLifecycleTest BEFORE PRIVATE "${CMAKE_CURRENT_BINARY_DIR}/generated")
    target_compile_features(KeyKeyPopupLifecycleTest PRIVATE cxx_std_17)
    target_compile_options(KeyKeyPopupLifecycleTest PRIVATE /utf-8)
    target_link_libraries(KeyKeyPopupLifecycleTest PRIVATE keykey_core ole32 oleaut32 uuid advapi32 gdi32 shell32 shcore user32 d2d1 dwrite uxtheme)
    add_test(NAME KeyKeyPopupLifecycle COMMAND KeyKeyPopupLifecycleTest)
    set_tests_properties(KeyKeyPopupLifecycle PROPERTIES RUN_SERIAL TRUE)
    add_executable(KeyKeyTsfOutputBehaviorTest TsfOutputBehaviorTest.cpp
        LangBarButton.cpp TextService.cpp CandidateWindow.cpp SymbolPanel.cpp)
    target_compile_features(KeyKeyTsfOutputBehaviorTest PRIVATE cxx_std_17)
    target_compile_definitions(KeyKeyTsfOutputBehaviorTest PRIVATE UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX)
    target_compile_options(KeyKeyTsfOutputBehaviorTest PRIVATE /utf-8)
    target_include_directories(KeyKeyTsfOutputBehaviorTest BEFORE PRIVATE "${CMAKE_CURRENT_BINARY_DIR}/generated")
    target_link_libraries(KeyKeyTsfOutputBehaviorTest PRIVATE keykey_core ole32 oleaut32 uuid advapi32 gdi32 shell32 shcore user32 d2d1 dwrite uxtheme)
    add_dependencies(KeyKeyTsfOutputBehaviorTest keykey_symbol_resources keykey_database_deploy)
    add_test(NAME KeyKeyTsfOutputCommitBehavior COMMAND KeyKeyTsfOutputBehaviorTest)
    add_executable(KeyKeyFrontendPreferencesTest FrontendPreferencesTest.cpp)
    target_link_libraries(KeyKeyFrontendPreferencesTest PRIVATE keykey_core)
    add_test(NAME KeyKeyFrontendPreferences COMMAND KeyKeyFrontendPreferencesTest)
    add_executable(KeyKeyEngineAdvancedSettingsTest EngineAdvancedSettingsTest.cpp)
    target_compile_options(KeyKeyEngineAdvancedSettingsTest PRIVATE /utf-8)
    target_link_libraries(KeyKeyEngineAdvancedSettingsTest PRIVATE keykey_core shell32 user32)
    add_dependencies(KeyKeyEngineAdvancedSettingsTest keykey_database_deploy)
    foreach(mode custom hsu eten26 invalid four-output)
        add_test(NAME KeyKeyEngineAdvanced-${mode} COMMAND KeyKeyEngineAdvancedSettingsTest ${mode})
    endforeach()
    add_executable(KeyKeySymbolPanelTest SymbolPanelTest.cpp SymbolPanel.cpp)
    add_dependencies(KeyKeySymbolPanelTest keykey_symbol_resources)
    target_include_directories(KeyKeySymbolPanelTest BEFORE PRIVATE
        "${CMAKE_CURRENT_BINARY_DIR}/generated" "${CMAKE_CURRENT_SOURCE_DIR}")
    target_compile_features(KeyKeySymbolPanelTest PRIVATE cxx_std_17)
    target_compile_definitions(KeyKeySymbolPanelTest PRIVATE UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX)
    target_link_libraries(KeyKeySymbolPanelTest PRIVATE keykey_core shell32 user32 gdi32 advapi32 d2d1 dwrite uxtheme)
    add_test(NAME KeyKeySymbolPanelResourcesAndFocus COMMAND KeyKeySymbolPanelTest)
    add_executable(KeyKeyOutputConversionTest OutputConversionTest.cpp)
    target_link_libraries(KeyKeyOutputConversionTest PRIVATE keykey_core)
    add_test(NAME KeyKeyOutputConversion COMMAND KeyKeyOutputConversionTest)
    add_executable(KeyKeySharedOutputStateTest SharedOutputStateTest.cpp)
    target_compile_features(KeyKeySharedOutputStateTest PRIVATE cxx_std_17)
    target_compile_definitions(KeyKeySharedOutputStateTest PRIVATE UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX)
    target_link_libraries(KeyKeySharedOutputStateTest PRIVATE ole32 oleaut32 uuid user32 userenv advapi32)
    add_test(NAME KeyKeySharedOutputStateProcesses COMMAND KeyKeySharedOutputStateTest)
    add_test(NAME KeyKeySharedOutputStateAppContainer COMMAND KeyKeySharedOutputStateTest --container)
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
        LangBarButton.cpp TextService.cpp CandidateWindow.cpp SymbolPanel.cpp)
    add_dependencies(KeyKeyTsfSystemTrayTest keykey_symbol_resources)
    target_include_directories(KeyKeyTsfSystemTrayTest BEFORE PRIVATE "${CMAKE_CURRENT_BINARY_DIR}/generated")
    target_compile_features(KeyKeyTsfSystemTrayTest PRIVATE cxx_std_17)
    target_compile_definitions(KeyKeyTsfSystemTrayTest PRIVATE UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX)
    if(MSVC)
        target_compile_options(KeyKeyTsfSystemTrayTest PRIVATE /W4 /permissive- /utf-8)
    endif()
    target_link_libraries(KeyKeyTsfSystemTrayTest PRIVATE keykey_core ole32 oleaut32 uuid advapi32 gdi32 shell32 shcore user32 d2d1 dwrite uxtheme)
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
    add_test(NAME KeyKeyEngineNumpad COMMAND KeyKeyEngineSmokeTest numpad)
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
