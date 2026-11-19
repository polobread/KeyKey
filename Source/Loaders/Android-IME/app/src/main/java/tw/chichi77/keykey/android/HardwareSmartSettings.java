package tw.chichi77.keykey.android;

import android.content.Context;

/** Desktop behavior choices, used only by the hardware bottom strip/floating window. */
final class HardwareSmartSettings {
    static final String CURSOR_AT_END = "candidate_cursor_at_end";
    static final String RETURNS_TO_END = "selection_returns_to_end";
    static final String CLEAR_ESCAPE = "clear_composing_with_escape";
    static final String MAX_SYLLABLES = "max_completed_syllables";
    static final String IGNORE_CAPS = "ignore_caps_lock_in_chinese";
    static final String SHIFT_UPPER = "shift_always_uppercase";
    record Options(boolean omitTone, boolean cursorAtEnd, boolean returnsToEnd,
                   boolean clearEscape, int maxSyllables, boolean ignoreCaps, boolean shiftUpper) {
        static Options defaults() { return new Options(false, false, false, false, 10, false, false); }
    }
    private HardwareSmartSettings() {}
    static boolean enabled(Context context, String name) {
        return KeyboardSettingsProfile.preferences(context).getBoolean(KeyboardSettingsProfile.key(false, name), false);
    }
    static void setEnabled(Context context, String name, boolean enabled) {
        KeyboardSettingsProfile.preferences(context).edit().putBoolean(KeyboardSettingsProfile.key(false, name), enabled).apply();
    }
    static int maxSyllables(Context context) {
        return Math.max(10, Math.min(20, KeyboardSettingsProfile.preferences(context)
                .getInt(KeyboardSettingsProfile.key(false, MAX_SYLLABLES), 10)));
    }
    static void setMaxSyllables(Context context, int count) {
        KeyboardSettingsProfile.preferences(context).edit().putInt(KeyboardSettingsProfile.key(false, MAX_SYLLABLES), Math.max(10, Math.min(20, count))).apply();
    }
    static Options options(Context context) {
        return new Options(BopomofoCompositionModeSettings.omitTone(context, false),
                enabled(context, CURSOR_AT_END), enabled(context, RETURNS_TO_END), enabled(context, CLEAR_ESCAPE),
                maxSyllables(context), enabled(context, IGNORE_CAPS), enabled(context, SHIFT_UPPER));
    }
}
