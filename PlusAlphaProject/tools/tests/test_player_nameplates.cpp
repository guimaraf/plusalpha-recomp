#include "../../player_nameplates_text.h"
#include <cassert>
int main() {
    using plusalpha::display_player_name;
    assert(display_player_name(u8"🇧🇷 - Guimaraf") == "Guimaraf");
    assert(display_player_name(u8"🇺🇸 — PlayerNameLong") == "PlayerName");
    assert(display_player_name("1234567890123") == "1234567890");
    assert(display_player_name(u8"JoãoJoséÁÉ123") == u8"JoãoJoséÁÉ");
    assert(display_player_name(u8"A\u0301BCDEFGHIJK") == u8"A\u0301BCDEFGHIJ");
    assert(display_player_name("  Ana-Maria  ") == "Ana-Maria");
    assert(display_player_name("BR - Ana") == "BR - Ana");
    assert(display_player_name("A\nB\tC") == "ABC");
    assert(display_player_name(u8"🇧🇷 - ").empty());
    assert(display_player_name(std::string("A\xff") + "B") == "AB");
}
