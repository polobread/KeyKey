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
        private final int packedValue;

        Component(char key, String symbol, Kind kind, int packedValue) {
            this.key = key;
            this.symbol = symbol;
            this.kind = kind;
            this.packedValue = packedValue;
        }

        char key() { return key; }
        String symbol() { return symbol; }
        Kind kind() { return kind; }
        int packedValue() { return packedValue; }
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

    /** The two-byte absolute-order key used by the cooked macOS/iOS language model. */
    String languageModelKey() {
        int packed = value(initial) | value(medial) | value(finalComponent) | value(tone);
        int absoluteOrder = (packed & 0x001f)
                + ((packed & 0x0060) >> 5) * 22
                + ((packed & 0x0780) >> 7) * 22 * 4
                + ((packed & 0x3800) >> 11) * 22 * 4 * 14;
        char low = (char) (48 + absoluteOrder % 79);
        char high = (char) (48 + absoluteOrder / 79);
        return new String(new char[]{low, high});
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

    static String languageModelKeyForReading(String text) {
        BopomofoReading reading = new BopomofoReading();
        boolean initialSeen = false, medialSeen = false, finalSeen = false, toneSeen = false;
        for (int offset = 0; offset < text.length();) {
            int point = text.codePointAt(offset);
            offset += Character.charCount(point);
            Component match = point < 128 ? COMPONENTS.get(Character.toLowerCase((char) point))
                    : null;
            if (match == null) {
                for (Component component : COMPONENTS.values()) {
                    if (component.symbol().codePointAt(0) == point) {
                        match = component;
                        break;
                    }
                }
            }
            if (match == null) return null;
            switch (match.kind()) {
                case INITIAL -> {
                    if (initialSeen) return null;
                    initialSeen = true;
                }
                case MEDIAL -> {
                    if (medialSeen) return null;
                    medialSeen = true;
                }
                case FINAL -> {
                    if (finalSeen) return null;
                    finalSeen = true;
                }
                case TONE -> {
                    if (toneSeen) return null;
                    toneSeen = true;
                }
            }
            reading.combine(match.key());
        }
        return initialSeen || medialSeen || finalSeen ? reading.languageModelKey() : null;
    }

    static String readingForLanguageModelKey(String key) {
        if (key.length() != 2) return null;
        int order = key.charAt(0) - 48 + (key.charAt(1) - 48) * 79;
        if (order < 0 || order >= 6160) return null;
        int initial = order % 22;
        int medial = order / 22 % 4;
        int last = order / 88 % 14;
        int tone = order / 1232;
        StringBuilder result = new StringBuilder();
        appendPackedSymbol(result, Kind.INITIAL, initial);
        appendPackedSymbol(result, Kind.MEDIAL, medial << 5);
        appendPackedSymbol(result, Kind.FINAL, last << 7);
        appendPackedSymbol(result, Kind.TONE, tone << 11);
        return result.toString();
    }

    private static void appendPackedSymbol(StringBuilder result, Kind kind, int value) {
        if (value == 0) return;
        for (Component component : COMPONENTS.values()) {
            if (component.kind() == kind && component.packedValue() == value) {
                result.append(component.symbol());
                return;
            }
        }
    }

    private static void add(Map<Character, Component> target, Kind kind, String keys, String[] symbols) {
        if (keys.length() != symbols.length) throw new IllegalArgumentException("Key map length mismatch");
        for (int i = 0; i < keys.length(); i++) {
            char key = Character.toLowerCase(keys.charAt(i));
            int packedValue = switch (kind) {
                case INITIAL -> i + 1;
                case MEDIAL -> (i + 1) << 5;
                case FINAL -> (i + 1) << 7;
                case TONE -> (i + 1) << 11;
            };
            target.put(key, new Component(key, symbols[i], kind, packedValue));
        }
    }

    private static int value(Component component) {
        return component == null ? 0 : component.packedValue();
    }

    private static void appendKey(StringBuilder target, Component value) {
        if (value != null) target.append(value.key());
    }

    private static void appendSymbol(StringBuilder target, Component value) {
        if (value != null) target.append(value.symbol());
    }
}
