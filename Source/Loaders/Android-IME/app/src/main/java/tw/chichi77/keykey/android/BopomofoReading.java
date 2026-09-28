// Copyright (c) 2007-2012, Yahoo! Inc. All rights reserved.
// Copyrights licensed under the New BSD License. See the accompanying LICENSE.
// Hsu mapping and disambiguation ported from Formosa/Mandarin.h and Mandarin.cpp.
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

    // Standard-layout component keys in the desktop Hsu disambiguation order.
    private static final Map<Character, String> HSU_KEYS = Map.ofEntries(
            Map.entry('b', "1"), Map.entry('p', "q"), Map.entry('m', "a0"),
            Map.entry('f', "z3"), Map.entry('d', "26"), Map.entry('t', "w"),
            Map.entry('n', "sp"), Map.entry('l', "x/-"), Map.entry('g', "ek"),
            Map.entry('k', "d;"), Map.entry('h', "ci"), Map.entry('j', "r54"),
            Map.entry('v', "ft"), Map.entry('c', "vg"), Map.entry('r', "b"),
            Map.entry('z', "y"), Map.entry('a', "ho"), Map.entry('s', "n7"),
            Map.entry('e', "u,"), Map.entry('x', "j"), Map.entry('u', "m"),
            Map.entry('y', "8"), Map.entry('i', "9"), Map.entry('w', "l"),
            Map.entry('o', "."));

    private BopomofoKeyboardLayout layout = BopomofoKeyboardLayout.STANDARD;

    BopomofoKeyboardLayout layout() { return layout; }

    void setLayout(BopomofoKeyboardLayout layout) {
        clear();
        this.layout = layout;
    }

    boolean isReadingKey(char rawKey) {
        char key = Character.toLowerCase(rawKey);
        return layout == BopomofoKeyboardLayout.HSU
                ? HSU_KEYS.containsKey(key) : isBopomofoKey(key);
    }

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
        if (layout == BopomofoKeyboardLayout.HSU) {
            char key = Character.toLowerCase(rawKey);
            if (!isReadingKey(key)) return false;
            parseHsu(hsuSequence() + key);
            return true;
        }
        Component component = COMPONENTS.get(Character.toLowerCase(rawKey));
        if (component == null) return false;
        addComponent(component);
        return true;
    }

    private void addComponent(Component component) {
        switch (component.kind()) {
            case INITIAL -> initial = component;
            case MEDIAL -> medial = component;
            case FINAL -> finalComponent = component;
            case TONE -> tone = component;
        }
    }

    void backspace() {
        if (layout == BopomofoKeyboardLayout.HSU) {
            String sequence = hsuSequence();
            parseHsu(sequence.isEmpty() ? "" : sequence.substring(0, sequence.length() - 1));
            return;
        }
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

    private String hsuSequence() {
        StringBuilder result = new StringBuilder();
        for (char key : queryKey().toCharArray()) {
            for (Map.Entry<Character, String> entry : HSU_KEYS.entrySet()) {
                if (entry.getValue().indexOf(key) >= 0) {
                    result.append(entry.getKey());
                    break;
                }
            }
        }
        return result.toString();
    }

    private static int mask(Component component) {
        return switch (component.kind()) {
            case INITIAL -> 0x001f;
            case MEDIAL -> 0x0060;
            case FINAL -> 0x0780;
            case TONE -> 0x3800;
        };
    }

    private int maskType() {
        return (initial == null ? 0 : 0x001f) | (medial == null ? 0 : 0x0060)
                | (finalComponent == null ? 0 : 0x0780) | (tone == null ? 0 : 0x3800);
    }

    private static boolean jqx(Component component) {
        return component.packedValue >= 12 && component.packedValue <= 14;
    }

    private static boolean zcsr(Component component) {
        return component.packedValue >= 15 && component.packedValue <= 21;
    }

    private static boolean endOrTone(String sequence, int index) {
        return index == sequence.length() || "dfjs".indexOf(sequence.charAt(index)) >= 0;
    }

    private static boolean containsIorUE(String sequence) {
        return sequence.indexOf('e') >= 0 || sequence.indexOf('u') >= 0;
    }

    private void parseHsu(String sequence) {
        clear();
        for (int index = 0; index < sequence.length(); index++) {
            String keys = HSU_KEYS.get(sequence.charAt(index));
            if (keys == null) continue;
            Component head = COMPONENTS.get(keys.charAt(0));
            if (keys.length() == 1) { addComponent(head); continue; }
            Component follow = COMPONENTS.get(keys.charAt(1));
            Component ending = COMPONENTS.get(keys.charAt(keys.length() - 1));
            boolean beforeHasIorUE = containsIorUE(sequence.substring(0, index));
            boolean aheadHasIorUE = containsIorUE(sequence.substring(index + 1));
            if (head.key == ',' || follow.key == ',') {
                addComponent(beforeHasIorUE ? COMPONENTS.get(',')
                        : (head.key == ',' ? follow : head));
            } else if (jqx(head) != jqx(follow)) {
                if (!isEmpty()) {
                    if (ending != follow) addComponent(ending);
                } else {
                    addComponent(aheadHasIorUE == jqx(head) ? head : follow);
                }
            } else if (sequence.length() == 1) {
                if (head.kind == Kind.FINAL || follow.kind == Kind.TONE || zcsr(head)) {
                    addComponent(head);
                } else {
                    addComponent(follow.kind == Kind.FINAL || ending.kind == Kind.TONE
                            ? follow : ending);
                }
            } else if ((maskType() & mask(head)) == 0 && !endOrTone(sequence, index + 1)) {
                addComponent(head);
            } else if (endOrTone(sequence, index + 1) && zcsr(head) && isEmpty()) {
                addComponent(head);
            } else {
                addComponent(maskType() < mask(follow) ? follow : ending);
            }
        }
        if (finalComponent == COMPONENTS.get('/') && initial == null && medial == null) {
            finalComponent = COMPONENTS.get('-');
        } else if (initial == COMPONENTS.get('e')
                && (medial == COMPONENTS.get('u') || medial == COMPONENTS.get('m'))) {
            initial = COMPONENTS.get('r');
        }
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
