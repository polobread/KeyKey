package tw.chichi77.keykey.android;

final class TextDeletion {
    private static final int ZERO_WIDTH_JOINER = 0x200D;
    private static final int VARIATION_SELECTOR_START = 0xFE00;
    private static final int VARIATION_SELECTOR_END = 0xFE0F;
    private static final int VARIATION_SELECTOR_SUPPLEMENT_START = 0xE0100;
    private static final int VARIATION_SELECTOR_SUPPLEMENT_END = 0xE01EF;
    private static final int EMOJI_MODIFIER_START = 0x1F3FB;
    private static final int EMOJI_MODIFIER_END = 0x1F3FF;
    private static final int REGIONAL_INDICATOR_START = 0x1F1E6;
    private static final int REGIONAL_INDICATOR_END = 0x1F1FF;

    private TextDeletion() {}

    static int previousGraphemeLength(CharSequence beforeCursor) {
        if (beforeCursor == null || beforeCursor.length() == 0) return 0;
        String text = beforeCursor.toString();
        int end = text.length();
        int start = previousComponentStart(text, end);

        int base = text.codePointAt(start);
        if (isRegionalIndicator(base) && start > 0) {
            int previousStart = previousComponentStart(text, start);
            if (isRegionalIndicator(text.codePointAt(previousStart))) start = previousStart;
        }

        while (start > 0) {
            int joinerStart = text.offsetByCodePoints(start, -1);
            if (text.codePointAt(joinerStart) != ZERO_WIDTH_JOINER) break;
            start = joinerStart;
            if (start > 0) start = previousComponentStart(text, start);
        }
        return end - start;
    }

    private static int previousComponentStart(String text, int end) {
        int start = end;
        int codePoint;
        do {
            start = text.offsetByCodePoints(start, -1);
            codePoint = text.codePointAt(start);
        } while (start > 0 && isExtendingCodePoint(codePoint));
        return start;
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
