package tw.chichi77.keykey.android;

import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.function.Predicate;

/** Best 36 visible values, stable within a rank, without retaining the whole query. */
final class CangjiePrefixSelection {
    static final int LIMIT = 36;
    private final Set<String> seen;
    private final ArrayList<String> values = new ArrayList<>();
    CangjiePrefixSelection(List<String> excluding) {
        seen = new HashSet<>();
        for (String text : excluding) seen.add(CangjieCommonRanking.identity(text));
    }
    static boolean isPrefixCode(String code) {
        if (code.isEmpty() || code.length() > 4) return false;
        for (int i = 0; i < code.length(); i++)
            if (code.charAt(i) < 'a' || code.charAt(i) > 'z') return false;
        return true;
    }
    private static int rank(String text) {
        return CangjieCommonRanking.rank(text);
    }
    void consider(String text, Predicate<String> filter) {
        if (text.isEmpty()) return;
        String identity = CangjieCommonRanking.identity(text);
        if (seen.contains(identity)) return;
        int cp = text.codePointAt(0);
        int type = Character.getType(cp);
        if (Character.isWhitespace(cp) || switch (type) {
            case Character.CONNECTOR_PUNCTUATION, Character.DASH_PUNCTUATION,
                 Character.START_PUNCTUATION, Character.END_PUNCTUATION,
                 Character.INITIAL_QUOTE_PUNCTUATION, Character.FINAL_QUOTE_PUNCTUATION,
                 Character.OTHER_PUNCTUATION, Character.SPACE_SEPARATOR, Character.LINE_SEPARATOR,
                 Character.PARAGRAPH_SEPARATOR, Character.MATH_SYMBOL, Character.CURRENCY_SYMBOL,
                 Character.MODIFIER_SYMBOL, Character.OTHER_SYMBOL -> true;
            default -> false;
        }) return;
        int rank = rank(text);
        if (values.size() == LIMIT && rank >= rank(values.get(values.size() - 1))) return;
        if (!filter.test(text)) return;
        seen.add(identity);
        int index = 0;
        while (index < values.size() && rank(values.get(index)) <= rank) index++;
        values.add(index, text);
        if (values.size() > LIMIT) values.remove(values.size() - 1);
    }
    List<String> values() { return List.copyOf(values); }
}
