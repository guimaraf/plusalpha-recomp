#include "../../player_nameplates_text.h"
#include <cassert>
int main() {
    using plusalpha::display_player_name;
    assert(display_player_name(u8"🇧🇷 - Guimaraf") == "Guimaraf");
    assert(display_player_name(u8"🇺🇸 — PlayerNameLong") == "PlayerNa");
    assert(display_player_name("1234567890123") == "12345678");
    assert(display_player_name(u8"JoãoJoséÁÉ123") == u8"JoãoJosé");
    assert(display_player_name(u8"A\u0301BCDEFGHIJK") == u8"A\u0301BCDEFGH");
    assert(display_player_name("  Ana-Maria  ") == "Ana-Mari");
    assert(display_player_name("BR - Ana") == "BR - Ana");
    assert(display_player_name("A\nB\tC") == "ABC");
    assert(display_player_name(u8"🇧🇷 - ").empty());
    assert(display_player_name(std::string("A\xff") + "B") == "AB");
}
