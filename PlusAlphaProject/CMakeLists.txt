cmake_minimum_required(VERSION 3.20)
project(StreetFighterEXPlusAlphaRecomp C CXX)

set(CMAKE_C_STANDARD 11)
set(CMAKE_CXX_STANDARD 17)

set(PSXRECOMP_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../psxrecomp" CACHE PATH
    "Caminho para o snapshot independente do PSXRecomp")

if(NOT EXISTS "${PSXRECOMP_ROOT}/runtime/runtime.cmake")
    message(FATAL_ERROR
        "PSXRecomp não encontrado em '${PSXRECOMP_ROOT}'. "
        "Mantenha o framework no diretório irmão ../psxrecomp.")
endif()

include("${PSXRECOMP_ROOT}/runtime/runtime.cmake")

set(GAME_GENERATED_FULL
    "${CMAKE_CURRENT_SOURCE_DIR}/generated/SLUS_005.48_full.c")
set(GAME_GENERATED_DISPATCH
    "${CMAKE_CURRENT_SOURCE_DIR}/generated/SLUS_005.48_dispatch.c")

option(BUILD_DECOUPLED_LAUNCHER "Build decoupled clean-room launcher (0 proprietary bytes; loads game_core.dll dynamically)" OFF)
option(PSX_OVERLAY_PRELOAD_ALL "Map all cached overlay DLLs before gameplay (Windows experiment)" OFF)
set(PSX_STATIC_OVERLAY_DIR "" CACHE PATH "Generated static overlay experiment directory")
if(PSX_STATIC_OVERLAY_DIR)
    if(BUILD_DECOUPLED_LAUNCHER OR PSX_OVERLAY_PRELOAD_ALL)
        message(FATAL_ERROR "Static overlays require monolithic runtime without DLL preload")
    endif()
    include("${PSX_STATIC_OVERLAY_DIR}/sources.cmake")
    set_source_files_properties(${PSX_STATIC_OVERLAY_SOURCES} PROPERTIES
        COMPILE_DEFINITIONS "PSX_NO_DEBUG_TOOLS=1")
endif()
if(PSX_OVERLAY_PRELOAD_ALL AND (NOT WIN32 OR BUILD_DECOUPLED_LAUNCHER))
    message(FATAL_ERROR "PSX_OVERLAY_PRELOAD_ALL requires the Windows monolithic runtime")
endif()

if(BUILD_DECOUPLED_LAUNCHER)
    # Decoupled clean-room launcher target: 0 bytes of proprietary game code.
    # The game core is compiled dynamically from extracted disc C via embedded TinyCC.
    psxrecomp_add_runtime_target(exPlusAlpha
        DEBUG_PORT 4531
        WINDOW_TITLE "Ex Plus Alpha"
        EXE_NAME "exPlusAlpha"
        DEFAULT_GAME_CONFIG_PATH "game.toml"
    )

    set_target_properties(exPlusAlpha PROPERTIES
        ENABLE_EXPORTS TRUE
        WIN32_EXECUTABLE TRUE
        OUTPUT_NAME "exPlusAlpha"
    )

    if(MINGW)
        target_link_options(exPlusAlpha PRIVATE "-Wl,--export-all-symbols")
    endif()

    add_custom_command(TARGET exPlusAlpha POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
            "${CMAKE_CURRENT_SOURCE_DIR}/game.toml"
            "$<TARGET_FILE_DIR:exPlusAlpha>/game.toml"
        COMMAND ${CMAKE_COMMAND} -E make_directory
            "$<TARGET_FILE_DIR:exPlusAlpha>/compileBuild"
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
            "${CMAKE_CURRENT_SOURCE_DIR}/overlay_captures.json"
            "$<TARGET_FILE_DIR:exPlusAlpha>/compileBuild/overlay_captures.json"
        COMMAND ${CMAKE_COMMAND} -E copy_directory
            "${CMAKE_CURRENT_SOURCE_DIR}/overlay_toolchain"
            "$<TARGET_FILE_DIR:exPlusAlpha>/compileBuild/overlay_toolchain"
        COMMAND ${CMAKE_COMMAND} -E copy_directory
            "${CMAKE_CURRENT_SOURCE_DIR}/tools"
            "$<TARGET_FILE_DIR:exPlusAlpha>/compileBuild/tools"
        COMMAND ${CMAKE_COMMAND} -E copy_directory
            "${PSXRECOMP_ROOT}/runtime/include"
            "$<TARGET_FILE_DIR:exPlusAlpha>/compileBuild/psxrecomp/runtime/include"
        COMMAND ${CMAKE_COMMAND} -E make_directory
            "$<TARGET_FILE_DIR:exPlusAlpha>/compileBuild/psxrecomp/tools"
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
            "${PSXRECOMP_ROOT}/tools/compile_overlays.py"
            "$<TARGET_FILE_DIR:exPlusAlpha>/compileBuild/psxrecomp/tools/compile_overlays.py"
        COMMENT "Copying game config to launcher directory, and toolchain into compileBuild/"
    )

    if(WIN32)
        get_filename_component(_cxx_dir "${CMAKE_CXX_COMPILER}" DIRECTORY)
        find_file(RUNTIME_SDL2_DLL "SDL2.dll"
            PATHS
                "${_cxx_dir}"
                "C:/msys64/ucrt64/bin"
                "C:/msys64/mingw64/bin"
        )
        if(RUNTIME_SDL2_DLL)
            add_custom_command(TARGET exPlusAlpha POST_BUILD
                COMMAND ${CMAKE_COMMAND} -E copy_if_different
                    "${RUNTIME_SDL2_DLL}"
                    "$<TARGET_FILE_DIR:exPlusAlpha>/SDL2.dll"
                COMMENT "Copying SDL2.dll to $<TARGET_FILE_DIR:exPlusAlpha>"
            )
        endif()

        foreach(_dep libgcc_s_seh-1.dll libstdc++-6.dll libwinpthread-1.dll)
            if(EXISTS "${_cxx_dir}/${_dep}")
                add_custom_command(TARGET exPlusAlpha POST_BUILD
                    COMMAND ${CMAKE_COMMAND} -E copy_if_different
                        "${_cxx_dir}/${_dep}"
                        "$<TARGET_FILE_DIR:exPlusAlpha>/${_dep}"
                    COMMENT "Copying ${_dep} to $<TARGET_FILE_DIR:exPlusAlpha>"
                )
            endif()
        endforeach()
    endif()
else()
    # Monolithic full recompilation target (for telemetry & baseline gameplay)
    psxrecomp_add_runtime_target(psx-runtime
        GAME_GENERATED_FULL_C "${GAME_GENERATED_FULL}"
        GAME_GENERATED_DISPATCH_C "${GAME_GENERATED_DISPATCH}"
        GAME_OVERLAY_STATIC_C "${PSX_STATIC_OVERLAY_DISPATCH}"
        EXTRAS_SOURCES ${PSX_STATIC_OVERLAY_SOURCES}
        DEBUG_PORT 4531
        WINDOW_TITLE "Ex Plus Alpha"
        EXE_NAME "exPlusAlpha"
        DEFAULT_GAME_CONFIG_PATH "game.toml"
    )

    set_target_properties(psx-runtime PROPERTIES
        ENABLE_EXPORTS TRUE
        WIN32_EXECUTABLE TRUE
        OUTPUT_NAME "exPlusAlpha"
    )

    if(PSX_OVERLAY_PRELOAD_ALL)
        target_compile_definitions(psx-runtime PRIVATE PSX_OVERLAY_PRELOAD_ALL=1)
    endif()

    if(MINGW)
        target_link_options(psx-runtime PRIVATE "-Wl,--export-all-symbols")
    endif()

    if(WIN32)
        get_filename_component(_cxx_dir "${CMAKE_CXX_COMPILER}" DIRECTORY)
        find_file(RUNTIME_SDL2_DLL "SDL2.dll"
            PATHS
                "${_cxx_dir}"
                "C:/msys64/ucrt64/bin"
                "C:/msys64/mingw64/bin"
        )
        if(RUNTIME_SDL2_DLL)
            add_custom_command(TARGET psx-runtime POST_BUILD
                COMMAND ${CMAKE_COMMAND} -E copy_if_different
                    "${RUNTIME_SDL2_DLL}"
                    "$<TARGET_FILE_DIR:psx-runtime>/SDL2.dll"
                COMMENT "Copying SDL2.dll to $<TARGET_FILE_DIR:psx-runtime>"
            )
        endif()

        foreach(_dep libgcc_s_seh-1.dll libstdc++-6.dll libwinpthread-1.dll)
            if(EXISTS "${_cxx_dir}/${_dep}")
                add_custom_command(TARGET psx-runtime POST_BUILD
                    COMMAND ${CMAKE_COMMAND} -E copy_if_different
                        "${_cxx_dir}/${_dep}"
                        "$<TARGET_FILE_DIR:psx-runtime>/${_dep}"
                    COMMENT "Copying ${_dep} to $<TARGET_FILE_DIR:psx-runtime>"
                )
            endif()
        endforeach()
    endif()
endif()

set(PSX_APP_ICON "" CACHE FILEPATH "Windows executable and SDL window icon")
if(PSX_APP_ICON)
    if(NOT WIN32 OR CMAKE_SYSTEM_NAME STREQUAL "WindowsStore")
        message(FATAL_ERROR "PSX_APP_ICON requires a desktop Windows build")
    endif()
    if(NOT EXISTS "${PSX_APP_ICON}")
        message(FATAL_ERROR "Icon not found: ${PSX_APP_ICON}")
    endif()
    enable_language(RC)
    file(TO_CMAKE_PATH "${PSX_APP_ICON}" PSX_APP_ICON_RESOURCE_PATH)
    configure_file("${CMAKE_CURRENT_SOURCE_DIR}/../icon/exPlusAlpha.rc.in"
        "${CMAKE_CURRENT_BINARY_DIR}/exPlusAlpha.rc" @ONLY)
    set_source_files_properties("${CMAKE_CURRENT_BINARY_DIR}/exPlusAlpha.rc"
        PROPERTIES OBJECT_DEPENDS "${PSX_APP_ICON}")
    if(BUILD_DECOUPLED_LAUNCHER)
        target_sources(exPlusAlpha PRIVATE "${CMAKE_CURRENT_BINARY_DIR}/exPlusAlpha.rc")
    else()
        target_sources(psx-runtime PRIVATE "${CMAKE_CURRENT_BINARY_DIR}/exPlusAlpha.rc")
    endif()
endif()

if(CMAKE_SYSTEM_NAME STREQUAL "WindowsStore")
    message(STATUS "Configuring Xbox-only UWP AppX properties for psx-runtime")

    set_property(TARGET psx-runtime PROPERTY VS_WINRT_APPLICATION TRUE)
    set_property(TARGET psx-runtime PROPERTY WIN32_EXECUTABLE TRUE)
    target_sources(psx-runtime PRIVATE
        "${CMAKE_CURRENT_SOURCE_DIR}/../UWP/Package.appxmanifest"
        "${CMAKE_CURRENT_SOURCE_DIR}/../UWP/SDL_winrt_main_NonXAML.cpp"
    )
    set_property(SOURCE "${CMAKE_CURRENT_SOURCE_DIR}/../UWP/SDL_winrt_main_NonXAML.cpp"
                 PROPERTY COMPILE_OPTIONS "/ZW")
    set_property(SOURCE "${CMAKE_CURRENT_SOURCE_DIR}/../UWP/Package.appxmanifest"
                 PROPERTY VS_DEPLOYMENT_CONTENT 1)

    # These read-only package files seed LocalState/config on first launch.
    foreach(CONFIG_FILE game.toml settings.toml input.ini keybinds.ini)
        configure_file(
            "${CMAKE_CURRENT_SOURCE_DIR}/../UWP/${CONFIG_FILE}"
            "${CMAKE_CURRENT_BINARY_DIR}/${CONFIG_FILE}"
            COPYONLY)
        target_sources(psx-runtime PRIVATE
            "${CMAKE_CURRENT_BINARY_DIR}/${CONFIG_FILE}")
        set_property(SOURCE "${CMAKE_CURRENT_BINARY_DIR}/${CONFIG_FILE}"
                     PROPERTY VS_DEPLOYMENT_CONTENT 1)
        set_property(SOURCE "${CMAKE_CURRENT_BINARY_DIR}/${CONFIG_FILE}"
                     PROPERTY VS_DEPLOYMENT_LOCATION ".")
    endforeach()

    file(GLOB_RECURSE UWP_ASSETS "${CMAKE_CURRENT_SOURCE_DIR}/../UWP/Assets/*.*")
    target_sources(psx-runtime PRIVATE ${UWP_ASSETS})
    foreach(ASSET_FILE ${UWP_ASSETS})
        set_property(SOURCE ${ASSET_FILE} PROPERTY VS_DEPLOYMENT_CONTENT 1)
        set_property(SOURCE ${ASSET_FILE} PROPERTY VS_DEPLOYMENT_LOCATION "Assets")
    endforeach()
endif()
