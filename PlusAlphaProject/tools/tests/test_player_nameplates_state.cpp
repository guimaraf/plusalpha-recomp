#include "host_nameplates.h"
#include <cassert>
#include <initializer_list>
#include <string>
static uint8_t scene;
static uint8_t mode = 1;
static uint32_t result_flags;
extern "C" uint32_t psx_read_word(uint32_t addr) {
    assert(addr == 0x801D39E4u);
    return result_flags;
}
const PsxHostNameplateProvider *g_psx_nameplate_provider;
extern "C" void psx_host_nameplates_register(const PsxHostNameplateProvider *p) {
    g_psx_nameplate_provider = p;
}
extern "C" uint8_t psx_read_byte(uint32_t addr) {
    assert(addr == 0x801D39B8u || addr == 0x801DC9D0u);
    return addr == 0x801D39B8u ? scene : mode;
}
int main() {
    auto p = g_psx_nameplate_provider;
    assert(p && !p->configure(0));
    // Activation no longer depends on a preview file in the distribution.
    assert(p->configure(1));
    PsxHostNameplates snapshot{};
    p->snapshot(&snapshot);
    assert(std::string(snapshot.names[0]) == "Play 1");
    assert(std::string(snapshot.names[1]) == "Play 2");
    assert(!snapshot.visible);
    p->set_names(u8"🇧🇷 - Fred", "Felipe");
    p->snapshot(&snapshot);
    assert(std::string(snapshot.names[0]) == "Fred");
    assert(std::string(snapshot.names[1]) == "Felipe");
    p->set_names("1234567890123", "");
    p->snapshot(&snapshot);
    assert(std::string(snapshot.names[0]) == "12345678");
    assert(std::string(snapshot.names[1]) == "Play 2");
    p->set_names(nullptr, nullptr);
    p->snapshot(&snapshot);
    assert(std::string(snapshot.names[0]) == "Play 1");
    assert(std::string(snapshot.names[1]) == "Play 2");
    p->set_names("Fred", "Felipe");
    const uint32_t fill[] = {0x3800FFFF, 0x001A012C, 0x0000FF9B, 0x001A01F4,
                             0x0000FFFF, 0x00200125, 0x0000FF9B, 0x002001ED};
    scene = 1;
    p->observe_gp0(fill, 8); p->tick(1); p->snapshot(&snapshot); assert(snapshot.visible);
    p->tick(2); p->snapshot(&snapshot); assert(snapshot.visible); // replay retains labels
    assert(std::string(snapshot.names[0]) == "Fred");
    assert(std::string(snapshot.names[1]) == "Felipe");
    scene = 0;
    p->tick(3); p->snapshot(&snapshot); assert(!snapshot.visible); // character select
    scene = 1;
    p->tick(4); p->snapshot(&snapshot); assert(!snapshot.visible); // no stale match
    const uint32_t empty[] = {0x28400000, 0x001A000E, 0x001A00D6, 0x00200014, 0x002000DC};
    p->observe_gp0(empty, 5); p->tick(5); p->snapshot(&snapshot); assert(snapshot.visible);
    p->tick(1); p->snapshot(&snapshot); assert(!snapshot.visible); // restore clears latch
    const uint32_t wrong[] = {0x28400000, 0x001B000E, 0x001A00D6, 0x00200014, 0x002000DC};
    p->observe_gp0(wrong, 5); p->tick(2); p->snapshot(&snapshot); assert(!snapshot.visible);
    // Disable after a visible match, then re-enable: no stale visibility/names.
    p->observe_gp0(fill, 8); p->tick(3); p->snapshot(&snapshot); assert(snapshot.visible);
    assert(!p->configure(0));
    p->observe_gp0(fill, 8); p->tick(4); p->snapshot(&snapshot); assert(!snapshot.visible);
    assert(p->configure(1));
    p->tick(5); p->snapshot(&snapshot); assert(!snapshot.visible);
    assert(std::string(snapshot.names[0]) == "Play 1");
    assert(std::string(snapshot.names[1]) == "Play 2");
    // Identical life HUDs in other modes must not enable labels.
    scene = 1;
    for (uint8_t other : {0, 2, 3, 4, 5, 6, 7, 8, 9, 255}) {
        mode = other;
        p->observe_gp0(fill, 8); p->tick(10); p->snapshot(&snapshot);
        assert(!snapshot.visible);
    }
    mode = 1;
    p->observe_gp0(fill, 8); p->tick(11); p->snapshot(&snapshot);
    assert(snapshot.visible);
    // Mode remains Versus in RAM after returning to mode select.
    scene = 7;
    p->observe_gp0(fill, 8); p->tick(12); p->snapshot(&snapshot);
    assert(!snapshot.visible);
    scene = 0;
    p->tick(13); p->snapshot(&snapshot); assert(!snapshot.visible);
    scene = 1;
    p->tick(14); p->snapshot(&snapshot); assert(!snapshot.visible);
    p->observe_gp0(fill, 8); p->tick(15); p->snapshot(&snapshot); assert(snapshot.visible);
    // A restore can change mode with no entry/exit PC and no frame decrease.
    mode = 5;
    p->observe_gp0(fill, 8); p->tick(16); p->snapshot(&snapshot); assert(!snapshot.visible);
    mode = 1;
    p->tick(17); p->snapshot(&snapshot); assert(!snapshot.visible);
    p->observe_gp0(fill, 8); p->tick(18); p->snapshot(&snapshot); assert(snapshot.visible);
    // Full-match results, independent of the native streak and HUD switch.
    p->begin_session();
    auto step = [&](uint8_t next_scene, uint32_t flags) {
        scene = next_scene; result_flags = flags;
        p->simulation_tick(); p->tick(20); p->snapshot(&snapshot);
    };
    step(1, 0x83); // Intermediate round: no completed-match bit.
    assert(snapshot.wins[0] == 0 && snapshot.wins[1] == 0);
    uint8_t before_result[16], after_result[16];
    p->save_state(before_result);
    step(1, 0x683); // Captured P1 final result.
    assert(snapshot.wins[0] == 1 && snapshot.wins[1] == 0);
    p->save_state(after_result);
    assert(p->validate_state(after_result, 16));
    assert(!p->validate_state(after_result, 15));
    uint8_t malformed[16]{};
    assert(!p->validate_state(malformed, 16));
    for (int i = 0; i < 60; ++i) step(1, 0x683); // Replay/held result.
    step(0, 0x683); step(1, 0x683); // Character select cannot recount it.
    assert(snapshot.wins[0] == 1 && snapshot.wins[1] == 0);
    step(1, 0x8B); step(1, 0x69F); // P2 wins next: accumulated 1 x 1.
    assert(snapshot.wins[0] == 1 && snapshot.wins[1] == 1);
    step(1, 0); step(1, 0x440); // Non-scoring/draw.
    assert(snapshot.wins[0] == 1 && snapshot.wins[1] == 1);
    // Roll back an unconfirmed P1 win, then replay a corrected P2 result.
    p->load_state(before_result);
    step(1, 0x69F);
    assert(snapshot.wins[0] == 0 && snapshot.wins[1] == 1);
    p->load_state(after_result); step(1, 0x683);
    assert(snapshot.wins[0] == 1 && snapshot.wins[1] == 0);
    // A successful manual load/disconnect consumes an already-held result.
    p->reset_score(); step(1, 0x683);
    assert(snapshot.wins[0] == 0 && snapshot.wins[1] == 0);
    step(1, 0); step(1, 0x683);
    step(7, 0x683); step(0, 0x683); step(1, 0x683);
    assert(snapshot.wins[0] == 0 && snapshot.wins[1] == 0);
    p->configure(0);
    step(1, 0); step(1, 0x69F);
    p->configure(1); p->tick(21); p->snapshot(&snapshot);
    assert(snapshot.wins[0] == 0 && snapshot.wins[1] == 1);
    mode = 5; step(1, 0x683);
    assert(snapshot.wins[0] == 0 && snapshot.wins[1] == 0);
    // No overflow at the external counter's limit.
    mode = 1;
    uint8_t maximum[16] = {1,0,0,0,255,255,255,255};
    assert(p->validate_state(maximum, 16)); p->load_state(maximum);
    step(1, 0); step(1, 0x683);
    assert(snapshot.wins[0] == UINT32_MAX && snapshot.wins[1] == 0);
}
