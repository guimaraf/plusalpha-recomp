#ifndef PLUSALPHA_VERSUS_SCORE_STATE_H
#define PLUSALPHA_VERSUS_SCORE_STATE_H
#include <cstdint>
#include <limits>
namespace plusalpha {
// SLUS-00548: func_80109400 commits a full-match result at PC 0x80109438.
// func_80109864 qualifies scoring with bit 0x400 set and bit 0x40 clear.
struct VersusScoreState {
    uint32_t wins[2]{};
    bool result_latched = false;
    void reset(uint32_t flags = 0) {
        wins[0] = wins[1] = 0;
        result_latched = (flags & 0x400u) != 0;
    }
    void step(uint8_t scene, uint8_t mode, uint32_t flags) {
        if (scene == 7 || mode != 1) { reset(flags); return; }
        if (!(flags & 0x400u)) result_latched = false;
        if (scene != 1 || !(flags & 0x400u) || result_latched) return;
        result_latched = true;
        if (flags & 0x40u) return; // Native non-scoring result.
        auto &value = wins[(flags >> 4) & 1u];
        if (value != std::numeric_limits<uint32_t>::max()) ++value;
    }
    void save(uint8_t out[16]) const {
        const uint32_t fields[4] = {1u, wins[0], wins[1], result_latched ? 1u : 0u};
        for (unsigned i = 0; i < 4; ++i)
            for (unsigned b = 0; b < 4; ++b)
                out[i * 4 + b] = static_cast<uint8_t>(fields[i] >> (8 * b));
    }
    static uint32_t word(const uint8_t *p) {
        return uint32_t(p[0]) | (uint32_t(p[1]) << 8) |
               (uint32_t(p[2]) << 16) | (uint32_t(p[3]) << 24);
    }
    static bool validate(const uint8_t *p, uint32_t len) {
        return p && len == 16 && word(p) == 1 && word(p + 12) <= 1;
    }
    void load(const uint8_t *p) {
        wins[0] = word(p + 4); wins[1] = word(p + 8);
        result_latched = word(p + 12) != 0;
    }
};
}
#endif
