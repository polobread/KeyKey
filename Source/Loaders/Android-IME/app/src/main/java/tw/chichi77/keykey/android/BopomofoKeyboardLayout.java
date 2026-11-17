package tw.chichi77.keykey.android;

import java.util.List;

enum BopomofoKeyboardLayout {
    STANDARD("Standard", "standard", "標準", "1qaz2wsxedcrfv5tgbyhnujm8ik,9ol.0p;/-6347"),
    HSU("Hsu", "hsu", "許氏鍵盤", ""),
    HANYU_PINYIN("HanyuPinyin", "hanyu_pinyin", "漢語拼音", ""),
    ETEN("ETen", "eten", "倚天", "bpmfdtnlvkhg7c,./j;'sexuaorwiqzy890-=2341"),
    ETEN26("ETen26", "eten26", "倚天 26 鍵", "");

    // Display labels follow the one-to-one Standard and ETen mappings in Guanyinma.
    private static final String SYMBOLS = "ㄅㄆㄇㄈㄉㄊㄋㄌㄍㄎㄏㄐㄑㄒㄓㄔㄕㄖㄗㄘㄙㄧㄨㄩㄚㄛㄜㄝㄞㄟㄠㄡㄢㄣㄤㄥㄦˊˇˋ˙";
    static final List<List<String>> ETEN_TOUCH_ROWS = List.of(
            List.of("1", "2", "3", "4", "7", "8", "9", "0", "-", "=", "EMOJI"),
            List.of("q", "w", "e", "r", "t", "y", "u", "i", "o", "p", "@"),
            List.of("a", "s", "d", "f", "g", "h", "j", "k", "l", ";", "'"),
            List.of("z", "x", "c", "v", "b", "n", "m", ",", ".", "/", "SHIFT"));

    final String value;
    final String coreValue;
    final String displayName;
    private final String displayKeys;

    BopomofoKeyboardLayout(String value, String coreValue, String displayName, String displayKeys) {
        this.value = value;
        this.coreValue = coreValue;
        this.displayName = displayName;
        this.displayKeys = displayKeys;
    }

    static BopomofoKeyboardLayout fromValue(String value) {
        for (var layout : values()) {
            if (layout.value.equals(value)) return layout;
        }
        return STANDARD;
    }

    // Multirole phonetic keys retain their Latin keycaps.
    String symbolForKey(char key) {
        int index = displayKeys.indexOf(Character.toLowerCase(key));
        return index < 0 ? "" : SYMBOLS.substring(index, index + 1);
    }

    boolean isPhoneticKey(char key) {
        return switch (this) {
            case STANDARD, ETEN -> displayKeys.indexOf(key) >= 0;
            case HSU, ETEN26 -> key >= 'a' && key <= 'z';
            case HANYU_PINYIN -> (key >= 'a' && key <= 'z') || (key >= '2' && key <= '5');
        };
    }

    String punctuation(char key) {
        if (this != HSU) return null;
        return switch (key) {
            case ',' -> "，";
            case '.' -> "。";
            case '<' -> "〈";
            case '>' -> "〉";
            case ':' -> "：";
            case ';' -> "；";
            case '\'' -> "、";
            case '"' -> "”";
            case '-' -> "─";
            case '_' -> "＿";
            default -> null;
        };
    }
}
