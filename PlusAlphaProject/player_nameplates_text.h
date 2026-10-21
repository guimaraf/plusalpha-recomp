#pragma once
#include <cstdint>
#include <string>

namespace plusalpha {
// Decode before truncating: a UTF-8 byte is not a display character.
inline uint32_t name_codepoint(const std::string& text, size_t& at) {
    const auto first = static_cast<unsigned char>(text[at++]);
    if (first < 0x80) return first;
    unsigned extra = first >= 0xF0 && first <= 0xF4 ? 3 :
                     first >= 0xE0 && first <= 0xEF ? 2 :
                     first >= 0xC2 && first <= 0xDF ? 1 : 0;
    if (!extra || at + extra > text.size()) return 0xFFFD;
    uint32_t cp = first & ((1u << (6 - extra)) - 1);
    for (unsigned i = 0; i < extra; ++i) {
        const unsigned char c = text[at];
        if ((c & 0xC0) != 0x80) return 0xFFFD;
        ++at;
        cp = (cp << 6) | (c & 0x3F);
    }
    if ((extra == 1 && cp < 0x80) || (extra == 2 && cp < 0x800) ||
        (extra == 3 && cp < 0x10000) || cp > 0x10FFFF ||
        (cp >= 0xD800 && cp <= 0xDFFF)) return 0xFFFD;
    return cp;
}
inline bool name_space(uint32_t cp) { return cp == ' ' || cp == '\t' || cp == 0xA0; }
inline std::string display_player_name(const std::string& raw) {
    size_t start = 0;
    while (start < raw.size()) {
        size_t next = start;
        if (!name_space(name_codepoint(raw, next))) break;
        start = next;
    }
    size_t next = start;
    const auto a = next < raw.size() ? name_codepoint(raw, next) : 0;
    const auto b = next < raw.size() ? name_codepoint(raw, next) : 0;
    if (a >= 0x1F1E6 && a <= 0x1F1FF && b >= 0x1F1E6 && b <= 0x1F1FF) {
        start = next;
        while (start < raw.size()) {
            next = start;
            const auto cp = name_codepoint(raw, next);
            if (!name_space(cp) && cp != '-' && cp != 0x2013 && cp != 0x2014 && cp != 0xFE0F) break;
            start = next;
        }
    }
    std::string result;
    unsigned characters = 0;
    for (size_t at = start; at < raw.size();) {
        const size_t before = at;
        const auto cp = name_codepoint(raw, at);
        if (cp < 0x20 || cp == 0x7F || cp == 0xFFFD) continue;
        // Preserve combining accents without counting them as another letter.
        const bool accent = cp >= 0x300 && cp <= 0x36F;
        if (!accent && characters == 8) break;
        if (accent && !characters) continue;
        if (result.size() + at - before > 60) break;
        if (!accent) ++characters;
        result.append(raw, before, at - before);
    }
    while (!result.empty() && result.back() == ' ') result.pop_back();
    return result;
}
}
