// Copyright (c) 2007-2012, Yahoo! Inc. All rights reserved.
// Copyrights licensed under the New BSD License. See the accompanying LICENSE.
package tw.chichi77.keykey.android;

import java.util.ArrayList;

/** Legacy MJSR phrase syntax conversion only; never used by the input engine. */
final class PhraseReadingCodec {
    private static final String[] KEYS = {"1qaz2wsxedcrfv5tgbYhn", "ujm", "8ik,9ol.0p;/-", "6347"};
    private static final String[] SYMBOLS = {"ㄅㄆㄇㄈㄉㄊㄋㄌㄍㄎㄏㄐㄑㄒㄓㄔㄕㄖㄗㄘㄙ", "ㄧㄨㄩ", "ㄚㄛㄜㄝㄞㄟㄠㄡㄢㄣㄤㄥㄦ", "ˊˇˋ˙"};
    private PhraseReadingCodec() {}
    static String queryForReading(String reading) {
        ArrayList<String> syllables = new ArrayList<>();
        for (String part : reading.trim().split("[\\s,，]+")) {
            StringBuilder current = new StringBuilder();
            for (int offset = 0; offset < part.length();) {
                int point = part.codePointAt(offset);
                offset += Character.charCount(point);
                current.appendCodePoint(point);
                if (("6347ˊˇˋ˙".indexOf(point) >= 0) && current.codePointCount(0,
                        current.length()) > 1) {
                    syllables.add(current.toString());
                    current.setLength(0);
                }
            }
            if (current.length() > 0) syllables.add(current.toString());
        }
        if (syllables.size() < 1 || syllables.size() > 8) return null;
        StringBuilder result = new StringBuilder();
        for (String syllable : syllables) {
            String key = encodeSyllable(syllable);
            if (key == null) return null;
            result.append(key);
        }
        return result.toString();
    }

    static String readingForQuery(String query) {
        if (query == null || query.isEmpty() || query.length() % 2 != 0) return null;
        ArrayList<String> syllables = new ArrayList<>();
        for (int index = 0; index < query.length(); index += 2) {
            String reading = decodeSyllable(
                    query.substring(index, index + 2));
            if (reading == null) return null;
            syllables.add(reading);
        }
        return String.join(" ", syllables);
    }


    private static String encodeSyllable(String text) {
        int[] parts = new int[4];
        for (int offset = 0; offset < text.length(); offset++) {
            char symbol = text.charAt(offset);
            boolean found = false;
            for (int kind = 0; kind < 4; kind++) {
                int index = symbol < 128 ? KEYS[kind].toLowerCase(java.util.Locale.ROOT).indexOf(Character.toLowerCase(symbol)) : SYMBOLS[kind].indexOf(symbol);
                if (index < 0) continue;
                if (parts[kind] != 0) return null;
                parts[kind] = index + 1;
                found = true;
                break;
            }
            if (!found) return null;
        }
        if (parts[0] + parts[1] + parts[2] == 0) return null;
        int order = parts[0] + parts[1] * 22 + parts[2] * 88 + parts[3] * 1232;
        return new String(new char[]{(char) (48 + order % 79), (char) (48 + order / 79)});
    }
    private static String decodeSyllable(String query) {
        if (query.length() != 2) return null;
        int order = query.charAt(0) - 48 + (query.charAt(1) - 48) * 79;
        if (order < 0 || order >= 6160) return null;
        int[] parts = {order % 22, order / 22 % 4, order / 88 % 14, order / 1232};
        StringBuilder text = new StringBuilder();
        for (int kind = 0; kind < 4; kind++) {
            if (parts[kind] > 0) text.append(SYMBOLS[kind].charAt(parts[kind] - 1));
        }
        return text.toString();
    }
}
