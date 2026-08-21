cmake_minimum_required(VERSION 3.20)
project(StreetFighterEXPlusAlphaRecomp C CXX)

set(CMAKE_C_STANDARD 11)
set(CMAKE_CXX_STANDARD 17)
if(MSVC)
    set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} /std:c11 /experimental:c11atomics")
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} /FIalgorithm")
endif()

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
    message(STATUS "Configuring UWP AppX properties for psx-runtime")
    
    # Enable WinRT component property so VS packages it properly
    set_property(TARGET psx-runtime PROPERTY VS_WINRT_COMPONENT TRUE)
    
    # Add Package.appxmanifest to the project
    target_sources(psx-runtime PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/../UWP/Package.appxmanifest")
    set_property(SOURCE "${CMAKE_CURRENT_SOURCE_DIR}/../UWP/Package.appxmanifest" PROPERTY VS_DEPLOYMENT_CONTENT 1)

    # Copy and bundle configuration files
    file(COPY "${CMAKE_CURRENT_SOURCE_DIR}/../UWP/game.toml" DESTINATION "${CMAKE_CURRENT_BINARY_DIR}/")
    file(COPY "${CMAKE_CURRENT_SOURCE_DIR}/../UWP/input.ini" DESTINATION "${CMAKE_CURRENT_BINARY_DIR}/")

    target_sources(psx-runtime PRIVATE 
        "${CMAKE_CURRENT_BINARY_DIR}/game.toml"
        "${CMAKE_CURRENT_BINARY_DIR}/input.ini"
    )

    set_property(SOURCE "${CMAKE_CURRENT_BINARY_DIR}/game.toml" PROPERTY VS_DEPLOYMENT_CONTENT 1)
    set_property(SOURCE "${CMAKE_CURRENT_BINARY_DIR}/input.ini" PROPERTY VS_DEPLOYMENT_CONTENT 1)

    # Set the deployment location relative to Appx
    set_property(SOURCE "${CMAKE_CURRENT_BINARY_DIR}/game.toml" PROPERTY VS_DEPLOYMENT_LOCATION ".")
    set_property(SOURCE "${CMAKE_CURRENT_BINARY_DIR}/input.ini" PROPERTY VS_DEPLOYMENT_LOCATION ".")

    # Add Assets
    file(GLOB_RECURSE UWP_ASSETS "${CMAKE_CURRENT_SOURCE_DIR}/../UWP/Assets/*.*")
    target_sources(psx-runtime PRIVATE ${UWP_ASSETS})
    foreach(ASSET_FILE ${UWP_ASSETS})
        set_property(SOURCE ${ASSET_FILE} PROPERTY VS_DEPLOYMENT_CONTENT 1)
        set_property(SOURCE ${ASSET_FILE} PROPERTY VS_DEPLOYMENT_LOCATION "Assets")
    endforeach()
endif()
