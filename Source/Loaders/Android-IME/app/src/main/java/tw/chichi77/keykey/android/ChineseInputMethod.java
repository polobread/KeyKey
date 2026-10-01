package tw.chichi77.keykey.android;

/** Chinese method selection survives switches to English and number planes. */
enum ChineseInputMethod {
    SMART("好打注音", "ㄅ"), TRADITIONAL("傳統注音", "ㄅ"), CANGJIE("倉頡", "倉"), SIMPLEX("簡易", "簡");
    final String displayName;
    final String symbol;
    ChineseInputMethod(String name, String symbol) { this.displayName = name; this.symbol = symbol; }
    boolean isTable() { return this == CANGJIE || this == SIMPLEX; }
    int maximumCodeLength() { return this == SIMPLEX ? 2 : 5; }
    String tableName() { return this == SIMPLEX ? "Generic-simplex-cin" : "Generic-cj-cin"; }
    static String root(String key) {
        if (key.length() != 1) return "";
        char c = Character.toLowerCase(key.charAt(0));
        return c >= 'a' && c <= 'z' ? "日月金木水火土竹戈十大中一弓人心手口尸廿山女田難卜重".substring(c - 'a', c - 'a' + 1) : "";
    }
}
