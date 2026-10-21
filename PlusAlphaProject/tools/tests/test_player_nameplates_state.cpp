#include "host_nameplates.h"
#include <cassert>
#include <initializer_list>
#include <string>
static uint8_t scene;
static uint8_t mode = 1;
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
}
