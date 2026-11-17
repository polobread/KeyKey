package tw.chichi77.keykey.android;

/** Text-only policy; the keyboard's slots, touch bounds and actions stay unchanged. */
final class KeyboardTypography {
    private KeyboardTypography() {}

    static float keyTextSize(KeyboardLayoutProfile.FontSize size, float normalSize,
            float largeFit) {
        return (float) GuanyinmaNative.nativeKeyboardFontSize(size.coreLevel, normalSize, largeFit);
    }
}
