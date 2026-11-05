package tw.chichi77.keykey.android;

/** Text-only policy; the keyboard's slots, touch bounds and actions stay unchanged. */
final class KeyboardTypography {
    private KeyboardTypography() {}

    static float keyTextSize(KeyboardLayoutProfile.FontSize size, float normalSize,
            float largeFit) {
        // Constrain the entire family together; clipping a selected level
        // independently can collapse all four choices into the same size.
        float base = Math.min(normalSize,
                largeFit / KeyboardLayoutProfile.FontSize.EXTRA_LARGE.stripScale);
        return base * size.stripScale;
    }
}
