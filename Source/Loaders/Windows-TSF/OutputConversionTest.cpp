#include "OutputConversion.h"
#include <iostream>
using KeyKey::WindowsTsf::ConvertOutput;
int main() {
    const std::wstring original = L"\x81FA\x7063\x8F38\x5165\x6CD5\xFF0C ABC 123 \xD83D\xDE00 \xD840\xDC00";
    const std::wstring expected = L"\x53F0\x6E7E\x8F93\x5165\x6CD5\xFF0C ABC 123 \xD83D\xDE00 \xD840\xDC00";
    if (ConvertOutput(original, false) != original || ConvertOutput(original, true) != expected ||
        ConvertOutput(expected, true) != expected || ConvertOutput(L"", true) != L"") {
        std::cerr << "Output conversion table or untouched characters failed\n"; return 1;
    }
    // The same output policy handles explicit symbol strings containing Chinese.
    const std::wstring message = L"v(\xFFE3\xFE36\xFFE3)y \x5F97\x610F\x3001YA~";
    if (ConvertOutput(message, true) != message) { std::cerr << "Symbol preservation failed\n"; return 1; }
    const std::wstring punctuation = L"\xFE30\xFE31\xFE35\xFF02\xFF07\xFFE2\xFFE4";
    if (ConvertOutput(punctuation, true) != punctuation) {
        std::cerr << "Conversion must preserve original punctuation widths\n"; return 1;
    }
    std::cout << "Output conversion tests passed\n";
}
