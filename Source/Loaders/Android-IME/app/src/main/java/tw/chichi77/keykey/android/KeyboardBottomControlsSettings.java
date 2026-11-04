package tw.chichi77.keykey.android;

import android.content.Context;

final class KeyboardBottomControlsSettings {
    static final String KEY_ENABLED = "integrated_keyboard_bottom_controls_enabled";

    private KeyboardBottomControlsSettings() {}

    static boolean enabled(Context context) {
        return CandidateWindowSettings.preferences(context).getBoolean(KEY_ENABLED, false);
    }

    static void setEnabled(Context context, boolean enabled) {
        CandidateWindowSettings.preferences(context).edit().putBoolean(KEY_ENABLED, enabled).apply();
    }
}
