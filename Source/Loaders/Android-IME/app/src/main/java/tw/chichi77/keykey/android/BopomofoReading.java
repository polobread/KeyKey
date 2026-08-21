package tw.chichi77.keykey.android;

import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.Map;

final class BopomofoReading {
    private enum Kind { INITIAL, MEDIAL, FINAL, TONE }

    private static final class Component {
        private final char key;
        private final String symbol;
        private final Kind kind;

        Component(char key, String symbol, Kind kind) {
            this.key = key;
            this.symbol = symbol;
            this.kind = kind;
        }

        char key() { return key; }
        String symbol() { return symbol; }
        Kind kind() { return kind; }
    }

    private static final Map<Character, Component> COMPONENTS;

    static {
        Map<Character, Component> values = new LinkedHashMap<>();
        add(values, Kind.INITIAL, "1qaz2wsxedcrfv5tgbYhn",
                new String[]{"ㄅ", "ㄆ", "ㄇ", "ㄈ", "ㄉ", "ㄊ", "ㄋ", "ㄌ", "ㄍ", "ㄎ", "ㄏ",
                        "ㄐ", "ㄑ", "ㄒ", "ㄓ", "ㄔ", "ㄕ", "ㄖ", "ㄗ", "ㄘ", "ㄙ"});
        add(values, Kind.MEDIAL, "ujm", new String[]{"ㄧ", "ㄨ", "ㄩ"});
        add(values, Kind.FINAL, "8ik,9ol.0p;/-",
                new String[]{"ㄚ", "ㄛ", "ㄜ", "ㄝ", "ㄞ", "ㄟ", "ㄠ", "ㄡ", "ㄢ", "ㄣ", "ㄤ", "ㄥ", "ㄦ"});
        add(values, Kind.TONE, "6347", new String[]{"ˊ", "ˇ", "ˋ", "˙"});
        COMPONENTS = Collections.unmodifiableMap(values);
    }

    private Component initial;
    private Component medial;
    private Component finalComponent;
    private Component tone;

    boolean combine(char rawKey) {
        Component component = COMPONENTS.get(Character.toLowerCase(rawKey));
        if (component == null) return false;
        switch (component.kind()) {
            case INITIAL -> initial = component;
            case MEDIAL -> medial = component;
            case FINAL -> finalComponent = component;
            case TONE -> tone = component;
        }
        return true;
    }

    void backspace() {
        if (tone != null) tone = null;
        else if (finalComponent != null) finalComponent = null;
        else if (medial != null) medial = null;
        else initial = null;
    }

    void clear() {
        initial = null;
        medial = null;
        finalComponent = null;
        tone = null;
    }

    boolean isEmpty() {
        return initial == null && medial == null && finalComponent == null && tone == null;
    }

    boolean hasTone() {
        return tone != null;
    }

    String queryKey() {
        StringBuilder result = new StringBuilder(4);
        appendKey(result, initial);
        appendKey(result, medial);
        appendKey(result, finalComponent);
        appendKey(result, tone);
        return result.toString();
    }

    String displayText() {
        StringBuilder result = new StringBuilder(4);
        appendSymbol(result, initial);
        appendSymbol(result, medial);
        appendSymbol(result, finalComponent);
        appendSymbol(result, tone);
        return result.toString();
    }

    static boolean isBopomofoKey(char key) {
        return COMPONENTS.containsKey(Character.toLowerCase(key));
    }

    static String symbolForKey(char key) {
        Component component = COMPONENTS.get(Character.toLowerCase(key));
        return component == null ? "" : component.symbol();
    }

    private static void add(Map<Character, Component> target, Kind kind, String keys, String[] symbols) {
        if (keys.length() != symbols.length) throw new IllegalArgumentException("Key map length mismatch");
        for (int i = 0; i < keys.length(); i++) {
            char key = Character.toLowerCase(keys.charAt(i));
            target.put(key, new Component(key, symbols[i], kind));
        }
    }

    private static void appendKey(StringBuilder target, Component value) {
        if (value != null) target.append(value.key());
    }

    private static void appendSymbol(StringBuilder target, Component value) {
        if (value != null) target.append(value.symbol());
    }
}
