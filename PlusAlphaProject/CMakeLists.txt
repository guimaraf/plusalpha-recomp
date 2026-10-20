cmake_minimum_required(VERSION 3.24)
project(StreetFighterEXPlusAlphaRecomp C CXX)

set(CMAKE_C_STANDARD 11)
set(CMAKE_CXX_STANDARD 17)
set(PSXRECOMP_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../psxrecomp" CACHE PATH "PSXRecomp framework")
set(RECOMP_UI_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../recomp-ui" CACHE PATH "Shared launcher")
# This title is qualified against the owner's SCPH-1001 dump, not OpenBIOS.
# Override an earlier build cache too: only this backend may enter the registry.
set(PSXRECOMP_BIOS_STEMS "SCPH1001" CACHE STRING "Required retail BIOS backend" FORCE)
set(PSXRECOMP_BIOS_STEM "SCPH1001" CACHE STRING "Primary BIOS backend" FORCE)
set(PSXRECOMP_BIOS_PROFILE "${PSXRECOMP_ROOT}/bios/SCPH1001.toml" CACHE FILEPATH "Retail BIOS profile" FORCE)
option(PSX_NETPLAY "Enable online lobby and rollback" ON)
option(PSX_RECOMP_UI "Build the shared launcher" ON)
option(PSX_SETUP_WIZARD "Enable local generation wizard" ON)
option(BUILD_DECOUPLED_LAUNCHER "Build the official setup host without game C" OFF)
set(PSX_NET_LOBBY_DEFAULT_URL "ws://netplay.retcomm.net:8765" CACHE STRING "Default lobby server")
set(PSX_STATIC_OVERLAY_DIR "${CMAKE_CURRENT_SOURCE_DIR}/generated-online/retained-overlays" CACHE PATH "Verified retained static sources")
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
if(NOT BUILD_DECOUPLED_LAUNCHER)
    if(NOT PSX_STATIC_OVERLAY_DIR)
        message(FATAL_ERROR "This port requires the retained promotion set. Run tools/build_online.ps1.")
    endif()
    file(REAL_PATH "${PSX_STATIC_OVERLAY_DIR}" _static_dir)
    if(NOT EXISTS "${_static_dir}/retained_coverage.json")
        message(FATAL_ERROR "Missing retained coverage receipt. Run tools/build_online.ps1.")
    endif()
    file(READ "${_static_dir}/retained_coverage.json" _receipt)
    string(JSON _units GET "${_receipt}" translation_units)
    string(JSON _entries GET "${_receipt}" manifest_entries)
    string(JSON _dlls GET "${_receipt}" dlls)
    string(JSON _file_count LENGTH "${_receipt}" files)
    string(JSON _native_changes GET "${_receipt}" native_code_changes)
    string(JSON _current_dispatcher GET "${_receipt}" dispatcher_regenerated)
    if(NOT _units EQUAL 2086 OR NOT _entries EQUAL 4748 OR NOT _dlls EQUAL 2219 OR NOT _file_count EQUAL 2087)
        message(FATAL_ERROR "Incomplete retained static coverage.")
    endif()
    if(_native_changes OR NOT _current_dispatcher)
        message(FATAL_ERROR "Expected preserved native bodies and a current dispatcher.")
    endif()
    math(EXPR _last "${_file_count} - 1")
    foreach(_index RANGE 0 ${_last})
        string(JSON _file GET "${_receipt}" files ${_index} file)
        string(JSON _expected_hash GET "${_receipt}" files ${_index} sha256)
        if(NOT _file MATCHES "^overlays_static(_[0-9][0-9][0-9][0-9])?[.]c$")
            message(FATAL_ERROR "Invalid retained source name: ${_file}")
        endif()
        file(SHA256 "${_static_dir}/${_file}" _actual_hash)
        if(NOT _actual_hash STREQUAL _expected_hash)
            message(FATAL_ERROR "Retained source changed: ${_file}. Re-run preparation.")
        endif()
    endforeach()
    file(GLOB _retained_units "${_static_dir}/overlays_static_[0-9][0-9][0-9][0-9].c")
    list(LENGTH _retained_units _actual_units)
    if(NOT _actual_units EQUAL 2086)
        message(FATAL_ERROR "Unexpected retained source set (${_actual_units} units).")
    endif()
    set_source_files_properties(${_retained_units} PROPERTIES COMPILE_DEFINITIONS "PSX_NO_DEBUG_TOOLS=1")
    message(STATUS "Retained static coverage verified: 2219 DLLs, 2086 C units, 4748 manifest entries")
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
target_sources(psx-runtime PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/player_nameplates.cpp")
if(MINGW)
    target_link_options(psx-runtime PRIVATE "-Wl,--export-all-symbols")
endif()
add_custom_command(TARGET psx-runtime POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
        "${CMAKE_CURRENT_SOURCE_DIR}/game.toml" "$<TARGET_FILE_DIR:psx-runtime>/game.toml"
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
        "${CMAKE_CURRENT_SOURCE_DIR}/../sfexp.png" "$<TARGET_FILE_DIR:psx-runtime>/sfexp.png"
)
