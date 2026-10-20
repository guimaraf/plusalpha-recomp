#include "host_nameplates.h"
#include "player_nameplates_text.h"
#include <cstdio>
#include <mutex>

extern "C" uint8_t psx_read_byte(uint32_t addr);
namespace {
std::mutex snapshot_mutex;
PsxHostNameplates published{};
bool enabled = false;
bool hud_seen_in_match = false;
bool hud_packet_seen = false;
uint64_t previous_frame = 0;

void set_names(const char *left, const char *right) {
    const char *names[2] = {left, right};
    std::lock_guard<std::mutex> guard(snapshot_mutex);
    for (unsigned i = 0; i < 2; ++i) {
        auto clean = plusalpha::display_player_name(names[i] ? names[i] : "");
        if (clean.empty()) clean = i ? "Play 2" : "Play 1";
        std::snprintf(published.names[i], sizeof(published.names[i]), "%s", clean.c_str());
    }
}
int configure(int requested) {
    enabled = requested != 0;
    hud_seen_in_match = hud_packet_seen = false;
    previous_frame = 0;
    {
        std::lock_guard<std::mutex> guard(snapshot_mutex);
        published = {};
    }
    set_names(nullptr, nullptr);
    if (enabled)
        std::fprintf(stdout, "plusalpha: nameplates enabled [%s] [%s]\n",
                     published.names[0], published.names[1]);
    return enabled;
}
void observe(const uint32_t *w, unsigned n) {
    if (!enabled || n < 5) return;
    const auto op = w[0] >> 24;
    if (op != 0x28 && op != 0x38) return;
    if (op == 0x38 && n < 8) return;
    const unsigned b = op == 0x38 ? 3 : 2;
    const unsigned c = op == 0x38 ? 5 : 3;
    const unsigned d = op == 0x38 ? 7 : 4;
    if ((w[1] >> 16) != 26 || (w[b] >> 16) != 26 ||
        (w[c] >> 16) != 32 || (w[d] >> 16) != 32) return;
    const unsigned x1 = w[1] & 0xFFFF, x2 = w[b] & 0xFFFF;
    // Include the lost-health background: a KO removes the empty fill quad.
    if ((op == 0x28 && (w[0] & 0xFFFFFF) == 0x400000 && x1 == 14 && x2 <= 214) ||
        (op == 0x38 && ((x2 == 214 && x1 >= 14 && x1 <= 214) ||
                       (x1 == 300 && x2 >= 300 && x2 <= 500))))
        hud_packet_seen = true;
}
void tick(uint64_t frame) {
    if (!enabled) return;
    // SLUS-00548: 1 = match scene; 0 = character select; 7 = mode select.
    // Keep the match latch through replay, where the life HUD is not emitted.
    const bool match_scene = psx_read_byte(0x801D39B8u) == 1;
    if (!match_scene || frame < previous_frame) hud_seen_in_match = false;
    if (match_scene && hud_packet_seen) hud_seen_in_match = true;
    hud_packet_seen = false;
    previous_frame = frame;
    std::lock_guard<std::mutex> guard(snapshot_mutex);
    published.visible = match_scene && hud_seen_in_match;
}
void snapshot(PsxHostNameplates *out) {
    std::lock_guard<std::mutex> guard(snapshot_mutex);
    *out = published;
}
const PsxHostNameplateProvider provider{configure, tick, observe, snapshot, set_names};
struct Register {
    Register() { psx_host_nameplates_register(&provider); }
} registration;
}
