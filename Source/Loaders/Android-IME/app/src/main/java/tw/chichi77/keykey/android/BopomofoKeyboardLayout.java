package tw.chichi77.keykey.android;

enum BopomofoKeyboardLayout {
    STANDARD("Standard", "標準"), HSU("Hsu", "許氏");

    final String value;
    final String displayName;

    BopomofoKeyboardLayout(String value, String displayName) {
        this.value = value;
        this.displayName = displayName;
    }

    static BopomofoKeyboardLayout fromValue(String value) {
        return HSU.value.equals(value) ? HSU : STANDARD;
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
