cmake_minimum_required(VERSION 3.24)
project(StreetFighterEXPlusAlphaRecomp C CXX)

set(CMAKE_C_STANDARD 11)
set(CMAKE_CXX_STANDARD 17)
set(PSXRECOMP_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../psxrecomp" CACHE PATH "PSXRecomp framework")
set(RECOMP_UI_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../recomp-ui" CACHE PATH "Shared launcher")
option(PSX_NETPLAY "Enable online lobby and rollback" ON)
option(PSX_RECOMP_UI "Build the shared launcher" ON)
option(PSX_SETUP_WIZARD "Enable local generation wizard" ON)
option(BUILD_DECOUPLED_LAUNCHER "Build the official setup host without game C" OFF)
set(PSX_NET_LOBBY_DEFAULT_URL "ws://netplay.retcomm.net:8765" CACHE STRING "Default lobby server")
set(PSX_STATIC_OVERLAY_DIR "" CACHE PATH "Static overlays regenerated with this framework")
set(PSX_APP_ICON "${CMAKE_CURRENT_SOURCE_DIR}/../icon/alpha256.ico" CACHE FILEPATH "Application icon")

if(CMAKE_SYSTEM_NAME STREQUAL "WindowsStore")
    message(FATAL_ERROR "This migration targets desktop netplay. Use the versioned baseline for UWP.")
endif()
if(PSX_NETPLAY AND NOT PSX_RECOMP_UI)
    message(FATAL_ERROR "PSX_NETPLAY requires PSX_RECOMP_UI for the lobby.")
endif()
foreach(_dep "${PSXRECOMP_ROOT}/runtime/runtime.cmake"
             "${RECOMP_UI_ROOT}/recomp_ui.cmake")
    if(NOT EXISTS "${_dep}")
        message(FATAL_ERROR "Missing ${_dep}. Run git submodule update --init --recursive.")
    endif()
endforeach()
if(PSX_NETPLAY)
    foreach(_dep "${PSXRECOMP_ROOT}/lib/recomp-net/CMakeLists.txt"
                 "${PSXRECOMP_ROOT}/lib/retcomm-rbengine/CMakeLists.txt")
        if(NOT EXISTS "${_dep}")
            message(FATAL_ERROR "Missing ${_dep}. Run git submodule update --init --recursive.")
        endif()
    endforeach()
endif()

# Keep the old S1-309 generated C and caches separate: their ABI differs.
set(_generated "${CMAKE_CURRENT_SOURCE_DIR}/generated-online")
set(_dispatch "${_generated}/SLUS_005.48_dispatch.c")
if(BUILD_DECOUPLED_LAUNCHER)
    set(PSXRECOMP_FORCE_SETUP_HOST ON CACHE BOOL "Build setup host" FORCE)
else()
    set(PSXRECOMP_FORCE_SETUP_HOST OFF CACHE BOOL "Build setup host" FORCE)
    set(PSXRECOMP_REQUIRE_GAME_C ON CACHE BOOL "Require current game C" FORCE)
    if(NOT EXISTS "${_dispatch}")
        message(FATAL_ERROR "Generate current sources into generated-online first. See ONLINE.md. Do not reuse S1-309 generated/.")
    endif()
endif()

set(_overlay_args)
if(PSX_STATIC_OVERLAY_DIR)
    file(REAL_PATH "${PSX_STATIC_OVERLAY_DIR}" _static_dir)
    if(_static_dir MATCHES "[Ss]1[-_]309")
        message(FATAL_ERROR "S1-309 overlays use the old ABI. Regenerate with this framework.")
    endif()
    if(NOT EXISTS "${_static_dir}/overlays_static.c")
        message(FATAL_ERROR "PSX_STATIC_OVERLAY_DIR must contain current overlays_static.c and shards.")
    endif()
    list(APPEND _overlay_args GAME_OVERLAY_STATIC_C "${_static_dir}/overlays_static.c")
endif()

include("${PSXRECOMP_ROOT}/runtime/runtime.cmake")
if(PSX_NETPLAY AND (NOT PSXRECOMP_HAS_RECOMP_NET OR NOT PSXRECOMP_HAS_RBENGINE OR NOT PSXRECOMP_HAS_LOBBY_CLIENT))
    message(FATAL_ERROR "Online requested but the complete transport, rollback and lobby stack is unavailable.")
endif()
psxrecomp_add_game_runtime(psx-runtime
    GEN_MARKER "${_dispatch}"
    GEN_FULL_GLOB "${_generated}/SLUS_005.48_full_*.c"
    GEN_FULL_FALLBACK "${_generated}/SLUS_005.48_full.c"
    VERSION_FILE "${CMAKE_CURRENT_SOURCE_DIR}/VERSION"
    MAX_PLAYERS 2
    DEBUG_PORT 4531
    WINDOW_TITLE "Ex Plus Alpha"
    EXE_NAME "exPlusAlpha"
    APP_ICON "${PSX_APP_ICON}"
    DEFAULT_GAME_CONFIG_PATH "game.toml"
    PRELOADED_MODS_DIR NONE
    NETPLAY_LOBBY_URL "${PSX_NET_LOBBY_DEFAULT_URL}"
    ${_overlay_args}
    CODEGEN_SETUP_SOURCES "${CMAKE_CURRENT_SOURCE_DIR}/codegen_setup.c"
)
set_target_properties(psx-runtime PROPERTIES ENABLE_EXPORTS TRUE WIN32_EXECUTABLE TRUE)
if(MINGW)
    target_link_options(psx-runtime PRIVATE "-Wl,--export-all-symbols")
endif()
add_custom_command(TARGET psx-runtime POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
        "${CMAKE_CURRENT_SOURCE_DIR}/game.toml" "$<TARGET_FILE_DIR:psx-runtime>/game.toml"
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
        "${CMAKE_CURRENT_SOURCE_DIR}/../sfexp.png" "$<TARGET_FILE_DIR:psx-runtime>/sfexp.png"
)
