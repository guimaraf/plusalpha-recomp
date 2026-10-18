#include "codegen_setup.h"
#include "psxrecomp_codegen_host.h"

static const PsxrecompCodegenHostConfig kCodegenConfig = {
    .display_name = "Street Fighter EX Plus Alpha",
    .project_root_env = "PLUSALPHA_PROJECT_ROOT",
    .build_dir_env = "PLUSALPHA_BUILD_DIR",
    .force_setup_env = "PLUSALPHA_FORCE_SETUP",
    .psxrecomp_cli_relpath = "../psxrecomp/psxrecomp_cli.py",
    .seed_cfg_relpath = "game.toml",
    .game_toml_relpath = "game.toml",
    .gen_marker_relpath = "generated-online/SLUS_005.48_dispatch.c",
    .build_dir_name = "build-online",
    .cmake_target = "psx-runtime",
    .exe_basename = "exPlusAlpha",
};

void psx_game_codegen_setup_apply(RecompLauncherCGameInfo* gi) {
    psxrecomp_codegen_host_apply(gi, &kCodegenConfig);
}
void psx_game_codegen_relaunch_or_exit(const char* disc_path) {
    psxrecomp_codegen_host_relaunch_or_exit(disc_path);
}
void psx_game_codegen_forward_if_built(int argc, char** argv) {
    psxrecomp_codegen_host_forward_if_built(&kCodegenConfig, argc, argv);
}
