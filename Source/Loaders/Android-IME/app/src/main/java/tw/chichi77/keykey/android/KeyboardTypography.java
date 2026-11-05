package tw.chichi77.keykey.android;

/** Text-only policy; the keyboard's slots, touch bounds and actions stay unchanged. */
final class KeyboardTypography {
    private KeyboardTypography() {}

    static float keyTextSize(KeyboardLayoutProfile.FontSize size, float normalSize,
            float largeFit) {
        float standard = Math.min(normalSize, largeFit);
        if (size == KeyboardLayoutProfile.FontSize.NORMAL) return standard;
        if (size == KeyboardLayoutProfile.FontSize.EXTRA_LARGE) return largeFit;
        // Equal multiplicative steps between the two space-derived endpoints.
        return (float) (standard * Math.pow(largeFit / standard, size.ordinal() / 3.0));
    }
}
