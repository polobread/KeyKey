package tw.chichi77.keykey.android;

enum BopomofoKeyboardLayout {
    STANDARD("Standard", "標準"), HSU("Hsu", "許氏鍵盤");

    final String value;
    final String displayName;

    BopomofoKeyboardLayout(String value, String displayName) {
        this.value = value;
        this.displayName = displayName;
    }

    static BopomofoKeyboardLayout fromValue(String value) {
        return HSU.value.equals(value) ? HSU : STANDARD;
    }

    /** Standard labels printed on FE keys; input parsing belongs to Rust. */
    static String symbolForKey(char key) {
        String keys = "1qaz2wsxedcrfv5tgbYhnujm8ik,9ol.0p;/-6347".toLowerCase(java.util.Locale.ROOT);
        String symbols = "ㄅㄆㄇㄈㄉㄊㄋㄌㄍㄎㄏㄐㄑㄒㄓㄔㄕㄖㄗㄘㄙㄧㄨㄩㄚㄛㄜㄝㄞㄟㄠㄡㄢㄣㄤㄥㄦˊˇˋ˙";
        int index = keys.indexOf(Character.toLowerCase(key));
        return index < 0 ? null : symbols.substring(index, index + 1);
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
