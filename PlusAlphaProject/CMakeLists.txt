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

psxrecomp_add_runtime_target(psx-runtime
    GAME_GENERATED_FULL_C "${GAME_GENERATED_FULL}"
    GAME_GENERATED_DISPATCH_C "${GAME_GENERATED_DISPATCH}"
    DEBUG_PORT 4531
    WINDOW_TITLE "StreetFighterEXPlusAlphaRecomp"
    DEFAULT_GAME_CONFIG_PATH "game.toml"
)

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
