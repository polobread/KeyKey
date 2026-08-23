package tw.chichi77.keykey.android;

final class CandidateDisplayText {
    private static final int MAX_GRAPHEMES = 3;
    private static final int ZERO_WIDTH_JOINER = 0x200D;
    private static final int VARIATION_SELECTOR_START = 0xFE00;
    private static final int VARIATION_SELECTOR_END = 0xFE0F;
    private static final int VARIATION_SELECTOR_SUPPLEMENT_START = 0xE0100;
    private static final int VARIATION_SELECTOR_SUPPLEMENT_END = 0xE01EF;
    private static final int EMOJI_MODIFIER_START = 0x1F3FB;
    private static final int EMOJI_MODIFIER_END = 0x1F3FF;
    private static final int REGIONAL_INDICATOR_START = 0x1F1E6;
    private static final int REGIONAL_INDICATOR_END = 0x1F1FF;

    private CandidateDisplayText() {}

    static String elide(String text) {
        if (text == null || text.isEmpty()) return "";
        int end = 0;
        for (int count = 0; count < MAX_GRAPHEMES && end < text.length(); count++) {
            end = nextGraphemeEnd(text, end);
        }
        return end < text.length() ? text.substring(0, end) + "…" : text;
    }

    private static int nextGraphemeEnd(String text, int start) {
        int end = nextComponentEnd(text, start);
        int first = text.codePointAt(start);
        if (isRegionalIndicator(first) && end < text.length()) {
            int next = text.codePointAt(end);
            if (isRegionalIndicator(next)) end = nextComponentEnd(text, end);
        }
        while (end < text.length() && text.codePointAt(end) == ZERO_WIDTH_JOINER) {
            int joinedStart = end + Character.charCount(ZERO_WIDTH_JOINER);
            if (joinedStart >= text.length()) return text.length();
            end = nextComponentEnd(text, joinedStart);
        }
        return end;
    }

    private static int nextComponentEnd(String text, int start) {
        int end = start + Character.charCount(text.codePointAt(start));
        while (end < text.length() && isExtendingCodePoint(text.codePointAt(end))) {
            end += Character.charCount(text.codePointAt(end));
        }
        return end;
    }

    private static boolean isExtendingCodePoint(int codePoint) {
        int type = Character.getType(codePoint);
        return type == Character.NON_SPACING_MARK
                || type == Character.COMBINING_SPACING_MARK
                || type == Character.ENCLOSING_MARK
                || codePoint >= VARIATION_SELECTOR_START && codePoint <= VARIATION_SELECTOR_END
                || codePoint >= VARIATION_SELECTOR_SUPPLEMENT_START
                        && codePoint <= VARIATION_SELECTOR_SUPPLEMENT_END
                || codePoint >= EMOJI_MODIFIER_START && codePoint <= EMOJI_MODIFIER_END;
    }

    private static boolean isRegionalIndicator(int codePoint) {
        return codePoint >= REGIONAL_INDICATOR_START && codePoint <= REGIONAL_INDICATOR_END;
    }
}
