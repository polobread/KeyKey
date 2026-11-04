package tw.chichi77.keykey.android;

/** Text-only policy; the keyboard's slots, touch bounds and actions stay unchanged. */
final class KeyboardTypography {
    private KeyboardTypography() {}

    static float keyTextSize(KeyboardLayoutProfile.FontSize size, float normalSize,
            float largeFit) {
        return switch (size) {
            case NORMAL -> normalSize;
            case MEDIUM -> Math.min(largeFit, normalSize + (largeFit - normalSize) / 3f);
            case LARGE -> Math.min(largeFit, normalSize + (largeFit - normalSize) * 2f / 3f);
            case EXTRA_LARGE -> largeFit;
        };
    }
}
